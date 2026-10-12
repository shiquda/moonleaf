//
//  BrowseProviders.swift
//  moonleaf
//
//  Copyright © 2026 naomisphere. All rights reserved.
//

import Foundation
import Combine

enum WallpaperProvider: String, CaseIterable {
    case wallhaven = "wallhaven"
    case pexels = "pexels"

    var displayName: String {
        switch self {
        case .wallhaven: return "Wallhaven"
        case .pexels: return "Pexels"
        }
    }

    var icon: String {
        switch self {
        case .wallhaven: return "globe"
        case .pexels: return "video"
        }
    }
}

protocol WallpaperItem: Identifiable {
    var id: String { get }
    var width: Int { get }
    var height: Int { get }
    var previewURL: URL? { get }
    var downloadURL: URL? { get }
    var isVideo: Bool { get }
    var authorName: String? { get }
    var authorURL: URL? { get }
    var itemURL: URL? { get }
}

struct AnyWallpaper: Identifiable {
    let id: String
    let width: Int
    let height: Int
    let previewURL: URL?
    let downloadURL: URL?
    let isVideo: Bool
    let authorName: String?
    let authorURL: URL?
    let itemURL: URL?
    let provider: WallpaperProvider

    init<T: WallpaperItem>(_ item: T, provider: WallpaperProvider) {
        self.id = item.id
        self.width = item.width
        self.height = item.height
        self.previewURL = item.previewURL
        self.downloadURL = item.downloadURL
        self.isVideo = item.isVideo
        self.authorName = item.authorName
        self.authorURL = item.authorURL
        self.itemURL = item.itemURL
        self.provider = provider
    }
}

extension WHWallpaper: WallpaperItem {
    var width: Int { dimension_x }
    var height: Int { dimension_y }
    var previewURL: URL? { URL(string: thumbs.large) }
    var downloadURL: URL? { URL(string: path) }
    var isVideo: Bool { false }
    var authorName: String? { nil }
    var authorURL: URL? { nil }
    var itemURL: URL? { URL(string: url) }
}

class WHService: ObservableObject {
    @Published var wallpapers: [AnyWallpaper] = []
    private let baseURL = "https://wallhaven.cc/api/v1/search"
    private var currentSeed: String?
    private var apiKey: String = ""

    init() {
        loadAPIKey()
    }

    func loadAPIKey() {
        apiKey = MoonleafConfigStore.shared.readWallhavenAPIKey()
    }

    func searchWallpapers(
        query: String? = nil,
        sorting: WHSort = .date_added,
        order: WHOrder = .desc,
        purity: WHPurityStatus = .sfw,
        category: WHCategory = .all,
        topRange: WHTopRange = .week,
        page: Int = 1,
        completion: (() -> Void)? = nil
    ) {
        fetch(
            query: query,
            sorting: sorting,
            order: order,
            purity: purity,
            category: category,
            topRange: topRange,
            page: page,
            append: false,
            completion: completion
        )
    }

    func loadMoreWallpapers(
        query: String? = nil,
        sorting: WHSort = .date_added,
        order: WHOrder = .desc,
        purity: WHPurityStatus = .sfw,
        category: WHCategory = .all,
        topRange: WHTopRange = .week,
        page: Int
    ) {
        fetch(
            query: query,
            sorting: sorting,
            order: order,
            purity: purity,
            category: category,
            topRange: topRange,
            page: page,
            append: true,
            completion: nil
        )
    }

