import Foundation
import SwiftUI
import Combine
import Alamofire
import AppKit
#if canImport(GoogleSignIn)
import GoogleSignIn
#endif

class AppState: ObservableObject {
    let isTestMode: Bool
    private let appConfig = AppConfig.current

    // Persistent selection storage using @AppStorage
    @Published var selectedStructureID: String = UserDefaults.standard.string(forKey: "selectedStructureID") ?? "" {
        didSet { UserDefaults.standard.set(selectedStructureID, forKey: "selectedStructureID") }
    }
    @Published var selectedDeviceID: String = UserDefaults.standard.string(forKey: "selectedDeviceID") ?? "" {
        didSet { UserDefaults.standard.set(selectedDeviceID, forKey: "selectedDeviceID") }
    }
    @AppStorage("pubSubTopicID") var customPubSubTopicID: String = ""

    @Published var currentTemperatureCelsius: Double?
    @Published var selectedDeviceConnectionHealth: ConnectionHealth = .unknown
    @Published var sdmAccessToken: String = "" {
        didSet {
            if isTestMode {
                if sdmAccessToken.isEmpty, !oldValue.isEmpty {
                    resetAuthenticatedSessionState()
                }
                return
            }

            if sdmAccessToken.isEmpty {
                if !oldValue.isEmpty {
                    resetAuthenticatedSessionState()
                }
                KeychainManager.delete(for: "sdmAccessToken")
                storeSDMAccessTokenExpiration(nil)
                tokenRefreshTimer?.invalidate()
                tokenRefreshTimer = nil
                hasStartedSessionBootstrap = false
                cancelRetryWorkItems()
                resetRetryBackoffs()
            } else {
                if sdmAccessToken != oldValue {
                    authSessionVersion += 1
                }
                if oldValue.isEmpty {
                    hasStartedSessionBootstrap = false
                }
                KeychainManager.store(token: sdmAccessToken, for: "sdmAccessToken")
                scheduleAutoRefresh()
                if !isRestoringSession {
                    startSessionBootstrapIfNeeded()
                    if workloadIdentityProvider?.isTokenValid == true {
                        startPubSubSyncIfNeeded()
                    }
                }
            }
        }
    }
    @Published var userInfo: GoogleUserProfile?
    @Published var availableStructures: [Structure] = [] {
        didSet {
            if selectedStructure == nil || !availableStructures.contains(where: { $0.id == selectedStructure?.id }) {
                if let first = availableStructures.first {
                    print("AppState: Defaulting to first structure: \(first.displayName)")
                    selectedStructure = first
                } else {
                    selectedStructure = nil
                }
            }
        }
    }
    @Published var selectedStructure: Structure? {
        didSet {
            if let structureID = selectedStructure?.id {
                selectedStructureID = structureID
                print("AppState: Saved selected structure ID: \(structureID)")
            } else {
                selectedStructureID = ""
                print("AppState: Cleared selected structure ID")
            }
        }
    }
    @Published var availableThermostats: [GoogleSDMThermostatDevice] = [] {
        didSet {
            if selectedDevice == nil || !availableThermostats.contains(where: { $0.id == selectedDevice?.id }) {
                if let first = availableThermostats.first {
                    print("AppState: Defaulting to first device: \(first.displayName)")
                    selectedDevice = first
                } else {
                    selectedDevice = nil
                }
            }
        }
    }
    @Published var selectedDevice: GoogleSDMThermostatDevice? {
        didSet {
            if let deviceID = selectedDevice?.id {
                selectedDeviceID = deviceID
                print("AppState: Saved selected device ID: \(deviceID)")
            } else {
                selectedDeviceID = ""
                print("AppState: Cleared selected device ID")
            }
            updateSelectedDeviceConnectionHealth()
            refreshSelectedDeviceAfterSelectionChange(oldDeviceID: oldValue?.id)
        }
    }
    @Published var temperatureUnit: TemperatureUnit = .fahrenheit {
        didSet { objectWillChange.send() }
    }
    @Published var isPopoverVisible: Bool = false {
        didSet {
            if isPopoverVisible != oldValue && !sdmAccessToken.isEmpty {
                scheduleDevicePolling()
            }
        }
    }

