/// The set of displays connected at one time, e.g. "laptop only" or "laptop + desk monitor".
/// The same displays in any order are the same setup.
public struct DisplaySetup: Hashable, Codable, Sendable {
    public let displays: [String]

    public init<S: Sequence>(_ keys: S) where S.Element == String {
        displays = Array(Set(keys)).sorted()
    }

    /// A stable string for storage.
    public var id: String { displays.joined(separator: "+") }
}

/// A window as it can be recognised after a restart: by its app and its title.
public struct WindowTag: Hashable, Codable, Sendable {
    public var app: String
    public var title: String

    public init(app: String, title: String) {
        self.app = app
        self.title = title
    }
}

/// Puts windows back where they were the last time a display setup was connected.
public enum Arrangement {
    /// The windows for each display after `setup` comes back.
    ///
    /// - `saved`: windows per display, in tile order, from the last time this setup was connected.
    /// - `current`: windows per display right now. Its keys are the displays connected now.
    /// - `present`: every window that can be tiled right now.
    ///
    /// Saved windows that are present go back to their saved display, in saved order (only
    /// to displays that are connected). Every other window keeps its current display, after
    /// the restored ones. Each window appears once. Present windows in neither list are left
    /// out; they join as new windows.
    public static func restore<ID: Hashable>(saved: [String: [ID]], current: [String: [ID]], present: Set<ID>) -> [String: [ID]] {
        var result: [String: [ID]] = [:]
        var placed: Set<ID> = []
        let displays = current.keys.sorted()
        for display in displays {
            result[display] = []
            for id in saved[display] ?? [] where present.contains(id) && !placed.contains(id) {
                result[display]!.append(id)
                placed.insert(id)
            }
        }
        for display in displays {
            for id in current[display] ?? [] where present.contains(id) && !placed.contains(id) {
                result[display]!.append(id)
                placed.insert(id)
            }
        }
        return result
    }

    /// Turns an arrangement saved by tag (after a restart, windows are new objects) back into
    /// window IDs. A tag first matches a window with the same app and title; slots left over
    /// then take the remaining windows of the same app, in order (titles change: a browser
    /// shows a different tab). Each window is used once; unmatched slots are dropped.
    public static func resolve<ID: Hashable>(_ saved: [String: [WindowTag]], present: [(id: ID, tag: WindowTag)]) -> [String: [ID]] {
        let displays = saved.keys.sorted()
        var slots: [String: [ID?]] = [:]
        var used: Set<ID> = []

        for display in displays {
            slots[display] = saved[display]!.map { tag in
                guard let match = present.first(where: { $0.tag == tag && !used.contains($0.id) }) else { return nil }
                used.insert(match.id)
                return match.id
            }
        }
        for display in displays {
            for (i, tag) in saved[display]!.enumerated() where slots[display]![i] == nil {
                if let match = present.first(where: { $0.tag.app == tag.app && !used.contains($0.id) }) {
                    used.insert(match.id)
                    slots[display]![i] = match.id
                }
            }
        }
        return slots.mapValues { $0.compactMap { $0 } }
    }
}
