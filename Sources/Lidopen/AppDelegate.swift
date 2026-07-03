import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var runtime: AppRuntime?

    func applicationDidFinishLaunching(_ notification: Notification) {
        runtime = AppRuntimeFactory.makeDefaultRuntime()
        runtime?.start()
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        runtime?.prepareForTermination()
        return .terminateNow
    }
}
