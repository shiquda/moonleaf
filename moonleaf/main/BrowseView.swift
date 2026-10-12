//
//  BrowseView.swift
//  moonleaf
//
//  Copyright © 2026 naomisphere. All rights reserved.
//

import SwiftUI
import Combine

struct BrowseView: View {
    @StateObject private var WHServ = WHService()
    @StateObject private var pexelsServ = PexelsService()
    @State private var searchQuery = ""
    @State private var chosen_sorting: WHSort = .date_added
    @State private var chosen_order: WHOrder = .desc
    @State private var chosen_topRange: WHTopRange = .week
    @State private var chosen_purity: WHPurityStatus = .sfw
    @State private var chosen_categ: WHCategory = .all
    @State private var chosen_prov: Set<WallpaperProvider> = [.wallhaven]
    @State private var selectedResolution: ResolutionFilter = .all
    @State private var activeResolutionFilter: ResolutionFilter = .all
    @State private var currentPage = 1
    @State private var showFilters = false
    @State private var isLoading = false
    @State private var apiKey = ""
    @State private var pexelsAPIKey: String = ""
    @State private var showPexelsKeyAlert = false
    @State private var pexelsKeyError = false
    @Binding var previewTarget: PreviewTarget?

    enum ResolutionFilter: String, CaseIterable {
        case hd = "HD"
        case fullHd = "Full HD"
        case wqhd = "WQHD"
        case uhd4k = "4K UHD"
        case all = "All"

        var displayName: String {
            switch self {
            case .hd: return "HD"
            case .fullHd: return "Full HD"
            case .wqhd: return "WQHD"
            case .uhd4k: return "4K"
            case .all: return NSLocalizedString("filter_resolution_all", comment: "All")
            }
        }

        func matches(width: Int, height: Int) -> Bool {
            switch self {
            case .all:
                return true
            case .hd:
                let totalPixels = width * height
                return totalPixels >= 800_000 && totalPixels < 1_500_000
            case .fullHd:
                let totalPixels = width * height
                return totalPixels >= 1_500_000 && totalPixels < 3_000_000
            case .wqhd:
                let totalPixels = width * height
                return totalPixels >= 3_000_000 && totalPixels < 5_000_000
            case .uhd4k:
                let totalPixels = width * height
                return totalPixels >= 5_000_000
            }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            searchBar
                .padding(.horizontal, 24)
                .padding(.top, 16)
                .padding(.bottom, 8)

            if isLoading {
                loadingView
            } else if filteredWallpapers.isEmpty {
                emptyStateView
            } else {
                contentView
            }

            if chosen_prov.contains(.pexels) {
                Button(action: {
                    if let url = URL(string: "https://www.pexels.com") {
                        NSWorkspace.shared.open(url)
                    }
                }) {
                    Text("Photos provided by Pexels")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(.secondary.opacity(0.6))
                        .padding(.vertical, 8)
                }
                .buttonStyle(.plain)
            }
        }
        .onAppear {
            loadPexelsAPIKey()
            if WHServ.wallpapers.isEmpty && pexelsServ.videos.isEmpty {
                loadWallpapers()
            }
        }
        .alert("Pexels API Key", isPresented: $showPexelsKeyAlert) {
            TextField("Enter API Key", text: $apiKey)
            Button("Save") {
                let keyToTry = apiKey
                pexelsServ.validateAPIKey(keyToTry) { isValid in
                    DispatchQueue.main.async {
                        if isValid {
                            pexelsAPIKey = keyToTry
                            savePexelsAPIKey(keyToTry)
                            pexelsServ.setAPIKey(keyToTry)
                            chosen_prov.insert(.pexels)
                            apiKey = ""
                            loadWallpapers()
                        } else {
                            pexelsKeyError = true
                        }
                    }
                }
            }
            Button("Cancel", role: .cancel) {
                apiKey = ""
            }
        } message: {
            Text("Get a free API key from pexels.com")
        }
        .alert("Invalid API Key", isPresented: $pexelsKeyError) {
            Button("OK", role: .cancel) { }
        } message: {
            Text("The API key you entered appeared to be invalid. Please check and try again.")
        }
    }

    private func loadPexelsAPIKey() {
        pexelsAPIKey = MoonleafConfigStore.shared.readPexelsAPIKey()
        pexelsServ.setAPIKey(pexelsAPIKey)
    }

