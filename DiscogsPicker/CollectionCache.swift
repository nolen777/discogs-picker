import Foundation

struct CollectionCache {
    private var cacheURL: URL {
        let directory = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        return directory.appendingPathComponent("discogs-collection-cache.json")
    }

    func load() -> CachedCollection? {
        guard let data = try? Data(contentsOf: cacheURL) else {
            return nil
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(CachedCollection.self, from: data)
    }

    func save(_ cache: CachedCollection) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(cache)
        try data.write(to: cacheURL, options: [.atomic])
    }

    func clear() throws {
        guard FileManager.default.fileExists(atPath: cacheURL.path) else {
            return
        }
        try FileManager.default.removeItem(at: cacheURL)
    }
}
