import AppKit
import Combine
import Sparkle

/// Sparkle owns version comparison, authenticated downloads and atomic installation.
/// Keep a single controller alive for the lifetime of the app (not one per window).
@MainActor
final class UpdateController: NSObject, ObservableObject, SPUUpdaterDelegate {
    @Published private(set) var canCheckForUpdates = false
    @Published private(set) var automaticallyChecks = false
    @Published private(set) var automaticallyInstalls = false
    @Published private(set) var status = "正在初始化更新服务…"
    private var controller: SPUStandardUpdaterController!
    private var observations: [NSKeyValueObservation] = []
    private var started = false

    override init() {
        super.init()
        controller = SPUStandardUpdaterController(startingUpdater: false, updaterDelegate: self, userDriverDelegate: nil)
        let updater = controller.updater
        observations = [
            updater.observe(\.canCheckForUpdates, options: [.initial, .new]) { [weak self] _, change in
                DispatchQueue.main.async { self?.canCheckForUpdates = change.newValue ?? false }
            },
            updater.observe(\.automaticallyChecksForUpdates, options: [.initial, .new]) { [weak self] _, change in
                DispatchQueue.main.async { self?.automaticallyChecks = change.newValue ?? false }
            },
            updater.observe(\.automaticallyDownloadsUpdates, options: [.initial, .new]) { [weak self] _, change in
                DispatchQueue.main.async { self?.automaticallyInstalls = change.newValue ?? false }
            }
        ]
    }

    func start() {
        guard !started else { return }
        started = true
        // Bare `swift run` executables lack a signed app bundle and cannot self-update.
        guard Bundle.main.bundleURL.pathExtension == "app" else {
            status = "请运行打包后的 MacTVBOX.app 以启用更新"
            return
        }
        do {
            try controller.updater.start()
            status = "尚未发现新版本"
            if controller.updater.automaticallyChecksForUpdates {
                controller.updater.checkForUpdatesInBackground()
            }
        } catch {
            status = "更新服务启动失败：\(error.localizedDescription)"
        }
    }

    func checkForUpdates() { controller.checkForUpdates(nil) }

    func setAutomaticallyChecks(_ enabled: Bool) {
        controller.updater.automaticallyChecksForUpdates = enabled
    }

    func setAutomaticallyInstalls(_ enabled: Bool) {
        controller.updater.automaticallyDownloadsUpdates = enabled
    }

    func updater(_ updater: SPUUpdater, didFindValidUpdate item: SUAppcastItem) {
        status = "发现新版本 \(item.displayVersionString)"
    }

    func updaterDidNotFindUpdate(_ updater: SPUUpdater) {
        status = "当前已是最新版本"
    }

    func updater(_ updater: SPUUpdater, willInstallUpdateOnQuit item: SUAppcastItem,
                 immediateInstallationBlock immediateInstallHandler: @escaping () -> Void) -> Bool {
        status = "\(item.displayVersionString) 已就绪，将在退出时自动安装"
        // Do not interrupt playback or suppress Sparkle's retry / critical-update UI.
        return false
    }

    func updater(_ updater: SPUUpdater, didAbortWithError error: Error) {
        // A background failure leaves the existing app untouched. Manual checks use
        // Sparkle's error dialog; background errors remain visible in the app menu.
        status = "更新检查未完成：\(error.localizedDescription)"
    }
}
