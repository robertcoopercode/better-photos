import SwiftUI
import Photos
import Combine

@MainActor
class AppState: ObservableObject {
    // MARK: - Photo Library
    @Published var photos: [PhotoAsset] = []
    @Published var albums: [Album] = []  // Flat list (legacy, for compatibility)
    @Published var albumItems: [SidebarItem] = []  // Hierarchical structure with folders
    @Published var expandedFolderIds: Set<String> = []  // Track which folders are expanded
    @Published var selectedAlbum: Album? = nil
    @Published var selectedKeyword: KeywordWithCount? = nil
    @Published var keywordsWithCounts: [KeywordWithCount] = []

    // MARK: - Keyword Multi-Select
    @Published var selectedKeywordIds: Set<String> = []
    private var lastSelectedKeywordIndex: Int?

    /// Keywords that were explicitly deleted (hidden from sidebar)
    private var hiddenKeywords: Set<String> {
        get {
            Set(UserDefaults.standard.stringArray(forKey: "hiddenKeywords") ?? [])
        }
        set {
            UserDefaults.standard.set(Array(newValue), forKey: "hiddenKeywords")
        }
    }
    @Published var isLoadingPhotos = false
    @Published var photoLibraryAuthorized = false
    @Published var totalPhotoCount: Int = 0

    // MARK: - Photos Without Faces Filter
    @Published var showPhotosWithoutFaces: Bool = false
    @Published var photosWithoutFacesCount: Int = 0

    // MARK: - Selection
    @Published var selectedPhotoIds: Set<String> = []
    @Published var focusedPhotoId: String?
    @Published var lastSelectedIndex: Int?

    // MARK: - Tags
    @Published var currentTags: [String] = []  // For single selection (backward compat)
    @Published var commonTags: [String] = []   // Tags on ALL selected photos
    @Published var partialTags: [String] = []  // Tags on SOME but not all selected photos
    @Published var aiSuggestions: [TagSuggestion] = []  // Raw Vision analysis
    @Published var recommendedTags: [TagSuggestion] = []  // Existing tags matched to Vision
    @Published var allKnownTags: [String] = []

    // Cache of tags per photo for multi-select
    private var photoTagsCache: [String: [String]] = [:]

    // MARK: - Albums for Selected Photos
    @Published var commonAlbums: [Album] = []   // Albums containing ALL selected photos
    @Published var partialAlbums: [Album] = []  // Albums containing SOME but not all selected photos

    // Cache of albums per photo for multi-select
    private var photoAlbumsCache: [String: [Album]] = [:]

    // MARK: - People/Pets
    @Published var allKnownPeople: [PersonInfo] = []  // All people/pets in library
    @Published var commonPeople: [PersonInfo] = []    // People in ALL selected photos
    @Published var partialPeople: [PersonInfo] = []   // People in SOME but not all selected photos

    // Cache of people per photo
    private var photoPeopleCache: [String: [PersonInfo]] = [:]

    // MARK: - UI State
    @Published var focusTagInput = false
    @Published var focusAlbumInput = false
    @Published var isPhotosAppRunning = false
    @Published var isSyncing = false
    @Published var errorMessage: String?
    @Published var showError = false
    @Published var gridColumnCount: Int = 4
    @Published var showQuickPreview = false

    // MARK: - Services
    let photoLibraryService = PhotoLibraryService()
    let keywordService = AppleScriptKeywordService()
    let photosDatabaseService = PhotosDatabaseService()
    let visionService = VisionTaggingService()
    let tagRecommendationService = TagRecommendationService()
    let thumbnailCache = ThumbnailCache()
    let photosMonitor = PhotosAppMonitor()

    private var cancellables = Set<AnyCancellable>()

    init() {
        setupBindings()
    }

    private func setupBindings() {
        photosMonitor.$isRunning
            .receive(on: DispatchQueue.main)
            .assign(to: &$isPhotosAppRunning)
    }

    // MARK: - Photo Library

    func requestAuthorization() async {
        photoLibraryAuthorized = await photoLibraryService.requestAuthorization()
        if photoLibraryAuthorized {
            await refreshPhotos()
            await refreshAlbums()
            await loadAllKnownTags()
            await loadKeywordsWithCounts()
            await loadAllKnownPeople()
            await loadPhotosWithoutFacesCount()
        }
    }

    /// Loads the count of photos without detected faces
    private func loadPhotosWithoutFacesCount() async {
        photosWithoutFacesCount = photosDatabaseService.getPhotosWithoutFacesCount()
    }

