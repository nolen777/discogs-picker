import Foundation

enum DiscogsAPIError: LocalizedError {
    case invalidURL
    case invalidResponse
    case rateLimited
    case unauthorized
    case serverStatus(Int)

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            "Could not build the Discogs request."
        case .invalidResponse:
            "Discogs returned an unexpected response."
        case .rateLimited:
            "Discogs is rate limiting requests. Wait a moment and try again."
        case .unauthorized:
            "Discogs rejected these credentials."
        case let .serverStatus(status):
            "Discogs returned HTTP \(status)."
        }
    }
}

struct DiscogsAPI {
    private let session: URLSession
    private let decoder: JSONDecoder

    init(session: URLSession = .shared) {
        self.session = session
        self.decoder = JSONDecoder()
    }

    func fetchCollection(credentials: DiscogsCredentials) async throws -> [CollectionRelease] {
        var page = 1
        var pages = 1
        var releases: [CollectionRelease] = []

        repeat {
            let response = try await fetchCollectionPage(
                credentials: credentials,
                page: page,
                perPage: 100
            )
            releases.append(contentsOf: response.releases)
            pages = response.pagination.pages
            page += 1
        } while page <= pages

        return releases
    }

    private func fetchCollectionPage(
        credentials: DiscogsCredentials,
        page: Int,
        perPage: Int
    ) async throws -> DiscogsCollectionResponse {
        var components = URLComponents()
        components.scheme = "https"
        components.host = "api.discogs.com"
        components.path = "/users/\(credentials.username)/collection/folders/0/releases"
        components.queryItems = [
            URLQueryItem(name: "page", value: String(page)),
            URLQueryItem(name: "per_page", value: String(perPage)),
            URLQueryItem(name: "sort", value: "added"),
            URLQueryItem(name: "sort_order", value: "desc")
        ]

        guard let url = components.url else {
            throw DiscogsAPIError.invalidURL
        }

        var request = URLRequest(url: url)
        request.setValue("CrateShuffle/0.1 +https://github.com/nolen777/discogs-picker", forHTTPHeaderField: "User-Agent")
        request.setValue("Discogs token=\(credentials.token)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw DiscogsAPIError.invalidResponse
        }

        switch httpResponse.statusCode {
        case 200:
            return try decoder.decode(DiscogsCollectionResponse.self, from: data)
        case 401, 403:
            throw DiscogsAPIError.unauthorized
        case 429:
            throw DiscogsAPIError.rateLimited
        default:
            throw DiscogsAPIError.serverStatus(httpResponse.statusCode)
        }
    }
}