    private func fetch(
        query: String?,
        sorting: WHSort,
        order: WHOrder,
        purity: WHPurityStatus,
        category: WHCategory,
        topRange: WHTopRange,
        page: Int,
        append: Bool,
        completion: (() -> Void)?
    ) {
        loadAPIKey()
        var components = URLComponents(string: baseURL)!
        var queryItems: [URLQueryItem] = []

        if let query = query, !query.isEmpty {
            queryItems.append(URLQueryItem(name: "q", value: query))
        }

        queryItems.append(URLQueryItem(name: "sorting", value: sorting.rawValue))
        queryItems.append(URLQueryItem(name: "order", value: order.rawValue))
        queryItems.append(URLQueryItem(name: "purity", value: purity.rawValue))
        queryItems.append(URLQueryItem(name: "categories", value: category.rawValue))
        queryItems.append(URLQueryItem(name: "page", value: "\(page)"))

        // wallhaven only honours topRange on the toplist listing
        if sorting == .toplist {
            queryItems.append(URLQueryItem(name: "topRange", value: topRange.rawValue))
        }

        if sorting == .random, let seed = currentSeed {
            queryItems.append(URLQueryItem(name: "seed", value: seed))
        }

        components.queryItems = queryItems

        guard let url = components.url else {
            completion?()
            return
        }

        var request = URLRequest(url: url)
        if !apiKey.isEmpty {
            request.addValue(apiKey, forHTTPHeaderField: "X-API-Key")
        }

        URLSession.shared.dataTask(with: request) { data, _, error in
            defer { completion?() }

            if error != nil {
                return
            }

            guard let data = data else { return }

            do {
                let response = try JSONDecoder().decode(WHResponse.self, from: data)
                let fetched = response.data.map { AnyWallpaper($0, provider: .wallhaven) }
                DispatchQueue.main.async {
                    if append {
                        self.wallpapers.append(contentsOf: fetched)
                    } else {
                        self.wallpapers = fetched
                    }
                    if let seed = response.meta.seed {
                        self.currentSeed = seed
                    }
                }
            } catch {
                print("while decoding response: \(error)")
            }
        }.resume()
    }
}

class PexelsService: ObservableObject {
    @Published var videos: [AnyWallpaper] = []
    private let baseURL = "https://api.pexels.com/v1/videos"
    private var apiKey: String = ""

    func setAPIKey(_ key: String) {
        apiKey = key
    }

    func validateAPIKey(_ key: String, completion: @escaping (Bool) -> Void) {
        var components = URLComponents(string: "\(baseURL)/search")!
        components.queryItems = [
            URLQueryItem(name: "query", value: "test"),
            URLQueryItem(name: "per_page", value: "1")
        ]
        guard let url = components.url else { completion(false); return }
        var request = URLRequest(url: url)
        request.addValue(key, forHTTPHeaderField: "Authorization")

        URLSession.shared.dataTask(with: request) { data, response, _ in
            if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200, let data = data {
                do {
                    _ = try JSONDecoder().decode(PexelsSearchResponse.self, from: data)
                    completion(true)
                } catch {
                    completion(false)
                }
            } else {
                completion(false)
            }
        }.resume()
    }

    func searchVideos(query: String, page: Int = 1, perPage: Int = 15, completion: (() -> Void)? = nil) {
        fetchVideos(query: query, page: page, perPage: perPage, append: false, completion: completion)
    }

    func loadMoreVideos(query: String, page: Int, perPage: Int = 15) {
        fetchVideos(query: query, page: page, perPage: perPage, append: true, completion: nil)
    }

    private func fetchVideos(
        query: String,
        page: Int,
        perPage: Int,
        append: Bool,
        completion: (() -> Void)?
    ) {
        guard !apiKey.isEmpty else {
            completion?()
            return
        }

        var components = URLComponents(string: "\(baseURL)/search")!
        components.queryItems = [
            URLQueryItem(name: "query", value: query),
            URLQueryItem(name: "per_page", value: "\(perPage)"),
            URLQueryItem(name: "page", value: "\(page)")
        ]

        guard let url = components.url else {
            completion?()
            return
        }

        var request = URLRequest(url: url)
        request.addValue(apiKey, forHTTPHeaderField: "Authorization")

        URLSession.shared.dataTask(with: request) { data, _, error in
            defer { completion?() }
            if error != nil { return }
            guard let data = data else { return }

            do {
                let response = try JSONDecoder().decode(PexelsSearchResponse.self, from: data)
                let items = response.videos.map { AnyWallpaper(PexelsVideoWrapper(video: $0), provider: .pexels) }
                DispatchQueue.main.async {
                    if append {
                        self.videos.append(contentsOf: items)
                    } else {
                        self.videos = items
                    }
                }
            } catch {
            }
        }.resume()
    }
}

struct PexelsVideoWrapper: WallpaperItem {
    let video: PexelsVideo