    /// Loads all keywords with their photo counts for the sidebar (including empty ones)
    private func loadKeywordsWithCounts() async {
        var keywords = photosDatabaseService.getKeywordsWithCounts(includeEmpty: true)

        // Filter out hidden keywords (orphaned keywords that were explicitly deleted)
        // But unhide them if they now have photos again
        var currentHidden = hiddenKeywords
        for keyword in keywords where currentHidden.contains(keyword.keyword) {
            if keyword.count > 0 {
                // Keyword has photos again, unhide it
                currentHidden.remove(keyword.keyword)
            }
        }
        hiddenKeywords = currentHidden

        // Filter out remaining hidden keywords
        keywords = keywords.filter { !hiddenKeywords.contains($0.keyword) }

        keywordsWithCounts = keywords
    }

    /// Loads all known people/pets from the Photos library
    private func loadAllKnownPeople() async {
        let people = photosDatabaseService.getAllPeople()
        allKnownPeople = people
    }

    /// Loads all unique keywords from the Photos library for autocomplete
    private func loadAllKnownTags() async {
        // Use direct database query - much faster than AppleScript
        var tags = photosDatabaseService.getAllKeywords()
        if !tags.isEmpty {
            // Filter out hidden (deleted) keywords
            tags = tags.filter { !hiddenKeywords.contains($0) }
            allKnownTags = tags
        } else {
            // Fallback to AppleScript if database query fails
            do {
                try await keywordService.ensurePhotosRunning()
                var tags = try await keywordService.getAllKeywords()
                // Filter out hidden (deleted) keywords
                tags = tags.filter { !hiddenKeywords.contains($0) }
                allKnownTags = tags.sorted()
            } catch {
                // Fallback silently if AppleScript fails
            }
        }
    }

    func refreshPhotos() async {
        isLoadingPhotos = true
        defer { isLoadingPhotos = false }

        do {
            if let album = selectedAlbum {
                photos = try await photoLibraryService.fetchPhotosFromAlbum(album)
            } else if let keyword = selectedKeyword {
                photos = try await photoLibraryService.fetchPhotosByKeyword(keyword.keyword)
            } else if showPhotosWithoutFaces {
                photos = try await photoLibraryService.fetchPhotosWithoutFaces()
            } else {
                photos = try await photoLibraryService.fetchAllPhotos()
                totalPhotoCount = photos.count  // Update total count when viewing all photos
            }
            clearSelection()
        } catch {
            showError(message: "Failed to load photos: \(error.localizedDescription)")
        }
    }

    func refreshAlbums() async {
        albums = await photoLibraryService.fetchAlbums()
        albumItems = await photoLibraryService.fetchAlbumHierarchy()
    }

    func toggleFolderExpanded(_ folderId: String) {
        if expandedFolderIds.contains(folderId) {
            expandedFolderIds.remove(folderId)
        } else {
            expandedFolderIds.insert(folderId)
        }
    }


    /// Find an album by ID in the hierarchical structure
    func findAlbum(byId id: String) -> Album? {
        // First check flat list
        if let album = albums.first(where: { $0.id == id }) {
            return album
        }
        // Then search hierarchical structure
        return findAlbumInItems(albumItems, id: id)
    }

    private func findAlbumInItems(_ items: [SidebarItem], id: String) -> Album? {
        for item in items {
            switch item {
            case .album(let album):
                if album.id == id {
                    return album
                }
            case .folder(let folder):
                if let found = findAlbumInItems(folder.children, id: id) {
                    return found
                }
            }
        }
        return nil
    }

    func selectAlbum(id: String?) async {
        if let id = id {
            selectedAlbum = albums.first { $0.id == id }
            selectedKeyword = nil  // Clear keyword filter when selecting album
            showPhotosWithoutFaces = false  // Clear faces filter when selecting album
        } else {
            selectedAlbum = nil
            selectedKeyword = nil
            showPhotosWithoutFaces = false
        }
        await refreshPhotos()
    }

    func selectKeyword(_ keyword: String?) async {
        if let keyword = keyword {
            selectedKeyword = keywordsWithCounts.first { $0.keyword == keyword }
            selectedAlbum = nil  // Clear album filter when selecting keyword
            showPhotosWithoutFaces = false  // Clear faces filter when selecting keyword
            // Clear multi-select when doing regular selection
            selectedKeywordIds = [keyword]
            if let index = keywordsWithCounts.firstIndex(where: { $0.keyword == keyword }) {
                lastSelectedKeywordIndex = index
            }
        } else {
            selectedKeyword = nil
            selectedKeywordIds.removeAll()
            lastSelectedKeywordIndex = nil
            showPhotosWithoutFaces = false
        }
        await refreshPhotos()
    }

