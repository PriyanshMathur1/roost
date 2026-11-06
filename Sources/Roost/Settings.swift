import Foundation
import RoostCore

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

    var hasSeenWelcome: Bool {
        get { defaults.bool(forKey: "hasSeenWelcome") }
        nonmutating set { defaults.set(newValue, forKey: "hasSeenWelcome") }
    }

    /// The smallest size each app's windows accepted, by bundle ID, so tiling is right from
    /// the first second after a restart.
    var appMinSizes: [String: Size] {
        get { decode([String: Size].self, forKey: "appMinSizes") ?? [:] }
        nonmutating set { encode(newValue, forKey: "appMinSizes") }
    }

    /// Where windows were for each display setup (by `DisplaySetup.id`): display → windows.
    var arrangements: [String: [String: [WindowTag]]] {
        get { decode([String: [String: [WindowTag]]].self, forKey: "arrangements") ?? [:] }
        nonmutating set { encode(newValue, forKey: "arrangements") }
    }

    private func decode<T: Decodable>(_ type: T.Type, forKey key: String) -> T? {
        guard let data = defaults.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }

    private func encode<T: Encodable>(_ value: T, forKey key: String) {
        if let data = try? JSONEncoder().encode(value) { defaults.set(data, forKey: key) }
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
