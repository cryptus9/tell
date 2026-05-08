import ApplicationServices
import CoreGraphics
import Foundation

final class HotkeyManager {
    // nonisolated(unsafe) so the C callback thread can read these without MainActor.
    nonisolated(unsafe) var onKeyDown: (() -> Void)?
    nonisolated(unsafe) var onKeyUp: (() -> Void)?

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var retained: Unmanaged<HotkeyManager>?
    nonisolated(unsafe) private(set) var targetKeyCode: Int = 0
    nonisolated(unsafe) private(set) var targetModifiers: Int = 0

    func start(keyCode: Int, modifiers: Int) {
        stop()
        targetKeyCode = keyCode
        targetModifiers = modifiers

        let mask: CGEventMask =
            (1 << CGEventType.keyDown.rawValue) |
            (1 << CGEventType.keyUp.rawValue) |
            (1 << CGEventType.flagsChanged.rawValue)

        let ref = Unmanaged.passRetained(self)
        retained = ref
        eventTap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: hotkeyEventCallback,
            userInfo: ref.toOpaque()
        )

        guard let tap = eventTap else {
            ref.release()
            retained = nil
            print("[HotkeyManager] tapCreate failed — Accessibility permission granted?", AXIsProcessTrusted())
            return
        }

        runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        print("[HotkeyManager] tap active, keyCode=\(keyCode) modifiers=\(modifiers)")
    }

    func stop() {
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
            if let src = runLoopSource {
                CFRunLoopRemoveSource(CFRunLoopGetMain(), src, .commonModes)
            }
            retained?.release()
            retained = nil
        }
        eventTap = nil
        runLoopSource = nil
    }

    // Called from C callback — must be nonisolated.
    nonisolated fileprivate func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        let keyCode = Int(event.getIntegerValueField(.keyboardEventKeycode))
        let modifierMask: CGEventFlags = [.maskAlternate, .maskCommand, .maskControl, .maskShift]
        let active = Int(event.flags.intersection(modifierMask).rawValue)

        if type == .flagsChanged {
            // Modifier-only hotkey: targetModifiers == 0, targetKeyCode is a modifier key.
            guard keyCode == targetKeyCode, targetModifiers == 0 else {
                return Unmanaged.passRetained(event)
            }
            // Flags grew → press; flags cleared → release.
            if active != 0 {
                DispatchQueue.main.async { self.onKeyDown?() }
            } else {
                DispatchQueue.main.async { self.onKeyUp?() }
            }
            return nil
        }

        guard keyCode == targetKeyCode, active == targetModifiers else {
            return Unmanaged.passRetained(event)
        }

        switch type {
        case .keyDown: DispatchQueue.main.async { self.onKeyDown?() }
        case .keyUp:   DispatchQueue.main.async { self.onKeyUp?() }
        default: break
        }
        return nil
    }
}

private func hotkeyEventCallback(
    proxy: CGEventTapProxy,
    type: CGEventType,
    event: CGEvent,
    refcon: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    guard let refcon else { return Unmanaged.passRetained(event) }
    let manager = Unmanaged<HotkeyManager>.fromOpaque(refcon).takeUnretainedValue()
    return manager.handle(type: type, event: event)
}
