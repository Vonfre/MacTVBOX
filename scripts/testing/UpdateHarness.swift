import AppKit
import Combine
import Foundation

@MainActor
final class UpdateHarnessDelegate: NSObject, NSApplicationDelegate {
    private var updater: UpdateController?
    private var observation: AnyCancellable?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let updater = UpdateController()
        self.updater = updater
        observation = updater.$status.sink { status in
            print("UPDATE_STATUS: \(status)")
            fflush(stdout)
            if status.contains("将在退出时自动安装") || status == "当前已是最新版本" || status.contains("更新检查未完成") || status.contains("启动失败") {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    NSApplication.shared.terminate(nil)
                }
            }
        }
        updater.start()
        print("UPDATE_DEFAULTS: checks=\(updater.automaticallyChecks) installs=\(updater.automaticallyInstalls)")
        DispatchQueue.main.asyncAfter(deadline: .now() + 45) {
            print("UPDATE_TIMEOUT")
            fflush(stdout)
            NSApplication.shared.terminate(nil)
        }
    }
}

@main
struct UpdateHarness {
    @MainActor static func main() {
        let app = NSApplication.shared
        let delegate = UpdateHarnessDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        app.run()
        withExtendedLifetime(delegate) {}
    }
}
