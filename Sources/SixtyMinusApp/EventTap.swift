import ApplicationServices
import Foundation

struct KeyboardInput {
    let keyCode: Int64
    let text: String
    let flags: CGEventFlags
    let isRepeat: Bool

    var hasCommandModifier: Bool { flags.contains(.maskCommand) }
    var hasControlModifier: Bool { flags.contains(.maskControl) }
    var hasOptionModifier: Bool { flags.contains(.maskAlternate) }
}

protocol EventTapDelegate: AnyObject {
    /// Return true to suppress the event.
    func eventTap(_ tap: EventTap, received input: KeyboardInput) -> Bool
    func eventTapReceivedMouseDown(_ tap: EventTap, at quartzLocation: CGPoint)
}

final class EventTap {
    weak var delegate: EventTapDelegate?

    private var port: CFMachPort?
    private var source: CFRunLoopSource?

    func start() -> Bool {
        guard port == nil else { return true }

        let types: [CGEventType] = [.keyDown, .leftMouseDown, .rightMouseDown, .otherMouseDown]
        let mask = types.reduce(CGEventMask(0)) { partial, type in
            partial | (CGEventMask(1) << CGEventMask(type.rawValue))
        }

        let context = Unmanaged.passUnretained(self).toOpaque()
        guard let port = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: eventTapCallback,
            userInfo: context
        ) else {
            return false
        }

        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, port, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: port, enable: true)
        self.port = port
        self.source = source
        return true
    }

    func stop() {
        if let source {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
        }
        if let port {
            CGEvent.tapEnable(tap: port, enable: false)
        }
        source = nil
        port = nil
    }

    fileprivate func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let port { CGEvent.tapEnable(tap: port, enable: true) }
            return Unmanaged.passUnretained(event)
        }

        if type == .leftMouseDown || type == .rightMouseDown || type == .otherMouseDown {
            delegate?.eventTapReceivedMouseDown(self, at: event.location)
            return Unmanaged.passUnretained(event)
        }

        guard type == .keyDown else { return Unmanaged.passUnretained(event) }
        let input = KeyboardInput(
            keyCode: event.getIntegerValueField(.keyboardEventKeycode),
            text: event.unicodeText,
            flags: event.flags,
            isRepeat: event.getIntegerValueField(.keyboardEventAutorepeat) != 0
        )
        return delegate?.eventTap(self, received: input) == true
            ? nil
            : Unmanaged.passUnretained(event)
    }
}

private let eventTapCallback: CGEventTapCallBack = { _, type, event, userInfo in
    guard let userInfo else { return Unmanaged.passUnretained(event) }
    let tap = Unmanaged<EventTap>.fromOpaque(userInfo).takeUnretainedValue()
    return tap.handle(type: type, event: event)
}

private extension CGEvent {
    var unicodeText: String {
        var count = 0
        keyboardGetUnicodeString(maxStringLength: 0, actualStringLength: &count, unicodeString: nil)
        guard count > 0 else { return "" }
        var buffer = [UniChar](repeating: 0, count: count)
        buffer.withUnsafeMutableBufferPointer { pointer in
            keyboardGetUnicodeString(
                maxStringLength: count,
                actualStringLength: &count,
                unicodeString: pointer.baseAddress
            )
        }
        return String(utf16CodeUnits: buffer, count: count)
    }
}
