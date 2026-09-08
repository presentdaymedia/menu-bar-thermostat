import SwiftUI
import AppKit

@main
struct MenuBarThermostatApp: App {
    @StateObject private var appState: AppState
    @StateObject private var menuBarStatusController: MenuBarStatusItemController
    @StateObject private var workloadIdentityProvider: WorkloadIdentityTokenProvider

    private let popover: NSPopover

    init() {
        let workloadIdentityProvider = WorkloadIdentityTokenProvider()
        let appStateModel = AppState()
        self._appState = StateObject(wrappedValue: appStateModel)
        self._workloadIdentityProvider = StateObject(wrappedValue: workloadIdentityProvider)

        let menuBarPopover = NSPopover()
        menuBarPopover.contentSize = NSSize(width: 300, height: 400)
        menuBarPopover.behavior = .transient
        menuBarPopover.animates = true
        menuBarPopover.contentViewController = NSHostingController(
            rootView: MenuBarPopoverView()
                .environmentObject(appStateModel)
                .environmentObject(workloadIdentityProvider)
        )

        let menuBarStatusController = MenuBarStatusItemController(popover: menuBarPopover, appState: appStateModel)
        self._menuBarStatusController = StateObject(wrappedValue: menuBarStatusController)

        appStateModel.menuBarStatusController = menuBarStatusController
        appStateModel.workloadIdentityProvider = workloadIdentityProvider

        self.popover = menuBarPopover

        NSApplication.shared.setActivationPolicy(.accessory)


    }

    var body: some Scene {
        Settings {
            EmptyView()
        }
        .onChange(of: appState.displayTemperature) { _, _ in
            menuBarStatusController.updateStatusItemButton()
        }
        .onChange(of: appState.sdmAccessToken) { _, _ in
            menuBarStatusController.updateStatusItemButton()
        }
        .onChange(of: appState.selectedDevice?.traits.thermostatHvac?.status) { _, _ in
            menuBarStatusController.updateStatusItemButton()
        }
    }
}
