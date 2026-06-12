import AppKit
import ApplicationServices

final class HotkeyManager {
    var onDoubleTap: (() -> Void)?

    private var globalMonitor: Any?
    private var localMonitor: Any?
    private var lastControlPressTime: Date?
    private var isControlDown = false
    private let doubleTapInterval: TimeInterval = 0.35

    init() {
        requestAccessibilityIfNeeded()
        setupMonitors()
    }

    deinit {
        if let m = globalMonitor { NSEvent.removeMonitor(m) }
        if let m = localMonitor { NSEvent.removeMonitor(m) }
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
        let controlNowDown = event.modifierFlags.contains(.control)

        if controlNowDown && !isControlDown {
            let now = Date()
            if let last = lastControlPressTime, now.timeIntervalSince(last) < doubleTapInterval {
                lastControlPressTime = nil
                DispatchQueue.main.async { [weak self] in
                    self?.onDoubleTap?()
                }
            } else {
                lastControlPressTime = now
            }
        }

        isControlDown = controlNowDown
    }
}