    /// Select keyword with modifier keys (Cmd for toggle, Shift for range)
    func selectKeywordWithModifiers(_ keyword: String, index: Int, modifiers: EventModifiers) {
        if modifiers.contains(.command) {
            // Command+click: Toggle selection
            if selectedKeywordIds.contains(keyword) {
                selectedKeywordIds.remove(keyword)
            } else {
                selectedKeywordIds.insert(keyword)
            }
            lastSelectedKeywordIndex = index
        } else if modifiers.contains(.shift), let lastIndex = lastSelectedKeywordIndex {
            // Shift+click: Range selection
            let range = min(lastIndex, index)...max(lastIndex, index)
            for i in range where i < keywordsWithCounts.count {
                selectedKeywordIds.insert(keywordsWithCounts[i].keyword)
            }
        } else {
            // Regular click: Single selection (handled by selectKeyword)
            Task {
                await selectKeyword(keyword)
            }
            return
        }

        // Update selectedKeyword to reflect primary selection (last clicked)
        selectedKeyword = keywordsWithCounts.first { $0.keyword == keyword }
        selectedAlbum = nil
    }

    /// Get all selected keywords
    var selectedKeywords: [KeywordWithCount] {
        keywordsWithCounts.filter { selectedKeywordIds.contains($0.keyword) }
    }

    /// Clear keyword selection
    func clearKeywordSelection() {
        selectedKeywordIds.removeAll()
        selectedKeyword = nil
        lastSelectedKeywordIndex = nil
    }

    /// Select photos without faces filter
    func selectPhotosWithoutFaces() async {
        selectedAlbum = nil
        selectedKeyword = nil
        selectedKeywordIds.removeAll()
        lastSelectedKeywordIndex = nil
        showPhotosWithoutFaces = true
        await refreshPhotos()
    }

    /// Send selected photos to Photos.app for tagging by creating a temporary album
    func sendSelectedPhotosToPhotosForTagging() async {
        let photoIds = Array(selectedPhotoIds)
        guard !photoIds.isEmpty else { return }

        isSyncing = true
        defer { isSyncing = false }

        do {
            try await keywordService.openPhotosForTagging(photoIds: photoIds)
        } catch {
            showError(message: "Failed to send photos to Photos: \(error.localizedDescription)")
        }
    }

    // MARK: - Renaming

    func renameAlbum(_ album: Album, to newName: String) async {
        guard !newName.isEmpty, newName != album.title else { return }

        do {
            try await PHPhotoLibrary.shared().performChanges {
                guard let changeRequest = PHAssetCollectionChangeRequest(for: album.collection) else {
                    return
                }
                changeRequest.title = newName
            }

            // Refresh albums list
            await refreshAlbums()

            // If this was the selected album, update the selection
            if selectedAlbum?.id == album.id {
                selectedAlbum = albums.first { $0.id == album.id }
            }
        } catch {
            showError(message: "Failed to rename album: \(error.localizedDescription)")
        }
    }

    func renameKeyword(from oldName: String, to newName: String) async {
        guard !newName.isEmpty, oldName != newName else { return }

        // Get all photos with the old keyword
        let photoUUIDs = photosDatabaseService.getPhotoUUIDsWithKeyword(oldName)
        guard !photoUUIDs.isEmpty else { return }

        isSyncing = true

        // Escape quotes in keyword names for AppleScript
        let escapedOldName = oldName.replacingOccurrences(of: "\"", with: "\\\"")
        let escapedNewName = newName.replacingOccurrences(of: "\"", with: "\\\"")

        // Phase 1: Add new keyword to ALL photos first (safer - if this fails, old keyword still exists)
        var addSuccessCount = 0
        for uuid in photoUUIDs {
            let addScript = """
                tell application "Photos"
                    try
                        set targetPhoto to first media item whose id contains "\(uuid)"
                        set currentKeywords to keywords of targetPhoto
                        -- Only add if not already present
                        if currentKeywords does not contain "\(escapedNewName)" then
                            set keywords of targetPhoto to currentKeywords & {"\(escapedNewName)"}
                        end if
                        return "success"
                    on error errMsg
                        return "error: " & errMsg
                    end try
                end tell
                """

            var error: NSDictionary?
            if let script = NSAppleScript(source: addScript) {
                let result = script.executeAndReturnError(&error)
                if error == nil, result.stringValue?.starts(with: "success") == true {
                    addSuccessCount += 1
                }
            }
        }

        // Only proceed to remove old keyword if we successfully added to at least some photos
        if addSuccessCount > 0 {
            // Phase 2: Remove old keyword from all photos
            for uuid in photoUUIDs {
                let removeScript = """
                    tell application "Photos"
                        try
                            set targetPhoto to first media item whose id contains "\(uuid)"
                            set currentKeywords to keywords of targetPhoto
                            set newKeywords to {}
                            repeat with kw in currentKeywords
                                if kw as text is not "\(escapedOldName)" then
                                    set end of newKeywords to kw
                                end if
                            end repeat
                            set keywords of targetPhoto to newKeywords
                            return "success"
                        on error errMsg
                            return "error: " & errMsg
                        end try
                    end tell
                    """

                var error: NSDictionary?
                if let script = NSAppleScript(source: removeScript) {
                    script.executeAndReturnError(&error)
                }
            }
        } else {
            showError(message: "Failed to rename keyword - could not add new keyword to any photos")
        }

        isSyncing = false

        // Update selected keyword if it was renamed
        if selectedKeyword?.keyword == oldName {
            selectedKeyword = KeywordWithCount(keyword: newName, count: selectedKeyword?.count ?? 0)
        }

        // Refresh keyword counts and autocomplete list after a delay
        try? await Task.sleep(nanoseconds: 1_500_000_000)
        await loadKeywordsWithCounts()
        await loadAllKnownTags()

        // If viewing the renamed keyword, refresh photos
        if selectedKeyword?.keyword == newName {
            await refreshPhotos()
        }
    }

