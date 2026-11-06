import Carbon
import os

/// Global keyboard shortcuts through Carbon's `RegisterEventHotKey`, which needs no
/// extra permission and works while other apps are frontmost.
@MainActor
final class HotKeys {
    struct Shortcut {
        let keyCode: Int
        let modifiers: Int
        let label: String
        let action: () -> Void
    }

    /// Shortcuts macOS refused, usually because another app already registered them.
    private(set) var failed: [String] = []
    private(set) var registered: [String] = []

    private let log = Logger(subsystem: "com.priyansh.roost", category: "hotkeys")
    private var actions: [UInt32: () -> Void] = [:]
    private var refs: [EventHotKeyRef] = []
    private var handler: EventHandlerRef?
    private var nextID: UInt32 = 1
    private static let signature: OSType = 0x524F_5354 // "ROST"

    init() {
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, event, userData in
            guard let event, let userData else { return OSStatus(eventNotHandledErr) }
            var id = EventHotKeyID()
            let status = GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                                           nil, MemoryLayout<EventHotKeyID>.size, nil, &id)
            guard status == noErr else { return status }
            let hotKeys = Unmanaged<HotKeys>.fromOpaque(userData).takeUnretainedValue()
            MainActor.assumeIsolated { hotKeys.actions[id.id]?() }
            return noErr
        }, 1, &spec, Unmanaged.passUnretained(self).toOpaque(), &handler)
    }

    func register(_ shortcuts: [Shortcut]) {
        for s in shortcuts {
            let id = nextID
            nextID += 1
            var ref: EventHotKeyRef?
            let status = RegisterEventHotKey(UInt32(s.keyCode), UInt32(s.modifiers),
                                             EventHotKeyID(signature: Self.signature, id: id),
                                             GetApplicationEventTarget(), 0, &ref)
            if status == noErr, let ref {
                refs.append(ref)
                actions[id] = s.action
                registered.append(s.label)
            } else {
                failed.append(s.label)
                log.error("Couldn't register \(s.label, privacy: .public): \(status)")
            }
        }
    }

    // Virtual key codes (Carbon `kVK_*`).
    enum Key {
        static let left = kVK_LeftArrow, right = kVK_RightArrow, up = kVK_UpArrow, down = kVK_DownArrow
        static let returnKey = kVK_Return, minus = kVK_ANSI_Minus, equal = kVK_ANSI_Equal
        static let f = kVK_ANSI_F, t = kVK_ANSI_T, tab = kVK_Tab
        static let digits = [kVK_ANSI_1, kVK_ANSI_2, kVK_ANSI_3, kVK_ANSI_4]
    }

    static let ctrlOpt = controlKey | optionKey
    static let ctrlOptShift = controlKey | optionKey | shiftKey
}