    private func savePexelsAPIKey(_ key: String) {
        try? MoonleafConfigStore.shared.writePexelsAPIKey(key)
    }
    private var searchBar: some View {
        HStack(spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)
                    .font(Font(font_loader.regular(size: 14)))

                TextField(NSLocalizedString("browse_search_placeholder", comment: "Search wallpapers..."), text: $searchQuery)
                    .textFieldStyle(PlainTextFieldStyle())
                    .font(Font(font_loader.regular(size: 14)))
                    .onSubmit {
                        currentPage = 1
                        loadWallpapers()
                    }

                if !searchQuery.isEmpty {
                    Button(action: {
                        searchQuery = ""
                        currentPage = 1
                        loadWallpapers()
                    }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(PlainButtonStyle())
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background {
                RoundedRectangle(cornerRadius: 12)
                    .fill(.regularMaterial)
                    .overlay {
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(.primary.opacity(0.1), lineWidth: 1)
                    }
            }

            Button(action: {
                showFilters.toggle()
            }) {
                Image(systemName: "slider.horizontal.3")
                    .font(Font(font_loader.regular(size: 14)))
                    .foregroundColor(.primary)
                    .padding(10)
                    .background {
                        RoundedRectangle(cornerRadius: 10)
                            .fill(.regularMaterial)
                            .overlay {
                                RoundedRectangle(cornerRadius: 10)
                                    .stroke(.primary.opacity(0.1), lineWidth: 1)
                            }
                    }
            }
            .buttonStyle(PlainButtonStyle())
            .popover(isPresented: $showFilters) {
                filtersView
                    .frame(width: 300)
                    .padding()
            }
        }
    }

    private var filtersView: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text(NSLocalizedString("browse_filters", comment: "Filters"))
                .font(Font(font_loader.bold(size: 16)))

            VStack(alignment: .leading, spacing: 12) {
                Text(NSLocalizedString("browse_provider", comment: "Source"))
                    .font(Font(font_loader.regular(size: 12)))
                    .foregroundColor(.secondary)

                LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 2), spacing: 8) {
                    ForEach(WallpaperProvider.allCases, id: \.self) { provider in
                        providerToggle(provider: provider)
                    }
                }
            }

            if chosen_prov.contains(.wallhaven) {
                VStack(alignment: .leading, spacing: 12) {
                    Text(NSLocalizedString("browse_category", comment: "Category"))
                        .font(Font(font_loader.regular(size: 12)))
                        .foregroundColor(.secondary)

                    Picker("", selection: $chosen_categ) {
                        ForEach(WHCategory.allCases, id: \.self) { category in
                            Text(category.displayName).tag(category)
                        }
                    }
                    .pickerStyle(SegmentedPickerStyle())
                }

                VStack(alignment: .leading, spacing: 12) {
                    Text(NSLocalizedString("browse_purity", comment: "Purity"))
                        .font(Font(font_loader.regular(size: 12)))
                        .foregroundColor(.secondary)

                    Picker("", selection: $chosen_purity) {
                        ForEach(WHPurityStatus.allCases, id: \.self) { purity in
                            Text(purity.displayName).tag(purity)
                        }
                    }
                    .pickerStyle(SegmentedPickerStyle())
                }
            }

            VStack(alignment: .leading, spacing: 12) {
                Text(NSLocalizedString("browse_resolution", comment: "Resolution"))
                    .font(Font(font_loader.regular(size: 12)))
                    .foregroundColor(.secondary)

                Picker("", selection: $selectedResolution) {
                    ForEach(ResolutionFilter.allCases, id: \.self) { resolution in
                        Text(resolution.displayName).tag(resolution)
                    }
                }
                .pickerStyle(SegmentedPickerStyle())
            }

            VStack(alignment: .leading, spacing: 12) {
                Text(NSLocalizedString("browse_sort", comment: "Sort by"))
                    .font(Font(font_loader.regular(size: 12)))
                    .foregroundColor(.secondary)

                Picker("", selection: $chosen_sorting) {
                    ForEach(WHSort.allCases, id: \.self) { sorting in
                        Text(sorting.displayName).tag(sorting)
                    }
                }
                .pickerStyle(MenuPickerStyle())

                if chosen_sorting == .toplist {
                    Text(NSLocalizedString("browse_top_range", comment: "Time Range"))
                        .font(Font(font_loader.regular(size: 12)))
                        .foregroundColor(.secondary)

                    Picker("", selection: $chosen_topRange) {
                        ForEach(WHTopRange.allCases, id: \.self) { range in
                            Text(range.displayName).tag(range)
                        }
                    }
                    .pickerStyle(SegmentedPickerStyle())
                } else {
                    Picker("", selection: $chosen_order) {
                        Text(NSLocalizedString("browse_desc", comment: "Descending")).tag(WHOrder.desc)
                        Text(NSLocalizedString("browse_asc", comment: "Ascending")).tag(WHOrder.asc)
                    }
                    .pickerStyle(SegmentedPickerStyle())
                }
            }

            Button(action: {
                activeResolutionFilter = selectedResolution
                currentPage = 1
                loadWallpapers()
                showFilters = false
            }) {
                Text(NSLocalizedString("browse_apply", comment: "Apply Filters"))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
            }
            .buttonStyle(.borderedProminent)
        }
    }

    private func providerToggle(provider: WallpaperProvider) -> some View {
        Toggle(isOn: Binding(
            get: { chosen_prov.contains(provider) },
            set: { isSelected in
                if isSelected {
                    if provider == .pexels && pexelsAPIKey.isEmpty {
                        showPexelsKeyAlert = true
                    } else {
                        chosen_prov.insert(provider)
                    }
                } else {
                    chosen_prov.remove(provider)
                }
            }
        )) {
            HStack(spacing: 6) {
                Image(systemName: provider.icon)
                    .font(Font(font_loader.regular(size: 11)))
                Text(provider.displayName)
                    .font(Font(font_loader.regular(size: 11)))
            }
        }
        .toggleStyle(CBToggle())
    }

    private var contentView: some View {
        ScrollView {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 20), count: 3), spacing: 20) {
                ForEach(filteredWallpapers) { wallpaper in
                    BrowseWallpaperCard(item: wallpaper, onPreview: { openPreview(for: wallpaper) })
                        .onAppear {
                            if wallpaper.id == filteredWallpapers.last?.id {
                                loadNextPage()
                            }
                        }
                }
            }
            .padding(24)
        }
    }

    private var filteredWallpapers: [AnyWallpaper] {
        var items: [AnyWallpaper] = []
        if chosen_prov.contains(.wallhaven) {
            items.append(contentsOf: WHServ.wallpapers)
        }
        if chosen_prov.contains(.pexels) {
            items.append(contentsOf: pexelsServ.videos)
        }
        return items.filter { item in
            activeResolutionFilter.matches(width: item.width, height: item.height)
        }
    }

    private var loadingView: some View {
        VStack(spacing: 20) {
            ProgressView()
                .scaleEffect(1.2)
            Text(NSLocalizedString("browse_loading", comment: "Loading wallpapers..."))
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyStateView: some View {
        VStack(spacing: 16) {
            Image(systemName: "photo.on.rectangle")
                .font(Font(font_loader.regular(size: 48)))
                .foregroundColor(.secondary)
            Text(NSLocalizedString("browse_no_results", comment: "No wallpapers found"))
                .font(Font(font_loader.regular(size: 16)))
            Text(NSLocalizedString("browse_try_search", comment: "Try adjusting your search or filters"))
                .font(Font(font_loader.regular(size: 14)))
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// Opens the same full-screen preview the library cards use. Browse items
    /// have no file on disk, so the preview streams the provider's
    /// full-resolution asset and falls back to the card thumbnail.
    private func openPreview(for item: AnyWallpaper) {
        guard let url = item.downloadURL ?? item.previewURL else { return }
        withAnimation(.easeInOut(duration: 0.3)) {
            previewTarget = PreviewTarget(
                url: url,
                title: item.id,
                detail: "\(item.width)x\(item.height)"
            )
        }
    }

    private func loadWallpapers() {
        isLoading = true
        let group = DispatchGroup()

        if chosen_prov.contains(.wallhaven) {
            group.enter()
            WHServ.searchWallpapers(
                query: searchQuery.isEmpty ? nil : searchQuery,
                sorting: chosen_sorting,
                order: chosen_order,
                purity: chosen_purity,
                category: chosen_categ,
                topRange: chosen_topRange,
                page: currentPage
            ) {
                group.leave()
            }
        } else {
            WHServ.wallpapers = []
        }

        if chosen_prov.contains(.pexels) {
            if !pexelsAPIKey.isEmpty {
                group.enter()
                pexelsServ.searchVideos(
                    query: searchQuery.isEmpty ? "nature" : searchQuery,
                    page: currentPage,
                    perPage: 24
                ) {
                    group.leave()
                }
            } else {
                pexelsServ.videos = []
            }
        } else {
            pexelsServ.videos = []
        }

        group.notify(queue: .main) {
            isLoading = false
        }
    }

    private func loadNextPage() {
        currentPage += 1
        if chosen_prov.contains(.wallhaven) {
            WHServ.loadMoreWallpapers(
                query: searchQuery.isEmpty ? nil : searchQuery,
                sorting: chosen_sorting,
                order: chosen_order,
                purity: chosen_purity,
                category: chosen_categ,
                topRange: chosen_topRange,
                page: currentPage
            )
        }
        if chosen_prov.contains(.pexels) && !pexelsAPIKey.isEmpty {
            pexelsServ.loadMoreVideos(
                query: searchQuery.isEmpty ? "nature" : searchQuery,
                page: currentPage,
                perPage: 24
            )
        }
    }
}

struct CBToggle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack {
            configuration.label
            Spacer()
            Image(systemName: configuration.isOn ? "checkmark.square.fill" : "square")
                .foregroundColor(configuration.isOn ? .blue : .secondary)
                .onTapGesture { configuration.isOn.toggle() }
        }
    }
}

struct BrowseWallpaperCard: View {
    let item: AnyWallpaper
    let onPreview: () -> Void
    @State private var image: NSImage?
    @State private var isLoading = true
    @State private var isHovered = false
    @State private var isDownloading = false
    @State private var isDownloaded = false
    @State private var downloadProgress: Double = 0
    @State private var downloadTask: URLSessionDownloadTask?
    @State private var progressObservation: NSKeyValueObservation?
    @State private var imageTask: URLSessionDataTask?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ZStack {
                if let image = image {
                    Image(nsImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(height: 200)
                        .clipped()
                } else {
                    Rectangle()
                        .fill(Color.gray.opacity(0.3))
                        .frame(height: 200)

                    if isLoading {
                        ProgressView()
                    }
                }

                if item.isVideo {
                    VStack {
                        HStack {
                            Spacer()
                            Image(systemName: "play.circle.fill")
                                .font(.title)
                                .foregroundColor(.white)
                                .shadow(radius: 2)
                        }
                        Spacer()
                    }
                    .padding(8)
                }

                if isHovered {
                    VStack {
                        HStack {
                            Spacer()
                            downloadButton
                        }
                        Spacer()
                        if item.provider == .pexels {
                            HStack {
                                if let author = item.authorName, let url = item.authorURL {
                                    Button(action: { NSWorkspace.shared.open(url) }) {
                                        Text("Photo by \(author)")
                                            .font(.system(size: 9, weight: .medium))
                                            .foregroundColor(.white.opacity(0.8))
                                            .padding(.horizontal, 8)
                                            .padding(.vertical, 4)
                                            .background(Capsule().fill(Color.black.opacity(0.4)))
                                    }
                                    .buttonStyle(.plain)
                                }
                                Spacer()
                                Button(action: { if let url = item.itemURL { NSWorkspace.shared.open(url) } }) {
                                    Text("on Pexels")
                                        .font(.system(size: 9, weight: .medium))
                                        .foregroundColor(.white.opacity(0.8))
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 4)
                                        .background(Capsule().fill(Color.black.opacity(0.4)))
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    .padding(8)
                }

                if isDownloading {
                    ZStack {
                        Circle()
                            .stroke(Color.white.opacity(0.2), lineWidth: 3)

                        Circle()
                            .trim(from: 0, to: max(0.05, downloadProgress))
                            .stroke(Color.white, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                            .rotationEffect(.degrees(-90))
                    }
                    .frame(width: 32, height: 32)
                    .background(Circle().fill(Color.black.opacity(0.4)))
                }
            }
            .frame(height: 200)
            .cornerRadius(12)
            .contentShape(Rectangle())
            .onTapGesture { onPreview() }

            Text(item.id)
                .font(Font(font_loader.regular(size: 12)))
                .lineLimit(1)

            Text("\(item.width)x\(item.height)")
                .font(Font(font_loader.regular(size: 10)))
                .foregroundColor(.secondary)
        }
        .contentShape(Rectangle())
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.2)) {
                isHovered = hovering
            }
        }
        .onAppear {
            loadPreview()
            checkIfDownloaded()
        }
        .onDisappear {
            downloadTask?.cancel()
            progressObservation?.invalidate()
            imageTask?.cancel()
        }
    }

    private var downloadButton: some View {
        Button(action: {
            if !isDownloaded {
                downloadWallpaper()
            }
        }) {
            ZStack {
                if isDownloaded {
                    Image(systemName: "checkmark.circle.fill")
                        .font(Font(font_loader.regular(size: 20)))
                        .foregroundColor(.green)
                } else if isDownloading {
                    ProgressView()
                        .scaleEffect(0.7)
                        .brightness(1)
                } else {
                    Image(systemName: "arrow.down.circle.fill")
                        .font(Font(font_loader.regular(size: 20)))
                        .foregroundColor(.white)
                }
            }
            .padding(8)
            .background(Circle().fill(Color.black.opacity(0.6)))
        }
        .buttonStyle(PlainButtonStyle())
        .disabled(isDownloading || isDownloaded)
    }

    private func checkIfDownloaded() {
        guard let downloadURL = item.downloadURL else { return }
        let wpStorageDir = macpaperService.wp_storage_dir
        let fileName = "\(item.id)-\(downloadURL.lastPathComponent)"
        let destinationURL = wpStorageDir.appendingPathComponent(fileName)

        if FileManager.default.fileExists(atPath: destinationURL.path) {
            isDownloaded = true
        }
    }

    private func loadPreview() {
        guard let previewURL = item.previewURL else {
            isLoading = false
            return
        }

        let cacheKey = previewURL.absoluteString
        if let cachedImage = ImageCache.remote.getImage(forKey: cacheKey) {
            self.image = cachedImage
            self.isLoading = false
            return
        }

        imageTask = URLSession.shared.dataTask(with: previewURL) { data, _, error in
            if error != nil {
                DispatchQueue.main.async {
                    self.isLoading = false
                }
                return
            }

            guard let data = data, let nsImage = NSImage(data: data) else {
                DispatchQueue.main.async {
                    self.isLoading = false
                }
                return
            }

            ImageCache.remote.setImage(nsImage, forKey: cacheKey)

            DispatchQueue.main.async {
                self.image = nsImage
                self.isLoading = false
            }
        }
        imageTask?.resume()
    }

    private func downloadWallpaper(retryCount: Int = 0) {
        guard let downloadURL = item.downloadURL else { return }

        let wpStorageDir = macpaperService.wp_storage_dir

        do {
            try FileManager.default.createDirectory(at: wpStorageDir, withIntermediateDirectories: true)

            let fileName = "\(item.id)-\(downloadURL.lastPathComponent)"
            let destinationURL = wpStorageDir.appendingPathComponent(fileName)

            if FileManager.default.fileExists(atPath: destinationURL.path) {
                isDownloaded = true
                return
            }

            isDownloading = true
            downloadProgress = 0

            downloadTask = URLSession.shared.downloadTask(with: downloadURL) { tempURL, _, error in
                DispatchQueue.main.async {
                    self.isDownloading = false
                    self.progressObservation?.invalidate()
                    self.progressObservation = nil
                }

                if error != nil {
                    if retryCount < 2 {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                            self.downloadWallpaper(retryCount: retryCount + 1)
                        }
                    }
                    return
                }

                guard let tempURL = tempURL else {
                    return
                }

                do {
                    if FileManager.default.fileExists(atPath: destinationURL.path) {
                        try? FileManager.default.removeItem(at: destinationURL)
                    }
                    try FileManager.default.moveItem(at: tempURL, to: destinationURL)

                    DispatchQueue.main.async {
                        self.isDownloaded = true
                        NotificationCenter.default.post(
                            name: NSNotification.Name("WallpaperDownloadCompleted"),
                            object: nil
                        )
                    }
                } catch {
                }
            }

            progressObservation = downloadTask?.progress.observe(\.fractionCompleted) { progress, _ in
                DispatchQueue.main.async {
                    self.downloadProgress = progress.fractionCompleted
                }
            }

            downloadTask?.resume()

        } catch {
            isDownloading = false
            downloadProgress = 0
        }
    }
}
