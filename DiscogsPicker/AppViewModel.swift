import Foundation

@MainActor
final class AppViewModel: ObservableObject {
    @Published var credentials: DiscogsCredentials
    @Published private(set) var releases: [CollectionRelease] = []
    @Published private(set) var currentRelease: CollectionRelease?
    @Published private(set) var isSyncing = false
    @Published private(set) var isPreparingNextRelease = false
    @Published var errorMessage: String?
    @Published private(set) var lastSyncedAt: Date?
    @Published private(set) var isDisplayingExpiredCache = false

    private let api = DiscogsAPI()
    private let keychain = KeychainStore()
    private let cache = CollectionCache()
    private let cacheFreshnessInterval: TimeInterval = 6 * 60 * 60
    private let autoRefreshInterval: Duration = .seconds(5 * 60)
    private let recentPickLimit = 15
    private var preparedRelease: CollectionRelease?
    private var prepareNextTask: Task<Void, Never>?
    private var recentlyPickedInstanceIds: [Int] = []

    init() {
        self.credentials = keychain.loadCredentials() ?? DiscogsCredentials(username: "", token: "")

        if credentials.isComplete, let cached = cache.load() {
            self.releases = cached.releases
            self.lastSyncedAt = cached.fetchedAt
            self.isDisplayingExpiredCache = Date().timeIntervalSince(cached.fetchedAt) > cacheFreshnessInterval
            chooseRandom()
        }
    }

    var hasCredentials: Bool {
        credentials.isComplete
    }

    var needsSetup: Bool {
        !hasCredentials || releases.isEmpty
    }

    var canPickAnother: Bool {
        releases.count > 1 && preparedRelease != nil && !isPreparingNextRelease
    }