    // MARK: - Deletion (Albums & Keywords)

    /// Deletes an album without deleting the photos in it
    func deleteAlbum(_ album: Album) async {
        do {
            try await PHPhotoLibrary.shared().performChanges {
                PHAssetCollectionChangeRequest.deleteAssetCollections([album.collection] as NSFastEnumeration)
            }

            // Clear selection if this was the selected album
            if selectedAlbum?.id == album.id {
                selectedAlbum = nil
                await refreshPhotos()
            }

            // Refresh albums list
            await refreshAlbums()
        } catch {
            showError(message: "Failed to delete album: \(error.localizedDescription)")
        }
    }

    /// Deletes a keyword by removing it from all photos that have it
    func deleteKeyword(_ keyword: String) async {
        // Get all photos with this keyword
        let photoUUIDs = photosDatabaseService.getPhotoUUIDsWithKeyword(keyword)

        // If there are photos with this keyword, remove it from them
        if !photoUUIDs.isEmpty {
            isSyncing = true

            let escapedKeyword = keyword.replacingOccurrences(of: "\"", with: "\\\"")

            for uuid in photoUUIDs {
                let removeScript = """
                    tell application "Photos"
                        try
                            set targetPhoto to first media item whose id contains "\(uuid)"
                            set currentKeywords to keywords of targetPhoto
                            set newKeywords to {}
                            repeat with kw in currentKeywords
                                if kw as text is not "\(escapedKeyword)" then
                                    set end of newKeywords to kw
                                end if
                            end repeat
                            set keywords of targetPhoto to newKeywords
                            return "success"
                        on error errMsg
                            return "error: " & errMsg
                        end try
                    end tell
                    """

                var error: NSDictionary?
                if let script = NSAppleScript(source: removeScript) {
                    script.executeAndReturnError(&error)
                }
            }

            isSyncing = false

            // After removing from all photos, hide the keyword so it doesn't reappear as orphaned
            var hidden = hiddenKeywords
            hidden.insert(keyword)
            hiddenKeywords = hidden
        } else {
            // Keyword has no photos - it's orphaned in the database
            // We can't delete it directly, so we hide it permanently
            var hidden = hiddenKeywords
            hidden.insert(keyword)
            hiddenKeywords = hidden
            keywordsWithCounts.removeAll { $0.keyword == keyword }
        }

        // Clear selection if this was the selected keyword
        if selectedKeyword?.keyword == keyword {
            selectedKeyword = nil
            await refreshPhotos()
        }

        // Refresh keyword counts and autocomplete list after a delay
        try? await Task.sleep(nanoseconds: 1_500_000_000)
        await loadKeywordsWithCounts()
        await loadAllKnownTags()
    }

    /// Deletes multiple selected keywords
    func deleteSelectedKeywords() async {
        let keywordsToDelete = Array(selectedKeywordIds)
        guard !keywordsToDelete.isEmpty else { return }

        for keyword in keywordsToDelete {
            // Get all photos with this keyword
            let photoUUIDs = photosDatabaseService.getPhotoUUIDsWithKeyword(keyword)

            if !photoUUIDs.isEmpty {
                isSyncing = true

                let escapedKeyword = keyword.replacingOccurrences(of: "\"", with: "\\\"")

                for uuid in photoUUIDs {
                    let removeScript = """
                        tell application "Photos"
                            try
                                set targetPhoto to first media item whose id contains "\(uuid)"
                                set currentKeywords to keywords of targetPhoto
                                set newKeywords to {}
                                repeat with kw in currentKeywords
                                    if kw as text is not "\(escapedKeyword)" then
                                        set end of newKeywords to kw
                                    end if
                                end repeat
                                set keywords of targetPhoto to newKeywords
                            end try
                        end tell
                        """

                    var error: NSDictionary?
                    if let script = NSAppleScript(source: removeScript) {
                        script.executeAndReturnError(&error)
                    }
                }

                isSyncing = false
            }

            // Hide the keyword
            var hidden = hiddenKeywords
            hidden.insert(keyword)
            hiddenKeywords = hidden
        }

        // Clear selection
        selectedKeywordIds.removeAll()
        selectedKeyword = nil
        lastSelectedKeywordIndex = nil

        // Remove from local list immediately for responsiveness
        keywordsWithCounts.removeAll { keywordsToDelete.contains($0.keyword) }

        // Refresh after delay
        try? await Task.sleep(nanoseconds: 1_500_000_000)
        await loadKeywordsWithCounts()
        await loadAllKnownTags()
        await refreshPhotos()
    }

