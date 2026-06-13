import AppKit
import ApplicationServices

final class HotkeyManager {
    var onDoubleTap: (() -> Void)?

    private var globalMonitor: Any?
    private var localMonitor: Any?
    private var lastControlPressTime: Date?
    private var isControlDown = false
    private let doubleTapInterval: TimeInterval = 0.35
    private let minTapInterval:    TimeInterval = 0.05  // filter keyboard bounce

    init() {
        requestAccessibilityIfNeeded()
        setupMonitors()
    }

    deinit {
        if let m = globalMonitor { NSEvent.removeMonitor(m) }
        if let m = localMonitor  { NSEvent.removeMonitor(m) }
    }

    private func requestAccessibilityIfNeeded() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        AXIsProcessTrustedWithOptions(options)
    }

    private func setupMonitors() {
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            self?.handleFlagsChanged(event)
        }
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            self?.handleFlagsChanged(event)
            return event
        }
    }

    private func handleFlagsChanged(_ event: NSEvent) {
        // Only react to actual Control key events.
        // keyCode 59 = Left Control, 62 = Right Control.
        // Without this check every modifier change (Shift, Option, Fn…) that
        // happens to leave .control set is misread as a Ctrl press.
        guard event.keyCode == 59 || event.keyCode == 62 else { return }

        let controlNowDown = event.modifierFlags.contains(.control)

        if controlNowDown && !isControlDown {
            let now = Date()
            if let last = lastControlPressTime {
                let elapsed = now.timeIntervalSince(last)
                // elapsed > minTapInterval: skip keyboard bounce
                // elapsed < doubleTapInterval: within the double-tap window
                if elapsed > minTapInterval && elapsed < doubleTapInterval {
                    lastControlPressTime = nil
                    DispatchQueue.main.async { [weak self] in
                        self?.onDoubleTap?()
                    }
                } else {
                    // Too fast (bounce) or too slow — start a fresh first-tap
                    lastControlPressTime = now
                }
            } else {
                lastControlPressTime = now
            }
        }

        isControlDown = controlNowDown
    }
}
