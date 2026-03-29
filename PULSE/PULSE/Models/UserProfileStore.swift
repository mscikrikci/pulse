import Foundation

struct UserProfileStore {

    static func save(_ profile: UserProfile) {
        guard let url = storeURL(),
              let data = try? JSONEncoder().encode(profile) else { return }
        try? data.write(to: url, options: .atomic)
    }

    static func load() -> UserProfile {
        guard let url = storeURL(),
              FileManager.default.fileExists(atPath: url.path),
              let data = try? Data(contentsOf: url),
              let profile = try? JSONDecoder().decode(UserProfile.self, from: data) else {
            return .empty
        }
        return profile
    }

    private static func storeURL() -> URL? {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first?
            .appendingPathComponent("user_profile.json")
    }
}
