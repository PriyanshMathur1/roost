import Foundation
import TesseraCore

/// User preferences, stored in UserDefaults.
struct Settings {
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        defaults.register(defaults: ["enabled": true, "gap": 8.0, "maxTiles": 6, "minTileWidth": 300.0])
    }

    static let gapChoices: [Double] = [0, 4, 8, 12, 16, 24]
    static let minTileChoices: [Double] = [0, 200, 300, 400]

    /// The narrowest tile worth having (0 = no limit). The height floor scales with it.
    var minTileWidth: Double {
        get { defaults.double(forKey: "minTileWidth") }
        nonmutating set { defaults.set(max(newValue, 0), forKey: "minTileWidth") }
    }

    var minTile: Size { Size(w: minTileWidth, h: (minTileWidth * 0.55).rounded()) }

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