    // MARK: - Selection

    var selectedPhotos: [PhotoAsset] {
        photos.filter { selectedPhotoIds.contains($0.id) }
    }

    var selectedPhoto: PhotoAsset? {
        guard selectedPhotoIds.count == 1,
              let id = selectedPhotoIds.first else { return nil }
        return photos.first { $0.id == id }
    }

    func selectPhoto(id: String, index: Int, modifiers: EventModifiers = []) {
        if modifiers.contains(.command) {
            // Toggle selection
            if selectedPhotoIds.contains(id) {
                selectedPhotoIds.remove(id)
            } else {
                selectedPhotoIds.insert(id)
            }
        } else if modifiers.contains(.shift), let lastIndex = lastSelectedIndex {
            // Range selection
            let range = min(lastIndex, index)...max(lastIndex, index)
            for i in range where i < photos.count {
                selectedPhotoIds.insert(photos[i].id)
            }
        } else {
            // Single selection
            selectedPhotoIds = [id]
        }
        lastSelectedIndex = index
        focusedPhotoId = id

        // Load tags, albums, and people for selected photos
        Task {
            await loadTagsForSelectedPhotos()
            await loadAlbumsForSelectedPhotos()
            await loadPeopleForSelectedPhotos()
            if selectedPhotoIds.count == 1 {
                await analyzeSelectedPhoto()
            } else {
                aiSuggestions = [] // Clear AI suggestions for multi-select
            }
        }
    }

    func selectAll() {
        selectedPhotoIds = Set(photos.map { $0.id })
    }

    func clearSelection() {
        selectedPhotoIds.removeAll()
        focusedPhotoId = nil
        lastSelectedIndex = nil
        currentTags = []
        commonTags = []
        partialTags = []
        aiSuggestions = []
        photoTagsCache.removeAll()
        commonAlbums = []
        partialAlbums = []
        photoAlbumsCache.removeAll()
        commonPeople = []
        partialPeople = []
        photoPeopleCache.removeAll()
    }

    func navigateSelection(direction: NavigationDirection, extendSelection: Bool = false) {
        guard !photos.isEmpty else { return }

        let columnsCount = max(1, gridColumnCount)
        var newIndex: Int

        if let currentId = focusedPhotoId,
           let currentIndex = photos.firstIndex(where: { $0.id == currentId }) {
            switch direction {
            case .left:
                newIndex = max(0, currentIndex - 1)
            case .right:
                newIndex = min(photos.count - 1, currentIndex + 1)
            case .up:
                newIndex = max(0, currentIndex - columnsCount)
            case .down:
                newIndex = min(photos.count - 1, currentIndex + columnsCount)
            }
        } else {
            newIndex = 0
        }

        let photo = photos[newIndex]

        if extendSelection {
            // Shift+Arrow: extend selection to include the new photo
            selectedPhotoIds.insert(photo.id)
            focusedPhotoId = photo.id
            lastSelectedIndex = newIndex

            // Reload tags, albums, and people for the updated selection
            Task {
                await loadTagsForSelectedPhotos()
                await loadAlbumsForSelectedPhotos()
                await loadPeopleForSelectedPhotos()
            }
        } else {
            selectPhoto(id: photo.id, index: newIndex)
        }
    }

    enum NavigationDirection {
        case left, right, up, down
    }

    // MARK: - Tags

    private func loadTagsForSelectedPhotos() async {
        let photoIds = Array(selectedPhotoIds)

        guard !photoIds.isEmpty else {
            currentTags = []
            commonTags = []
            partialTags = []
            return
        }

        // Load tags for all selected photos
        var allPhotoTags: [String: Set<String>] = [:]

        for photoId in photoIds {
            do {
                // Use cache if available
                if let cached = photoTagsCache[photoId] {
                    allPhotoTags[photoId] = Set(cached)
                } else {
                    let tags = try await keywordService.getKeywords(photoId: photoId)
                    photoTagsCache[photoId] = tags
                    allPhotoTags[photoId] = Set(tags)
                }
            } catch {
                allPhotoTags[photoId] = []
            }
        }

        // Calculate common tags (on ALL selected photos)
        var common: Set<String>?
        for (_, tags) in allPhotoTags {
            if common == nil {
                common = tags
            } else {
                common = common?.intersection(tags)
            }
        }

        // Calculate all tags across all photos
        var allTags: Set<String> = []
        for (_, tags) in allPhotoTags {
            allTags.formUnion(tags)
        }

        // Add discovered tags to allKnownTags for autocomplete
        for tag in allTags {
            if !allKnownTags.contains(tag) {
                allKnownTags.append(tag)
            }
        }
        allKnownTags.sort()

        // Partial tags = all tags minus common tags
        let commonSet = common ?? []
        let partial = allTags.subtracting(commonSet)

        commonTags = Array(commonSet).sorted()
        partialTags = Array(partial).sorted()

        // For backward compatibility, also set currentTags
        if photoIds.count == 1 {
            currentTags = commonTags
        } else {
            currentTags = commonTags
        }
    }

