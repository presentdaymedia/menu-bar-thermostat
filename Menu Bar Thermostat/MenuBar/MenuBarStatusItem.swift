import SwiftUI
import AppKit
import Combine

struct MenuBarStatusItemModifier: ViewModifier {
    let statusItem: NSStatusItem

    func body(content: Content) -> some View {
        content
            .task {
                if let button = statusItem.button {
                    button.contentTintColor = .systemYellow
                }
            }
    }
}

class MenuBarPopoverDelegate: NSObject, NSPopoverDelegate {
    private let popover: NSPopover
    private let appState: AppState

    init(popover: NSPopover, appState: AppState) {
        self.popover = popover
        self.appState = appState
        super.init()

        popover.delegate = self
    }

    @objc func statusItemClicked(_ sender: NSStatusBarButton) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            if self.popover.isShown {
                self.popover.performClose(nil)
            } else {
                self.popover.show(relativeTo: sender.bounds, of: sender, preferredEdge: .minY)
            }
        }
    }

    func popoverWillShow(_ notification: Notification) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            print("📱 MenuBarPopoverDelegate: Popover will show - setting isPopoverVisible = true")
            self.appState.isPopoverVisible = true
        }
    }

    func popoverDidClose(_ notification: Notification) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            print("📱 MenuBarPopoverDelegate: Popover did close - setting isPopoverVisible = false")
            self.appState.isPopoverVisible = false
        }
    }
}

class MenuBarStatusItemController: ObservableObject {
    private var statusItem: NSStatusItem
    private let statusItemDelegate: MenuBarPopoverDelegate
    private let appState: AppState

    private var loadingIndicatorTimer: Timer?
    private var loadingDotCount: Int = 0
    private let iconCache = NSCache<NSString, NSImage>()
    private var cancellables = Set<AnyCancellable>()

    init(popover: NSPopover, appState: AppState) {
        self.appState = appState
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        self.statusItemDelegate = MenuBarPopoverDelegate(popover: popover, appState: appState)

        if let button = statusItem.button {
            button.target = statusItemDelegate
            button.action = #selector(MenuBarPopoverDelegate.statusItemClicked(_:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }

        appState.$currentTemperatureCelsius
            .removeDuplicates { lhs, rhs in
                switch (lhs, rhs) {
                case (nil, nil): return true
                case let (l?, r?): return abs(l - r) < 0.01
                default: return false
                }
            }
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.updateStatusItemButton() }
            .store(in: &cancellables)

        appState.$sdmAccessToken
            .removeDuplicates()
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.updateStatusItemButton() }
            .store(in: &cancellables)

        appState.$selectedDevice
            .map { $0?.traits.thermostatHvac?.status }
            .removeDuplicates()
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.updateStatusItemButton() }
            .store(in: &cancellables)

        appState.$selectedDevice
            .map { $0?.traits.connectivity?.status }
            .removeDuplicates()
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.updateStatusItemButton() }
            .store(in: &cancellables)

        appState.$selectedDeviceConnectionHealth
            .removeDuplicates()
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.updateStatusItemButton() }
            .store(in: &cancellables)

        updateStatusItemButton()
    }

    func updateStatusItemButton() {
        guard let button = statusItem.button else {
#if DEBUG
            print("MenuBarStatusItemController: No button available for status item")
#endif
            return
        }

        func stopDotAnimation() {
            loadingIndicatorTimer?.invalidate()
            loadingIndicatorTimer = nil
            loadingDotCount = 0
        }

        if appState.sdmAccessToken.isEmpty {
            stopDotAnimation()
#if DEBUG
            print("MenuBarStatusItemController: No access token, showing leaf icon")
#endif
            button.attributedTitle = NSAttributedString(string: "")
            button.image = NSImage(systemSymbolName: "leaf.fill", accessibilityDescription: "Not connected")
            button.imagePosition = .imageOnly
            return
        }

        let isOffline = appState.selectedDevice?.traits.connectivity?.status == "OFFLINE"
        if appState.selectedDeviceConnectionHealth == .disconnected || isOffline {
            stopDotAnimation()
            button.attributedTitle = NSAttributedString(string: "")
            button.image = NSImage(systemSymbolName: "wifi.slash", accessibilityDescription: "Disconnected")
            button.imagePosition = .imageOnly
            return
        }

        if let temperature = appState.displayTemperature {
            stopDotAnimation()
            let roundedTemp = Int(round(temperature))
            let hvacStatus = appState.selectedDevice?.traits.thermostatHvac?.status ?? "UNKNOWN"
#if DEBUG
            print("MenuBarStatusItemController: Updating with temp \(roundedTemp)° and HVAC status \(hvacStatus)")
#endif

            button.image = makeTemperatureStatusIcon(temp: roundedTemp, hvacStatus: hvacStatus)
            button.imagePosition = .imageOnly
            button.attributedTitle = NSAttributedString(string: "")
        } else {
            if loadingIndicatorTimer == nil {
                loadingIndicatorTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
                    guard let self, let button = self.statusItem.button else { return }
                    self.loadingDotCount = (self.loadingDotCount % 3) + 1
                    let dots = String(repeating: ".", count: self.loadingDotCount)
                    let padded = dots.padding(toLength: 3, withPad: " ", startingAt: 0)
                    button.attributedTitle = NSAttributedString(string: padded)
                }
            }
            button.image = nil
            let initialDots = String(repeating: ".", count: (loadingDotCount == 0 ? 1 : loadingDotCount))
            button.attributedTitle = NSAttributedString(string: initialDots.padding(toLength: 3, withPad: " ", startingAt: 0))
        }
    }

    deinit {
        loadingIndicatorTimer?.invalidate()
        NSStatusBar.system.removeStatusItem(statusItem)
        cancellables.removeAll()
#if DEBUG
        print("MenuBarStatusItemController: Status item cleaned up")
#endif
    }

    private func makeTemperatureStatusIcon(temp: Int, hvacStatus: String) -> NSImage {
        let key = "\(temp)-\(hvacStatus)" as NSString
        if let cached = iconCache.object(forKey: key) { return cached }

        let size = NSSize(width: 20, height: 20)
        let image = NSImage(size: size, flipped: false) { _ in
            let circlePath = NSBezierPath(ovalIn: NSRect(x: 1, y: 1, width: 18, height: 18))
            circlePath.lineWidth = 1.5

            switch hvacStatus {
            case "HEATING": NSColor.systemRed.setStroke()
            case "COOLING": NSColor.systemBlue.setStroke()
            default: NSColor.labelColor.setStroke()
            }

            circlePath.stroke()

            let text = "\(temp)"
            let font = NSFont.systemFont(ofSize: 9.5, weight: .medium)
            let attrs: [NSAttributedString.Key: Any] = [
                .font: font,
                .foregroundColor: NSColor.labelColor
            ]
            let textSize = text.size(withAttributes: attrs)
            let x = (size.width - textSize.width) / 2 + 0.25
            let y = (size.height - textSize.height) / 2 - 0.5
            text.draw(at: NSPoint(x: x, y: y), withAttributes: attrs)
            return true
        }

        iconCache.setObject(image, forKey: key)
        return image
    }
}