    var id: String { String(video.id) }
    var width: Int { video.width }
    var height: Int { video.height }
    var previewURL: URL? { URL(string: video.image) }
    var downloadURL: URL? {
        let sorted = video.video_files.sorted {
            ($0.width ?? 0) * ($0.height ?? 0) > ($1.width ?? 0) * ($1.height ?? 0)
        }
        if let best = sorted.first, let url = URL(string: best.link) {
            return url
        }
        return nil
    }
    var isVideo: Bool { true }
    var authorName: String? { video.user?.name }
    var authorURL: URL? { video.user?.url != nil ? URL(string: video.user!.url!) : nil }
    var itemURL: URL? { video.url != nil ? URL(string: video.url!) : nil }
}

struct PexelsSearchResponse: Codable {
    let page: Int
    let per_page: Int
    let total_results: Int
    let next_page: String?
    let videos: [PexelsVideo]
}

struct PexelsVideo: Codable {
    let id: Int
    let width: Int
    let height: Int
    let url: String?
    let image: String
    let duration: Int?
    let user: PexelsUser?
    let video_files: [PexelsVideoFile]
    let video_pictures: [PexelsVideoPicture]?
}

struct PexelsUser: Codable {
    let id: Int?
    let name: String?
    let url: String?
}

struct PexelsVideoFile: Codable {
    let id: Int
    let quality: String?
    let file_type: String?
    let width: Int?
    let height: Int?
    let link: String
}

struct PexelsVideoPicture: Codable {
    let id: Int?
    let picture: String?
    let nr: Int?
}

struct WHResponse: Codable {
    let data: [WHWallpaper]
    let meta: WHMeta
}

struct WHWallpaper: Codable {
    let id: String
    let url: String
    let short_url: String
    let views: Int
    let favorites: Int
    let source: String
    let purity: String
    let category: String
    let dimension_x: Int
    let dimension_y: Int
    let resolution: String
    let ratio: String
    let file_size: Int
    let file_type: String
    let created_at: String
    let colors: [String]
    let path: String
    let thumbs: WHThumbs
}

struct WHThumbs: Codable {
    let large: String
    let original: String
    let small: String
}

struct WHMeta: Codable {
    let current_page: Int
    let last_page: Int
    let per_page: Int
    let total: Int
    let query: String?
    let seed: String?
}

enum WHSort: String, CaseIterable {
    case date_added = "date_added"
    case relevance = "relevance"
    case random = "random"
    case views = "views"
    case favorites = "favorites"
    case toplist = "toplist"

    var displayName: String {
        switch self {
        case .date_added: return NSLocalizedString("sort_date", comment: "Date Added")
        case .relevance: return NSLocalizedString("sort_relevance", comment: "Relevance")
        case .random: return NSLocalizedString("sort_random", comment: "Random")
        case .views: return NSLocalizedString("sort_views", comment: "Views")
        case .favorites: return NSLocalizedString("sort_favorites", comment: "Favorites")
        case .toplist: return NSLocalizedString("sort_top", comment: "Toplist")
        }
    }
}

enum WHOrder: String {
    case desc = "desc"
    case asc = "asc"
}

enum WHTopRange: String, CaseIterable {
    case day = "1d"
    case threeDays = "3d"
    case week = "1w"
    case month = "1M"
    case threeMonths = "3M"
    case sixMonths = "6M"
    case year = "1y"

    // same short tokens wallhaven uses in its own toplist range selector
    var displayName: String { rawValue.uppercased() }
}

enum WHPurityStatus: String, CaseIterable {
    case sfw = "100"

    var displayName: String {
        switch self {
        case .sfw: return "SFW"
        }
    }
}

enum WHCategory: String, CaseIterable {
    case general = "100"
    case anime = "010"
    case people = "001"
    case all = "111"

    var displayName: String {
        switch self {
        case .general: return NSLocalizedString("category_general", comment: "General")
        case .anime: return NSLocalizedString("category_anime", comment: "Anime")
        case .people: return NSLocalizedString("category_people", comment: "People")
        case .all: return NSLocalizedString("category_all", comment: "All")
        }
    }
}