    // MARK: - Albums for Selected Photos

    private func loadAlbumsForSelectedPhotos() async {
        let photoIds = Array(selectedPhotoIds)

        guard !photoIds.isEmpty else {
            commonAlbums = []
            partialAlbums = []
            return
        }

        // Get PHAssets for selected photo IDs
        let selectedAssets = photos.filter { selectedPhotoIds.contains($0.id) }.map { $0.phAsset }

        // Load albums for all selected photos
        var allPhotoAlbums: [String: Set<String>] = [:]  // photoId -> Set of album IDs

        for (index, photoId) in photoIds.enumerated() {
            // Use cache if available
            if let cached = photoAlbumsCache[photoId] {
                allPhotoAlbums[photoId] = Set(cached.map { $0.id })
            } else if index < selectedAssets.count {
                let albumsForPhoto = await photoLibraryService.fetchAlbumsContaining(asset: selectedAssets[index])
                photoAlbumsCache[photoId] = albumsForPhoto
                allPhotoAlbums[photoId] = Set(albumsForPhoto.map { $0.id })
            }
        }

        // Calculate common albums (containing ALL selected photos)
        var commonAlbumIds: Set<String>?
        for (_, albumIds) in allPhotoAlbums {
            if commonAlbumIds == nil {
                commonAlbumIds = albumIds
            } else {
                commonAlbumIds = commonAlbumIds?.intersection(albumIds)
            }
        }

        // Calculate all albums across all photos
        var allAlbumIds: Set<String> = []
        for (_, albumIds) in allPhotoAlbums {
            allAlbumIds.formUnion(albumIds)
        }

        // Partial albums = all albums minus common albums
        let commonSet = commonAlbumIds ?? []
        let partialAlbumIds = allAlbumIds.subtracting(commonSet)

        // Convert album IDs back to Album objects
        commonAlbums = albums.filter { commonSet.contains($0.id) }.sorted { $0.title < $1.title }
        partialAlbums = albums.filter { partialAlbumIds.contains($0.id) }.sorted { $0.title < $1.title }
    }

    func addTag(_ tag: String) async {
        let trimmed = tag.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !trimmed.isEmpty else { return }
        guard !commonTags.contains(trimmed) else { return }

        let photoIds = Array(selectedPhotoIds)
        guard !photoIds.isEmpty else { return }

        isSyncing = true
        defer { isSyncing = false }

        do {
            try await keywordService.ensurePhotosRunning()

            for photoId in photoIds {
                try await keywordService.addKeywords(photoId: photoId, newKeywords: [trimmed])

                // Update cache
                if var cached = photoTagsCache[photoId] {
                    if !cached.contains(trimmed) {
                        cached.append(trimmed)
                        photoTagsCache[photoId] = cached
                    }
                }
            }

            // Update local state - tag is now common to all selected photos
            if !commonTags.contains(trimmed) {
                commonTags.append(trimmed)
                commonTags.sort()
            }
            // Remove from partial tags if it was there
            partialTags.removeAll { $0 == trimmed }

            // Update currentTags for backward compat
            currentTags = commonTags

            if !allKnownTags.contains(trimmed) {
                allKnownTags.append(trimmed)
            }

            // Remove from suggestions if present
            aiSuggestions.removeAll { $0.tag.lowercased() == trimmed }

            // Refresh sidebar keyword counts after a delay to let Photos.app sync
            try? await Task.sleep(nanoseconds: 1_500_000_000)  // 1.5 seconds
            await loadKeywordsWithCounts()
        } catch {
            showError(message: "Failed to add tag: \(error.localizedDescription)")
        }
    }

    func removeTag(_ tag: String) async {
        let photoIds = Array(selectedPhotoIds)
        guard !photoIds.isEmpty else { return }

        isSyncing = true
        defer { isSyncing = false }

        do {
            try await keywordService.ensurePhotosRunning()

            for photoId in photoIds {
                try await keywordService.removeKeywords(photoId: photoId, keywordsToRemove: [tag])

                // Update cache
                if var cached = photoTagsCache[photoId] {
                    cached.removeAll { $0 == tag }
                    photoTagsCache[photoId] = cached
                }
            }

            // Update local state
            commonTags.removeAll { $0 == tag }
            partialTags.removeAll { $0 == tag }
            currentTags = commonTags

            // Refresh sidebar keyword counts after a delay to let Photos.app sync
            try? await Task.sleep(nanoseconds: 1_500_000_000)  // 1.5 seconds
            await loadKeywordsWithCounts()
        } catch {
            showError(message: "Failed to remove tag: \(error.localizedDescription)")
        }
    }

