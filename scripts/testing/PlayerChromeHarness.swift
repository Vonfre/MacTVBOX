import Foundation
import AppKit

@main struct PlayerChromeHarness {
    @MainActor static func check(_ condition: Bool, _ label: String) throws {
        if !condition { throw NSError(domain: "ChromeHarness", code: 1, userInfo: [NSLocalizedDescriptionKey: label]) }
        print("PASS " + label)
    }
    static func wait() async throws { try await Task.sleep(nanoseconds: 180_000_000) }
    @MainActor static func main() async throws {
        let chrome = PlayerChromeController(delay: 0.08)
        chrome.update(playing: true, interacting: false)
        try await wait()
        try check(chrome.visible, "windowed playback keeps controls visible")
        chrome.setFullScreen(true)
        try await wait()
        try check(!chrome.visible, "fullscreen playing hides controls after idle delay")
        chrome.activity()
        try check(chrome.visible, "pointer or key activity reveals controls immediately")
        chrome.update(playing: false, interacting: false)
        try await wait()
        try check(chrome.visible, "paused playback cancels pending hide")
        chrome.update(playing: true, interacting: true)
        try await wait()
        try check(chrome.visible, "open popover or scrubbing pins controls")
        chrome.update(playing: true, interacting: false)
        try await wait()
        try check(!chrome.visible, "closing interaction restarts idle delay")
        chrome.hoverControls(true)
        try await wait()
        try check(chrome.visible, "hovering controls prevents disappearing under pointer")
        chrome.hoverControls(false)
        try await wait()
        try check(!chrome.visible, "leaving controls restarts idle delay")
        chrome.setFullScreen(false)
        try await wait()
        try check(chrome.visible, "exiting fullscreen restores controls")
        chrome.setFullScreen(true)
        chrome.detach()
        try await wait()
        try check(chrome.visible, "leaving page cancels hide task")
        var reported = false
        chrome.onFullScreenChange = { reported = $0 }
        chrome.setFullScreen(true)
        try check(reported, "host fullscreen state is forwarded to app layout")
        chrome.detach()
        var sought = 0.0
        chrome.seekBy = { sought += $0; return true }
        func key(_ code: UInt16, repeatKey: Bool = false, flags: NSEvent.ModifierFlags = []) -> NSEvent {
            NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: flags,
                            timestamp: 0, windowNumber: 0, context: nil,
                            characters: "", charactersIgnoringModifiers: "", isARepeat: repeatKey, keyCode: code)!
        }
        try check(chrome.handleSeekKey(key(124)) && sought == 5, "right arrow seeks forward five seconds")
        for _ in 0..<6 { _ = chrome.handleSeekKey(key(124, repeatKey: true, flags: [.function, .numericPad])) }
        try check(sought == 35, "held arrow repeated keyDown events accumulate without dropping hardware flags")
        try check(chrome.handleSeekKey(key(123)) && sought == 30, "left arrow seeks backward five seconds")
        for flags: NSEvent.ModifierFlags in [.command, .control, .option, .shift] {
            try check(!chrome.handleSeekKey(key(124, flags: flags)) && sought == 30, "modified arrow remains available to other shortcuts: \(flags.rawValue)")
        }
        try check(!chrome.handleSeekKey(key(124), focusOwnsArrows: true), "editing and native controls retain arrow input")
        try check(PlayerChromeController.focusOwnsArrows(NSTextView()) && PlayerChromeController.focusOwnsArrows(NSSlider()), "text editor and slider focus are protected")
        try check(!chrome.handleSeekKey(key(126)), "unrelated keys are not consumed")
        chrome.update(playing: true, interacting: true)
        try check(!chrome.handleSeekKey(key(124)), "open panels and scrubbing prevent video seek")
        chrome.update(playing: true, interacting: false)
        try await wait()
        try check(!chrome.visible, "chrome can hide before keyboard seek")
        _ = chrome.handleSeekKey(key(124))
        try check(chrome.visible, "keyboard seek reveals fullscreen transport")
        chrome.seekBy = { _ in false }
        try check(!chrome.handleSeekKey(key(124)), "unready or unseekable media does not consume keys")
        chrome.seekBy = nil
        try check(!chrome.handleSeekKey(key(124)), "no playback callback means no seek")
        chrome.detach()
        print("CHROME INTEGRATION PASSED")
    }
}
