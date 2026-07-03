import AppKit
import LidopenCore

@MainActor
final class AppRuntime {
    private let appModel: AppModel
    private let menuBarController: MenuBarController
    private let eventMonitor: DisplayEventMonitor
    private let controller: DisplayController

    init(appModel: AppModel, controller: DisplayController) {
        self.appModel = appModel
        self.menuBarController = MenuBarController(appModel: appModel)
        self.eventMonitor = DisplayEventMonitor(controller: controller)
        self.controller = controller
    }

    func start() {
        eventMonitor.start()
        controller.bootstrap()
    }

    func prepareForTermination() {
        controller.prepareForTermination()
        eventMonitor.stop()
    }
}

enum AppRuntimeFactory {
    @MainActor
    static func makeDefaultRuntime() -> AppRuntime {
        let settingsStore = UserDefaultsSettingsStore()
        let logger = EventLogger()
        let controller = DisplayController(
            snapshotProvider: SystemDisplaySnapshotProvider(),
            policy: DisplayPolicy(),
            // CGSConfigureDisplayEnabled is the only approach that has worked reliably here.
            backend: CGSDisplayEnableBackend(),
            settingsStore: settingsStore,
            logger: logger
        )

        return AppRuntime(
            appModel: AppModel(
                settingsStore: settingsStore,
                controller: controller,
                logger: logger
            ),
            controller: controller
        )
    }
}