    /// Remove a partial tag from all photos that have it
    func removePartialTag(_ tag: String) async {
        let photoIds = Array(selectedPhotoIds)
        guard !photoIds.isEmpty else { return }

        isSyncing = true
        defer { isSyncing = false }

        do {
            try await keywordService.ensurePhotosRunning()

            for photoId in photoIds {
                // Only remove from photos that have this tag
                if let cached = photoTagsCache[photoId], cached.contains(tag) {
                    try await keywordService.removeKeywords(photoId: photoId, keywordsToRemove: [tag])

                    // Update cache
                    var updated = cached
                    updated.removeAll { $0 == tag }
                    photoTagsCache[photoId] = updated
                }
            }

            // Update local state
            partialTags.removeAll { $0 == tag }

            // Refresh sidebar keyword counts after a delay to let Photos.app sync
            try? await Task.sleep(nanoseconds: 1_500_000_000)  // 1.5 seconds
            await loadKeywordsWithCounts()
        } catch {
            showError(message: "Failed to remove tag: \(error.localizedDescription)")
        }
    }

    /// Promote a partial tag to all selected photos (make it common)
    func applyPartialTagToAll(_ tag: String) async {
        await addTag(tag)
    }

    // MARK: - AI Suggestions

    private func analyzeSelectedPhoto() async {
        guard let photo = selectedPhoto else {
            aiSuggestions = []
            recommendedTags = []
            return
        }

        do {
            let image = try await photoLibraryService.loadFullImage(for: photo.phAsset, maxDimension: 1024)
            guard let cgImage = image?.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
                return
            }

            // Get Vision analysis of what's in the image
            let visionSuggestions = try await visionService.analyzeTags(for: cgImage)

            // Filter out Vision suggestions that are already applied
            aiSuggestions = visionSuggestions.filter { suggestion in
                !currentTags.contains(suggestion.tag.lowercased())
            }

            // Use Vision results to recommend existing tags from the user's library
            let recommendations = tagRecommendationService.recommendTags(
                fromVisionSuggestions: visionSuggestions,
                existingTags: allKnownTags,
                currentTags: currentTags,
                limit: 10
            )

            recommendedTags = recommendations
        } catch {
            aiSuggestions = []
            recommendedTags = []
        }
    }

    func acceptSuggestion(_ suggestion: TagSuggestion) async {
        await addTag(suggestion.tag)
    }

    func acceptAllSuggestions() {
        Task {
            for suggestion in aiSuggestions {
                await addTag(suggestion.tag)
            }
        }
    }

    func rejectSuggestion(_ suggestion: TagSuggestion) {
        aiSuggestions.removeAll { $0.id == suggestion.id }
    }

    // MARK: - Deletion

    func deleteSelectedPhotos() async {
        let photosToDelete = selectedPhotos
        guard !photosToDelete.isEmpty else { return }

        // Find the index to focus after deletion (the photo after the last selected one)
        let deletedIds = Set(photosToDelete.map { $0.id })
        var nextFocusIndex: Int? = nil

        // Find the highest index among selected photos
        if let maxSelectedIndex = photos.indices.filter({ deletedIds.contains(photos[$0].id) }).max() {
            // The next photo after the last deleted one
            nextFocusIndex = maxSelectedIndex + 1 - deletedIds.count
        }

        let assets = photosToDelete.map { $0.phAsset }

        do {
            try await photoLibraryService.deletePhotos(assets)

            // Remove deleted photos from local state
            photos.removeAll { deletedIds.contains($0.id) }

            // Clear caches
            for id in deletedIds {
                photoTagsCache.removeValue(forKey: id)
                photoAlbumsCache.removeValue(forKey: id)
                photoPeopleCache.removeValue(forKey: id)
            }

            // Focus on the next photo after deletion
            if !photos.isEmpty, let focusIndex = nextFocusIndex {
                let safeIndex = min(focusIndex, photos.count - 1)
                let photoToFocus = photos[safeIndex]
                selectPhoto(id: photoToFocus.id, index: safeIndex)
            } else {
                clearSelection()
            }

            // Refresh sidebar keyword counts after deletion
            try? await Task.sleep(nanoseconds: 500_000_000)  // 0.5 seconds
            await loadKeywordsWithCounts()
        } catch {
            showError(message: "Failed to delete photos: \(error.localizedDescription)")
        }
    }

    // MARK: - People for Selected Photos

    private func loadPeopleForSelectedPhotos() async {
        let photoIds = Array(selectedPhotoIds)

        guard !photoIds.isEmpty else {
            commonPeople = []
            partialPeople = []
            return
        }

        // Load people for all selected photos
        var allPhotoPeople: [String: Set<String>] = [:]  // photoId -> Set of person names (using name as ID for consistency)

        for photoId in photoIds {
            // Use cache if available
            if let cached = photoPeopleCache[photoId] {
                allPhotoPeople[photoId] = Set(cached.map { $0.name })
            } else {
                let people = photosDatabaseService.getPeopleInPhoto(photoUUID: photoId)
                photoPeopleCache[photoId] = people
                allPhotoPeople[photoId] = Set(people.map { $0.name })
            }
        }

        // Calculate common people (in ALL selected photos)
        var commonNames: Set<String>?
        for (_, personNames) in allPhotoPeople {
            if commonNames == nil {
                commonNames = personNames
            } else {
                commonNames = commonNames?.intersection(personNames)
            }
        }

        // Calculate all people across all photos
        var allPersonNames: Set<String> = []
        for (_, personNames) in allPhotoPeople {
            allPersonNames.formUnion(personNames)
        }

        // Partial people = all people minus common people
        let commonSet = commonNames ?? []
        let partialNames = allPersonNames.subtracting(commonSet)

        // Convert names back to PersonInfo objects
        // Build a map by name from all known people and cache
        var peopleByName: [String: PersonInfo] = [:]
        for person in allKnownPeople {
            peopleByName[person.name] = person
        }
        for (_, people) in photoPeopleCache {
            for person in people {
                if peopleByName[person.name] == nil {
                    peopleByName[person.name] = person
                }
            }
        }

        commonPeople = commonSet.compactMap { peopleByName[$0] }.sorted { $0.name < $1.name }
        partialPeople = partialNames.compactMap { peopleByName[$0] }.sorted { $0.name < $1.name }
    }

    // MARK: - Album Management

    /// Available albums that the selected photos are NOT already in
    var availableAlbumsForSelection: [Album] {
        // Filter out albums that all selected photos are already in
        albums.filter { album in
            !commonAlbums.contains { $0.id == album.id }
        }
    }

    func addSelectedPhotosToAlbum(_ album: Album) async {
        let photoIds = Array(selectedPhotoIds)
        guard !photoIds.isEmpty else { return }

        isSyncing = true
        defer { isSyncing = false }

        do {
            try await keywordService.ensurePhotosRunning()

            for photoId in photoIds {
                // Only add if photo isn't already in this album
                let currentAlbums = photoAlbumsCache[photoId] ?? []
                if !currentAlbums.contains(where: { $0.id == album.id }) {
                    try await keywordService.addToAlbum(photoId: photoId, albumId: album.id)

                    // Update cache
                    var updated = currentAlbums
                    updated.append(album)
                    photoAlbumsCache[photoId] = updated
                }
            }

            // Reload albums for selection to update UI
            await loadAlbumsForSelectedPhotos()
        } catch {
            showError(message: "Failed to add to album: \(error.localizedDescription)")
        }
    }

    func removeSelectedPhotosFromAlbum(_ album: Album) async {
        let photoIds = Array(selectedPhotoIds)
        guard !photoIds.isEmpty else { return }

        isSyncing = true
        defer { isSyncing = false }

        do {
            try await keywordService.ensurePhotosRunning()

            for photoId in photoIds {
                try await keywordService.removeFromAlbum(photoId: photoId, albumId: album.id)

                // Update cache
                if var cached = photoAlbumsCache[photoId] {
                    cached.removeAll { $0.id == album.id }
                    photoAlbumsCache[photoId] = cached
                }
            }

            // Reload albums for selection to update UI
            await loadAlbumsForSelectedPhotos()
        } catch {
            showError(message: "Failed to remove from album: \(error.localizedDescription)")
        }
    }

    func createAlbumAndAddSelectedPhotos(name: String) async {
        let photoIds = Array(selectedPhotoIds)
        guard !photoIds.isEmpty else { return }
        guard !name.trimmingCharacters(in: .whitespaces).isEmpty else { return }

        isSyncing = true
        defer { isSyncing = false }

        do {
            try await keywordService.ensurePhotosRunning()

            // Create the album
            let albumId = try await keywordService.createAlbum(name: name)

            // Add all selected photos to it
            for photoId in photoIds {
                try await keywordService.addToAlbum(photoId: photoId, albumId: albumId)
            }

            // Refresh albums list to include the new album
            await refreshAlbums()
            await loadAlbumsForSelectedPhotos()
        } catch {
            showError(message: "Failed to create album: \(error.localizedDescription)")
        }
    }

    // MARK: - Helpers

    private func showError(message: String) {
        errorMessage = message
        showError = true
    }
}
