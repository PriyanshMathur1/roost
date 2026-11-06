import Foundation
import TesseraCore

/// User preferences, stored in UserDefaults.
struct Settings {
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        defaults.register(defaults: ["enabled": true, "gap": 8.0, "maxTiles": 6])
    }

    static let gapChoices: [Double] = [0, 4, 8, 12, 16, 24]

    var enabled: Bool {
        get { defaults.bool(forKey: "enabled") }
        nonmutating set { defaults.set(newValue, forKey: "enabled") }
    }

    var gap: Double {
        get { defaults.double(forKey: "gap") }
        nonmutating set { defaults.set(max(newValue, 0), forKey: "gap") }
    }

    var maxTiles: Int {
        get { max(defaults.integer(forKey: "maxTiles"), 1) }
        nonmutating set { defaults.set(max(newValue, 1), forKey: "maxTiles") }
    }

    /// Layout per display, keyed by display UUID. Displays without a choice use `.main`.
    func layout(for displayKey: String) -> LayoutKind {
        let stored = defaults.dictionary(forKey: "layouts") as? [String: String]
        return stored?[displayKey].flatMap(LayoutKind.init(rawValue:)) ?? .main
    }

    func setLayout(_ kind: LayoutKind, for displayKey: String) {
        var stored = (defaults.dictionary(forKey: "layouts") as? [String: String]) ?? [:]
        stored[displayKey] = kind.rawValue
        defaults.set(stored, forKey: "layouts")
    }
}
