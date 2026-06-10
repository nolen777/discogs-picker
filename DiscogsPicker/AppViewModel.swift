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
    private var backStack: [CollectionRelease] = []
    private var forwardStack: [CollectionRelease] = []

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

    var canGoBack: Bool {
        !backStack.isEmpty
    }

    var nextReleaseForNavigation: CollectionRelease? {
        forwardStack.last ?? preparedRelease
    }

    var previousReleaseForNavigation: CollectionRelease? {
        backStack.last
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
            refreshNavigationHistory(in: fetchedReleases)
            lastSyncedAt = cached.fetchedAt
            isDisplayingExpiredCache = false
            errorMessage = nil

            if pickNewRelease || releaseToPreserve == nil {
                preparedRelease = nil
                clearForwardHistory()
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
        clearForwardHistory()
        chooseNextRelease()
    }

    @discardableResult
    func navigateForward() -> Bool {
        if let release = forwardStack.popLast() {
            display(release, preservingCurrentInBackStack: true)
            reconcilePreparedRelease()
            return true
        }

        return chooseNextRelease()
    }

    @discardableResult
    func navigateBack() -> Bool {
        guard let currentRelease, let previousRelease = backStack.popLast() else {
            return false
        }

        forwardStack.append(currentRelease)
        trimNavigationStacks()
        self.currentRelease = previousRelease
        rememberPicked(previousRelease)
        reconcilePreparedRelease()
        return true
    }

    @discardableResult
    private func chooseNextRelease() -> Bool {
        guard !releases.isEmpty else {
            currentRelease = nil
            preparedRelease = nil
            prepareNextTask?.cancel()
            prepareNextTask = nil
            isPreparingNextRelease = false
            backStack = []
            forwardStack = []
            return false
        }

        if releases.count == 1 {
            backStack = []
            forwardStack = []
            display(releases[0], preservingCurrentInBackStack: false)
            preparedRelease = nil
            prepareNextTask?.cancel()
            prepareNextTask = nil
            isPreparingNextRelease = false
            return true
        }

        if let preparedRelease {
            display(preparedRelease, preservingCurrentInBackStack: true)
            self.preparedRelease = nil
            prepareNextRelease()
            return true
        }

        guard let release = randomRelease(excluding: currentRelease) else {
            return false
        }

        display(release, preservingCurrentInBackStack: true)
        prepareNextRelease()
        return true
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

    private func display(_ release: CollectionRelease, preservingCurrentInBackStack shouldPreserveCurrent: Bool) {
        if shouldPreserveCurrent, let currentRelease, currentRelease != release {
            backStack.append(currentRelease)
            trimNavigationStacks()
        }

        currentRelease = release
        rememberPicked(release)
    }

    private func reconcilePreparedRelease() {
        guard releases.count > 1 else { return }

        if preparedRelease?.instanceId == currentRelease?.instanceId {
            preparedRelease = nil
            prepareNextTask?.cancel()
            prepareNextTask = nil
            isPreparingNextRelease = false
        }

        if preparedRelease == nil && !isPreparingNextRelease {
            prepareNextRelease()
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

    private func refreshNavigationHistory(in refreshedReleases: [CollectionRelease]) {
        backStack = backStack.compactMap { release in
            refreshedVersion(of: release, in: refreshedReleases)
        }
        forwardStack = forwardStack.compactMap { release in
            refreshedVersion(of: release, in: refreshedReleases)
        }
        trimNavigationStacks()
    }

    private func clearForwardHistory() {
        forwardStack = []
    }

    private func trimNavigationStacks() {
        let limit = min(recentPickLimit, max(releases.count - 1, 0))

        if backStack.count > limit {
            backStack.removeFirst(backStack.count - limit)
        }
        if forwardStack.count > limit {
            forwardStack.removeFirst(forwardStack.count - limit)
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
        backStack = []
        forwardStack = []
    }

    private func trimmedCredentials() -> DiscogsCredentials {
        DiscogsCredentials(
            username: credentials.username.trimmingCharacters(in: .whitespacesAndNewlines),
            token: credentials.token.trimmingCharacters(in: .whitespacesAndNewlines)
        )
    }
}