    static let lastNetworkDeviceUpdateKey = "lastNetworkDeviceUpdateTime"
    static let stateFreshnessInterval: TimeInterval = 15.0
    static let maxRememberedPubSubEventIDs = 500

    var lastNetworkSnapshotTimesByDeviceID: [String: TimeInterval] = [:]
    var lastFullSnapshotTimesByDeviceID: [String: TimeInterval] = [:]
    var lastTraitEventTimesByDeviceID: [String: [String: Date]] = [:]
    var processedPubSubEventIDs: Set<String> = []
    var processedPubSubEventIDOrder: [String] = []

    var deviceAccessEnterpriseID: String { appConfig.deviceAccessEnterpriseID }
    var devicePollingTimer: Timer?
    var tokenRefreshTimer: Timer?
    var isRefreshingToken: Bool = false
    @Published var authenticationStatus: AuthenticationStatus = .signedOut
    var authenticationRequest: ((@escaping (Result<GoogleSessionTokens, Error>) -> Void) -> Void)?
    var authenticationAttemptID = UUID()
    var authenticationRetryDelay: TimeInterval = 5
    var nextAuthenticationAttempt: Date?
    var lastAuthenticationAttempt: Date?
    var hasRestorableGoogleSession = false
    var testTokenExpiration: Date?
    var pollManager = PollManager()
    var httpSession: Session = AF

    var cancellables = Set<AnyCancellable>()
    var hasStartedSessionBootstrap = false

    var structuresRetryWorkItem: DispatchWorkItem?
    var devicesRetryWorkItem: DispatchWorkItem?
    var userInfoRetryWorkItem: DispatchWorkItem?

    var pubSubSubscriptionResourceName: String?
    var pubSubSubscriptionSetupTask: Task<Void, Never>?
    var scheduledPubSubRetry: DispatchWorkItem?
    var pubSubPollingTask: Task<Void, Never>?
    var isPubSubActive: Bool = false
    var consecutiveAuthFailures: Int = 0
    var consecutiveNetworkFailures: Int = 0
    var pubSubBackoffDelay: TimeInterval = 1.0
    var latestPubSubError: PubSubError?

    var structuresRetryDelay: TimeInterval = 5
    var devicesRetryDelay: TimeInterval = 5
    var userInfoRetryDelay: TimeInterval = 5

    var notificationObservers: [Any] = []

    weak var menuBarStatusController: MenuBarStatusItemController?
    var workloadIdentityProvider: WorkloadIdentityTokenProvider? {
        didSet {
            attachWorkloadIdentityTokenListener()
        }
    }

    var workloadIdentityTokenSubscription: AnyCancellable?
    var promptShownEmails: Set<String> = []
    var authSessionVersion: Int = 0
    var isRestoringSession: Bool = false

    var pubSubAccessToken: String { workloadIdentityProvider?.serviceAccountAccessToken ?? "" }
    var hasValidatedPubSubTopic: Bool = false

    /// Tracks the timestamp of the last processed event or successful fetch.
    /// Used to ignore old/backlog PubSub messages that might cause UI flashing.
    var lastProcessedPubSubEventTime: Date = Date.distantPast

    init(testMode: Bool = false) {
        self.isTestMode = testMode
        if testMode {
            return
        }

        isRestoringSession = true
        authenticationStatus = .restoring
        hasRestorableGoogleSession = UserDefaults.standard.bool(forKey: "hasAuthorizedGoogleSession")
        if let savedToken = KeychainManager.retrieve(for: "sdmAccessToken") {
            self.sdmAccessToken = savedToken
            hasRestorableGoogleSession = true
        }
        if UserDefaults.standard.bool(forKey: "googleReauthenticationRequired") {
            authenticationStatus = .reauthenticationRequired
            isRestoringSession = false
        }
        AuthenticationDiagnostics.record("app_started")
        refreshTokenIfNeeded(force: true)
        setupNotificationObservers()
    }

    deinit {
        cleanup()
    }
}