    func saveCredentials() {
        do {
            try keychain.save(credentials: trimmedCredentials())
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func runAutoRefreshLoop() async {
        await refreshCollectionIfPossible()

        while !Task.isCancelled {
            do {
                try await Task.sleep(for: autoRefreshInterval)
            } catch {
                return
            }
            await refreshCollectionIfPossible()
        }
    }

    func refreshCollectionIfPossible() async {
        guard hasCredentials else { return }
        await syncCollection(pickNewRelease: false, reportErrors: false)
    }

    func syncCollection(pickNewRelease: Bool = true, reportErrors: Bool = true) async {
        guard trimmedCredentials().isComplete else {
            if reportErrors {
                errorMessage = "Enter your Discogs username and token."
            }
            return
        }

        guard !isSyncing else {
            return
        }

        isSyncing = true
        defer { isSyncing = false }

        do {
            let cleanCredentials = trimmedCredentials()
            try keychain.save(credentials: cleanCredentials)
            let fetchedReleases = try await api.fetchCollection(credentials: cleanCredentials)
            let releaseToPreserve = currentRelease
            let preparedReleaseToPreserve = preparedRelease
            let cached = CachedCollection(
                username: cleanCredentials.username,
                fetchedAt: Date(),
                releases: fetchedReleases
            )
            try cache.save(cached)

            credentials = cleanCredentials
            releases = fetchedReleases
            pruneRecentPicks()
            lastSyncedAt = cached.fetchedAt
            isDisplayingExpiredCache = false
            errorMessage = nil

            if pickNewRelease || releaseToPreserve == nil {
                preparedRelease = nil
                prepareNextTask?.cancel()
                prepareNextTask = nil
                isPreparingNextRelease = false
                chooseRandom()
            } else {
                applyRefreshedSelection(
                    current: releaseToPreserve,
                    prepared: preparedReleaseToPreserve,
                    refreshedReleases: fetchedReleases
                )
            }
        } catch {
            if isDisplayingExpiredCache {
                clearDisplayedCollection()
            }
            if reportErrors {
                errorMessage = error.localizedDescription
            }
        }
    }

    func chooseRandom() {
        guard !releases.isEmpty else {
            currentRelease = nil
            preparedRelease = nil
            prepareNextTask?.cancel()
            prepareNextTask = nil
            isPreparingNextRelease = false
            return
        }

        if releases.count == 1 {
            currentRelease = releases[0]
            rememberPicked(releases[0])
            preparedRelease = nil
            prepareNextTask?.cancel()
            prepareNextTask = nil
            isPreparingNextRelease = false
            return
        }

        if let preparedRelease {
            currentRelease = preparedRelease
            rememberPicked(preparedRelease)
            self.preparedRelease = nil
            prepareNextRelease()
            return
        }

        currentRelease = randomRelease(excluding: currentRelease)
        rememberPicked(currentRelease)
        prepareNextRelease()
    }

    private func applyRefreshedSelection(
        current: CollectionRelease?,
        prepared: CollectionRelease?,
        refreshedReleases: [CollectionRelease]
    ) {
        let refreshedCurrent = current.flatMap { refreshedVersion(of: $0, in: refreshedReleases) }
        let refreshedPrepared = prepared.flatMap { refreshedVersion(of: $0, in: refreshedReleases) }

        if let refreshedCurrent {
            currentRelease = refreshedCurrent

            if let refreshedPrepared, refreshedPrepared != refreshedCurrent {
                preparedRelease = refreshedPrepared
                isPreparingNextRelease = false
            } else {
                preparedRelease = nil
                prepareNextTask?.cancel()
                prepareNextTask = nil
                isPreparingNextRelease = false
                prepareNextRelease()
            }
            return
        }

        if let refreshedPrepared {
            currentRelease = refreshedPrepared
            rememberPicked(refreshedPrepared)
            preparedRelease = nil
            prepareNextTask?.cancel()
            prepareNextTask = nil
            isPreparingNextRelease = false
            prepareNextRelease()
            return
        }

        preparedRelease = nil
        prepareNextTask?.cancel()
        prepareNextTask = nil
        isPreparingNextRelease = false
        chooseRandom()
    }

    private func prepareNextRelease() {
        guard releases.count > 1 else { return }

        prepareNextTask?.cancel()
        isPreparingNextRelease = true

        let release = randomRelease(excluding: currentRelease)
        prepareNextTask = Task { [weak self] in
            await Self.prefetchArtwork(for: release)
            guard !Task.isCancelled else { return }

            await MainActor.run {
                self?.preparedRelease = release
                self?.isPreparingNextRelease = false
            }
        }
    }

    private func randomRelease(excluding excludedRelease: CollectionRelease?) -> CollectionRelease? {
        let eligibleReleases = releases.filter { candidate in
            candidate.instanceId != excludedRelease?.instanceId
        }
        guard !eligibleReleases.isEmpty else { return nil }

        let recentPicks = Set(recentlyPickedInstanceIds)
        let preferredReleases = eligibleReleases.filter { candidate in
            !recentPicks.contains(candidate.instanceId)
        }

        return (preferredReleases.isEmpty ? eligibleReleases : preferredReleases).randomElement()
    }

    private func rememberPicked(_ release: CollectionRelease?) {
        guard let release else { return }

        recentlyPickedInstanceIds.removeAll { instanceId in
            instanceId == release.instanceId
        }
        recentlyPickedInstanceIds.append(release.instanceId)

        let limit = min(recentPickLimit, max(releases.count - 1, 0))
        if recentlyPickedInstanceIds.count > limit {
            recentlyPickedInstanceIds.removeFirst(recentlyPickedInstanceIds.count - limit)
        }
    }

    private func pruneRecentPicks() {
        let releaseIds = Set(releases.map(\.instanceId))
        recentlyPickedInstanceIds.removeAll { instanceId in
            !releaseIds.contains(instanceId)
        }

        let limit = min(recentPickLimit, max(releases.count - 1, 0))
        if recentlyPickedInstanceIds.count > limit {
            recentlyPickedInstanceIds.removeFirst(recentlyPickedInstanceIds.count - limit)
        }
    }

    private func refreshedVersion(
        of release: CollectionRelease,
        in refreshedReleases: [CollectionRelease]
    ) -> CollectionRelease? {
        refreshedReleases.first { candidate in
            candidate.instanceId == release.instanceId
        }
    }

    nonisolated private static func prefetchArtwork(for release: CollectionRelease?) async {
        guard let release else { return }

        await withTaskGroup(of: Void.self) { group in
            for url in release.basicInformation.artworkURLsForPrefetch {
                group.addTask {
                    _ = try? await URLSession.shared.data(from: url)
                }
            }
        }
    }

    func signOut() {
        do {
            try keychain.clearCredentials()
            try cache.clear()
            credentials = DiscogsCredentials(username: "", token: "")
            clearDisplayedCollection()
            lastSyncedAt = nil
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func clearDisplayedCollection() {
        releases = []
        currentRelease = nil
        preparedRelease = nil
        prepareNextTask?.cancel()
        prepareNextTask = nil
        isPreparingNextRelease = false
        isDisplayingExpiredCache = false
        recentlyPickedInstanceIds = []
    }

    private func trimmedCredentials() -> DiscogsCredentials {
        DiscogsCredentials(
            username: credentials.username.trimmingCharacters(in: .whitespacesAndNewlines),
            token: credentials.token.trimmingCharacters(in: .whitespacesAndNewlines)
        )
    }
}
