import Foundation

struct DiscogsCredentials: Codable, Equatable {
    var username: String
    var token: String

    var isComplete: Bool {
        !username.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
            !token.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

struct DiscogsCollectionResponse: Decodable {
    let pagination: Pagination
    let releases: [CollectionRelease]

    struct Pagination: Decodable {
        let page: Int
        let pages: Int
        let items: Int
    }
}

struct CollectionRelease: Codable, Identifiable, Equatable {
    let instanceId: Int
    let rating: Int?
    let basicInformation: BasicInformation
    let folderId: Int?
    let dateAdded: String?
    let id: Int

    var discogsURL: URL? {
        URL(string: "https://www.discogs.com/release/\(basicInformation.id)")
    }

    var displayArtist: String {
        basicInformation.artists.map(\.displayName).joined(separator: ", ")
    }

    var formatLine: String {
        basicInformation.formats.map { format in
            let descriptions = format.descriptions?.joined(separator: ", ")
            return [format.qty.map { "\($0)x" }, format.name, descriptions]
                .compactMap { value in
                    guard let value, !value.isEmpty else { return nil }
                    return value
                }
                .joined(separator: " ")
        }
        .joined(separator: " + ")
    }

    var labelLine: String {
        basicInformation.labels.map(\.name).joined(separator: ", ")
    }

    enum CodingKeys: String, CodingKey {
        case instanceId = "instance_id"
        case rating
        case basicInformation = "basic_information"
        case folderId = "folder_id"
        case dateAdded = "date_added"
        case id
    }
}

struct BasicInformation: Codable, Equatable {
    let id: Int
    let title: String
    let year: Int?
    let thumb: String?
    let coverImage: String?
    let resourceURL: String?
    let artists: [DiscogsArtist]
    let formats: [DiscogsFormat]
    let labels: [DiscogsLabel]

    var artworkURL: URL? {
        fullArtworkURL ?? thumbnailArtworkURL
    }

    var thumbnailArtworkURL: URL? {
        guard let thumb, !thumb.isEmpty else { return nil }
        return URL(string: thumb)
    }

    var fullArtworkURL: URL? {
        guard let coverImage, !coverImage.isEmpty else { return nil }
        return URL(string: coverImage)
    }

    var artworkURLsForPrefetch: [URL] {
        [thumbnailArtworkURL, fullArtworkURL].compactMap(\.self)
    }

    enum CodingKeys: String, CodingKey {
        case id
        case title
        case year
        case thumb
        case coverImage = "cover_image"
        case resourceURL = "resource_url"
        case artists
        case formats
        case labels
    }
}

struct DiscogsArtist: Codable, Equatable {
    let name: String
    let anv: String?
    let join: String?

    var displayName: String {
        let candidate = if let anv, !anv.isEmpty { anv } else { name }
        return candidate.replacingOccurrences(of: #" \(\d+\)$"#, with: "", options: .regularExpression)
    }
}

struct DiscogsFormat: Codable, Equatable {
    let name: String
    let qty: String?
    let descriptions: [String]?
}

struct DiscogsLabel: Codable, Equatable {
    let name: String
    let catno: String?
}

struct CachedCollection: Codable {
    let username: String
    let fetchedAt: Date
    let releases: [CollectionRelease]
}
