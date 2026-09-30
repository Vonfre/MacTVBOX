import AppKit
import SwiftUI

/// Owns only player chrome, never playback. Monitoring is scoped to the host window.
@MainActor final class PlayerChromeController: ObservableObject {
    @Published private(set) var visible = true
    @Published private(set) var isFullScreen = false
    weak var window: NSWindow?
    /// Returns false when media is not seekable; repeated keyDown events accumulate.
    var seekBy: ((Double) -> Bool)?
    var dismissPanel: (() -> Bool)?
    var onFullScreenChange: ((Bool) -> Void)?
    private var hideTask: Task<Void, Never>?
    private var observers: [NSObjectProtocol] = []
    private var monitor: Any?
    private var originalMouseMoved = false
    private var playing = false
    private var interacting = false
    private var hoveringControls = false
    private let delay: Double
    init(delay: Double = 3) { self.delay = delay }

    func attach(_ window: NSWindow?) {
        guard self.window !== window else { return }
        detach()
        guard let window else { return }
        self.window = window
        originalMouseMoved = window.acceptsMouseMovedEvents
        window.acceptsMouseMovedEvents = true
        setFullScreen(window.styleMask.contains(.fullScreen))
        for name in [NSWindow.didEnterFullScreenNotification, NSWindow.didExitFullScreenNotification] {
            observers.append(NotificationCenter.default.addObserver(forName: name, object: window, queue: .main) { [weak self, weak window] _ in
                Task { @MainActor [weak self, weak window] in
                    guard let self, let window else { return }
                    self.setFullScreen(window.styleMask.contains(.fullScreen))
                }
            })
        }
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.mouseMoved, .leftMouseDown, .leftMouseDragged, .rightMouseDown, .scrollWheel, .keyDown]) { [weak self] event in
            guard let self, let window = self.window, event.window === window else { return event }
            self.activity()
            // Native Escape exits the same fullscreen window, not a separate player.
            if event.type == .keyDown, event.keyCode == 53 {
                if self.dismissPanel?() == true { return nil }
                if self.isFullScreen { self.toggleFullScreen(); return nil }
            }
            if event.type == .keyDown, window.isKeyWindow,
               window.attachedSheet == nil, NSApp.modalWindow == nil,
               self.handleSeekKey(event, focusOwnsArrows: Self.focusOwnsArrows(window.firstResponder)) {
                return nil
            }
            return event
        }
    }
    static func focusOwnsArrows(_ responder: NSResponder?) -> Bool {
        // Preserve caret movement and native slider/list keyboard navigation.
        responder is NSText || responder is NSControl || responder is NSScrollView
    }
    @discardableResult
    func handleSeekKey(_ event: NSEvent, focusOwnsArrows: Bool = false) -> Bool {
        guard event.type == .keyDown, !interacting, !focusOwnsArrows,
              event.modifierFlags.intersection([.command, .control, .option, .shift]).isEmpty,
              event.keyCode == 123 || event.keyCode == 124 else { return false }
        // Do not filter isARepeat: holding an arrow follows macOS keyboard repeat.
        // Function/numericPad flags are normal for hardware arrow keys.
        guard seekBy?(event.keyCode == 123 ? -5 : 5) == true else { return false }
        activity()
        return true
    }
    func setFullScreen(_ value: Bool) {
        isFullScreen = value
        hoveringControls = false
        onFullScreenChange?(value)
        activity()
    }
    func toggleFullScreen() { activity(); window?.toggleFullScreen(nil) }
    func update(playing: Bool, interacting: Bool) {
        guard self.playing != playing || self.interacting != interacting else { return }
        self.playing = playing; self.interacting = interacting
        activity()
    }
    func hoverControls(_ value: Bool) { hoveringControls = value; activity() }
    func activity() {
        hideTask?.cancel()
        visible = true
        guard isFullScreen, playing, !interacting, !hoveringControls else { return }
        hideTask = Task { [weak self, delay] in
            do { try await Task.sleep(nanoseconds: UInt64(max(0, delay) * 1_000_000_000)) }
            catch { return }
            guard let self, !Task.isCancelled, self.isFullScreen, self.playing, !self.interacting, !self.hoveringControls else { return }
            self.visible = false
        }
    }
    func detach() {
        hideTask?.cancel(); hideTask = nil
        if let monitor { NSEvent.removeMonitor(monitor) }; monitor = nil
        observers.forEach { NotificationCenter.default.removeObserver($0) }; observers.removeAll()
        window?.acceptsMouseMovedEvents = originalMouseMoved
        window = nil
        visible = true
    }
}

struct PlayerWindowReader: NSViewRepresentable {
    let chrome: PlayerChromeController
    final class Reader: NSView {
        var onWindow: ((NSWindow?) -> Void)?
        override func viewDidMoveToWindow() { super.viewDidMoveToWindow(); onWindow?(window) }
        override func hitTest(_ point: NSPoint) -> NSView? { nil }
    }
    func makeNSView(context: Context) -> Reader {
        let view = Reader()
        view.onWindow = { [weak chrome] window in
            // Avoid publishing changes during SwiftUI's representable update.
            Task { @MainActor [weak chrome] in chrome?.attach(window) }
        }
        return view
    }
    func updateNSView(_ nsView: Reader, context: Context) { }
    static func dismantleNSView(_ nsView: Reader, coordinator: ()) { nsView.onWindow = nil }
}
