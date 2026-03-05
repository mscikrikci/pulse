import Foundation

/// Stores the Anthropic API key in UserDefaults with a fallback to Config.plist.
/// UserDefaults takes precedence — Config.plist is the legacy default.
struct APIKeyStore {

    private static let defaultsKey = "anthropicAPIKey"

    // MARK: - Read

    static func load() -> String? {
        // 1. UserDefaults (user-configured via Settings)
        if let stored = UserDefaults.standard.string(forKey: defaultsKey),
           !stored.isEmpty {
            return stored
        }
        // 2. Config.plist fallback (dev default / initial setup)
        return loadFromPlist()
    }

    static var isConfigured: Bool {
        load() != nil
    }

    // MARK: - Write

    static func save(_ key: String) {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        UserDefaults.standard.set(trimmed.isEmpty ? nil : trimmed, forKey: defaultsKey)
    }

    static func clear() {
        UserDefaults.standard.removeObject(forKey: defaultsKey)
    }

    // MARK: - Private

    private static func loadFromPlist() -> String? {
        guard let path = Bundle.main.path(forResource: "Config", ofType: "plist"),
              let config = NSDictionary(contentsOfFile: path),
              let key = config["AnthropicAPIKey"] as? String,
              !key.isEmpty,
              key != "sk-ant-YOUR_KEY_HERE" else { return nil }
        return key
    }
}
