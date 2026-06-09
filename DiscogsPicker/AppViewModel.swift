import Foundation

@MainActor
final class AppViewModel: ObservableObject {
    @Published var credentials: DiscogsCredentials
    @Published private(set) var releases: [CollectionRelease] = []
    @Published private(set) var currentRelease: CollectionRelease?
    @Published private(set) var isSyncing = false
    @Published var errorMessage: String?
    @Published private(set) var lastSyncedAt: Date?

    private let api = DiscogsAPI()
    private let keychain = KeychainStore()
    private let cache = CollectionCache()
    private let cacheFreshnessInterval: TimeInterval = 6 * 60 * 60

    init() {
        self.credentials = keychain.loadCredentials() ?? DiscogsCredentials(username: "", token: "")

        if let cached = cache.load(), Date().timeIntervalSince(cached.fetchedAt) < cacheFreshnessInterval {
            self.releases = cached.releases
            self.lastSyncedAt = cached.fetchedAt
            chooseRandom()
        }
    }

    var hasCredentials: Bool {
        credentials.isComplete
    }

    var needsSetup: Bool {
        !hasCredentials || releases.isEmpty
    }

    func saveCredentials() {
        do {
            try keychain.save(credentials: trimmedCredentials())
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func syncCollection() async {
        guard trimmedCredentials().isComplete else {
            errorMessage = "Enter your Discogs username and token."
            return
        }

        isSyncing = true
        defer { isSyncing = false }

        do {
            let cleanCredentials = trimmedCredentials()
            try keychain.save(credentials: cleanCredentials)
            let fetchedReleases = try await api.fetchCollection(credentials: cleanCredentials)
            let cached = CachedCollection(
                username: cleanCredentials.username,
                fetchedAt: Date(),
                releases: fetchedReleases
            )
            try cache.save(cached)

            credentials = cleanCredentials
            releases = fetchedReleases
            lastSyncedAt = cached.fetchedAt
            errorMessage = nil
            chooseRandom()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func chooseRandom() {
        guard !releases.isEmpty else {
            currentRelease = nil
            return
        }

        if releases.count == 1 {
            currentRelease = releases[0]
            return
        }

        var next = releases.randomElement()
        while next == currentRelease {
            next = releases.randomElement()
        }
        currentRelease = next
    }

    func signOut() {
        do {
            try keychain.clearCredentials()
            try cache.clear()
            credentials = DiscogsCredentials(username: "", token: "")
            releases = []
            currentRelease = nil
            lastSyncedAt = nil
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func trimmedCredentials() -> DiscogsCredentials {
        DiscogsCredentials(
            username: credentials.username.trimmingCharacters(in: .whitespacesAndNewlines),
            token: credentials.token.trimmingCharacters(in: .whitespacesAndNewlines)
        )
    }
}
