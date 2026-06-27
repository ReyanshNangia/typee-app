import AppKit
import ApplicationServices
import CoreGraphics

enum HotkeyKey: String, CaseIterable {
    case control = "control"
    case option  = "option"
    case command = "command"

    var label: String {
        switch self {
        case .control: return "Control"
        case .option:  return "Option"
        case .command: return "Command"
        }
    }

    fileprivate var keyCodes: Set<UInt16> {
        switch self {
        case .control: return [59, 62]
        case .option:  return [58, 61]
        case .command: return [55, 54]
        }
    }

    fileprivate var flag: NSEvent.ModifierFlags {
        switch self {
        case .control: return .control
        case .option:  return .option
        case .command: return .command
        }
    }

    fileprivate var cgFlag: CGEventFlags {
        switch self {
        case .control: return .maskControl
        case .option:  return .maskAlternate
        case .command: return .maskCommand
        }
    }
}

final class HotkeyManager {
    var onDoubleTap: (() -> Void)?
    var onTrustGained: (() -> Void)?

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var localMonitor: Any?

    private var lastPressTime: Date?
    private var isKeyDown = false

    private let doubleTapInterval: TimeInterval = 0.35
    private let minTapInterval:    TimeInterval = 0.05

    private(set) var currentKey: HotkeyKey
    private var trustTimer: Timer?

    init() {
        let raw = UserDefaults.standard.string(forKey: "typee.hotkeyKey") ?? "control"
        currentKey = HotkeyKey(rawValue: raw) ?? .control
        setupMonitors()
        setupSleepWakeObservers()
        if !AXIsProcessTrusted() {
            startTrustPolling()
        }
    }

    deinit {
        trustTimer?.invalidate()
        NSWorkspace.shared.notificationCenter.removeObserver(self)
        removeMonitors()
    }

    var isTrusted: Bool { AXIsProcessTrusted() }

    func promptForAccessibility() {
        let opts = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        AXIsProcessTrustedWithOptions(opts)
        startTrustPolling()
    }

    func updateKey(_ key: HotkeyKey) {
        currentKey = key
        UserDefaults.standard.set(key.rawValue, forKey: "typee.hotkeyKey")
        removeMonitors()
        isKeyDown     = false
        lastPressTime = nil
        setupMonitors()
    }

    // MARK: - Sleep/wake

    private func setupSleepWakeObservers() {
        let wc = NSWorkspace.shared.notificationCenter
        wc.addObserver(self,
                       selector: #selector(systemWillSleep),
                       name: NSWorkspace.willSleepNotification,
                       object: nil)
        wc.addObserver(self,
                       selector: #selector(systemDidWake),
                       name: NSWorkspace.didWakeNotification,
                       object: nil)
    }

    @objc private func systemWillSleep() {
        removeEventTap()
    }

    @objc private func systemDidWake() {
        // macOS needs a moment after wake before event taps work reliably
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
            self?.reinstallEventTap()
        }
    }

    private func reinstallEventTap() {
        removeEventTap()
        isKeyDown     = false
        lastPressTime = nil
        if AXIsProcessTrusted() {
            installEventTap()
        }
    }

    // MARK: - Monitor management

    private func setupMonitors() {
        installLocalMonitor()
        if AXIsProcessTrusted() {
            installEventTap()
        }
    }

    private func removeMonitors() {
        removeEventTap()
        removeLocalMonitor()
    }

    // MARK: - Local monitor (no accessibility needed, for when app is focused)

    private func installLocalMonitor() {
        guard localMonitor == nil else { return }
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { [weak self] e in
            self?.handleNSEvent(e)
            return e
        }
    }

    private func removeLocalMonitor() {
        if let m = localMonitor { NSEvent.removeMonitor(m); localMonitor = nil }
    }

    // MARK: - CGEventTap (reliable globally, survives sleep/wake)

    private func installEventTap() {
        guard eventTap == nil else { return }

        // passUnretained is safe: HotkeyManager is owned by AppDelegate for the
        // entire process lifetime, so the pointer is always valid while the tap runs.
        let selfPtr = Unmanaged.passUnretained(self).toOpaque()

        let mask = CGEventMask(1 << CGEventType.flagsChanged.rawValue)
        let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .listenOnly,
            eventsOfInterest: mask,
            callback: { _, type, event, userInfo -> Unmanaged<CGEvent>? in
                guard let userInfo else { return nil }
                let mgr = Unmanaged<HotkeyManager>.fromOpaque(userInfo).takeUnretainedValue()
                // macOS disables the tap on timeout or after certain system events.
                // Re-enable it in-place so the hotkey keeps working without reinstall.
                if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
                    if let tap = mgr.eventTap { CGEvent.tapEnable(tap: tap, enable: true) }
                    return nil
                }
                mgr.handleCGEvent(event)
                // listenOnly tap: return value is ignored by the event system.
                return nil
            },
            userInfo: selfPtr
        )

        guard let tap else { return }

        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)

        eventTap      = tap
        runLoopSource = source
    }

    private func removeEventTap() {
        guard let tap = eventTap else { return }
        CGEvent.tapEnable(tap: tap, enable: false)
        if let src = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), src, .commonModes)
            runLoopSource = nil
        }
        eventTap = nil
    }

    // MARK: - Event handling

    private func handleCGEvent(_ cgEvent: CGEvent) {
        let keyCode = UInt16(cgEvent.getIntegerValueField(.keyboardEventKeycode))
        guard currentKey.keyCodes.contains(keyCode) else { return }
        let nowDown = cgEvent.flags.contains(currentKey.cgFlag)
        processKeyState(nowDown: nowDown)
    }

    private func handleNSEvent(_ event: NSEvent) {
        guard currentKey.keyCodes.contains(event.keyCode) else { return }
        let nowDown = event.modifierFlags.contains(currentKey.flag)
        processKeyState(nowDown: nowDown)
    }

    private func processKeyState(nowDown: Bool) {
        if nowDown && !isKeyDown {
            let now = Date()
            if let last = lastPressTime {
                let dt = now.timeIntervalSince(last)
                if dt > minTapInterval && dt < doubleTapInterval {
                    lastPressTime = nil
                    DispatchQueue.main.async { [weak self] in self?.onDoubleTap?() }
                } else {
                    lastPressTime = now
                }
            } else {
                lastPressTime = now
            }
        }
        isKeyDown = nowDown
    }

    // MARK: - Trust polling

    private func startTrustPolling() {
        trustTimer?.invalidate()
        let t = Timer(timeInterval: 2.0, repeats: true) { [weak self] timer in
            guard let self else { timer.invalidate(); return }
            if AXIsProcessTrusted() {
                timer.invalidate()
                self.trustTimer = nil
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.75) { [weak self] in
                    self?.reinstallEventTap()
                    self?.onTrustGained?()
                }
            }
        }
        RunLoop.main.add(t, forMode: .common)
        trustTimer = t
    }
}
