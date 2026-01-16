import SwiftUI

struct TagPanelView: View {
    @EnvironmentObject var appState: AppState
    @State private var newTagText = ""
    @FocusState private var isTagInputFocused: Bool
    @State private var selectedSuggestionIndex: Int = 0
    @State private var showAllSuggestions: Bool = false

    // Album input state
    @State private var albumSearchText = ""
    @FocusState private var isAlbumInputFocused: Bool
    @State private var selectedAlbumIndex: Int = 0
    @State private var showAlbumDropdown: Bool = false


    var body: some View {
        Group {
            if appState.selectedPhotoIds.isEmpty {
                emptySelectionView
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        // Photo preview (only for single selection)
                        if appState.selectedPhotoIds.count == 1, let photo = appState.selectedPhoto {
                            PhotoPreviewView(photo: photo)
                        }

                        selectedPhotoInfo

                        // Albums section
                        if appState.selectedPhotoIds.count == 1 {
                            albumsSection
                        } else {
                            commonAlbumsSection
                            otherAlbumsSection
                        }

                        albumInputSection

                        Divider()

                        // People section (read-only - showing detected people)
                        if appState.selectedPhotoIds.count == 1 {
                            peopleSection
                        } else {
                            commonPeopleSection
                            otherPeopleSection
                        }

                        Divider()

                        if appState.selectedPhotoIds.count == 1 {
                            // Single photo: show simple tags section
                            currentTagsSection
                            recommendedTagsSection
                        } else {
                            // Multiple photos: show common and partial tags
                            allPhotosTagsSection
                            otherTagsSection
                        }

                        tagInputSection
                    }
                    .padding()
                }
            }
        }
        .onChange(of: appState.focusTagInput) { _, shouldFocus in
            if shouldFocus {
                isTagInputFocused = true
                appState.focusTagInput = false
            }
        }
        .onChange(of: appState.focusAlbumInput) { _, shouldFocus in
            if shouldFocus {
                isAlbumInputFocused = true
                appState.focusAlbumInput = false
            }
        }
    }

    private var emptySelectionView: some View {
        VStack(spacing: 12) {
            Image(systemName: "photo")
                .font(.system(size: 32))
                .foregroundColor(.secondary)
            Text("No Photo Selected")
                .font(.headline)
            Text("Select a photo to view and edit tags")
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var selectedPhotoInfo: some View {
        VStack(alignment: .leading, spacing: 4) {
            if appState.selectedPhotoIds.count == 1 {
                Text("1 Photo Selected")
                    .font(.headline)
            } else {
                Text("\(appState.selectedPhotoIds.count) Photos Selected")
                    .font(.headline)
            }

            if let photo = appState.selectedPhoto,
               let date = photo.creationDate {
                Text(date, style: .date)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }

    private var currentTagsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Current Tags")
                    .font(.subheadline)
                    .fontWeight(.medium)
                Spacer()
                if !appState.commonTags.isEmpty {
                    Text("\(appState.commonTags.count)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            if appState.commonTags.isEmpty {
                Text("No tags")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .italic()
            } else {
                FlowLayout(spacing: 6) {
                    ForEach(appState.commonTags, id: \.self) { tag in
                        TagChip(tag: tag, style: .applied) {
                            Task {
                                await appState.removeTag(tag)
                            }
                        }
                    }
                }
            }
        }
    }

    private var allPhotosTagsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("All Photos Tags")
                    .font(.subheadline)
                    .fontWeight(.medium)
                Spacer()
                if !appState.commonTags.isEmpty {
                    Text("\(appState.commonTags.count)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            Text("Tags applied to all \(appState.selectedPhotoIds.count) selected photos")
                .font(.caption2)
                .foregroundStyle(.tertiary)

            if appState.commonTags.isEmpty {
                Text("No common tags")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .italic()
            } else {
                FlowLayout(spacing: 6) {
                    ForEach(appState.commonTags, id: \.self) { tag in
                        TagChip(tag: tag, style: .applied) {
                            Task {
                                await appState.removeTag(tag)
                            }
                        }
                    }
                }
            }
        }
    }

    private var otherTagsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            if !appState.partialTags.isEmpty {
                HStack {
                    Text("Other Tags")
                        .font(.subheadline)
                        .fontWeight(.medium)
                    Spacer()
                    Text("\(appState.partialTags.count)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Text("Tags on some but not all selected photos")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)

                FlowLayout(spacing: 6) {
                    ForEach(appState.partialTags, id: \.self) { tag in
                        TagChip(tag: tag, style: .partial) {
                            Task {
                                await appState.applyPartialTagToAll(tag)
                            }
                        }
                    }
                }

                Text("Click a tag to apply to all selected photos")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
    }

    // MARK: - Album Sections

    private var albumsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Albums")
                    .font(.subheadline)
                    .fontWeight(.medium)
                Spacer()
                if !appState.commonAlbums.isEmpty {
                    Text("\(appState.commonAlbums.count)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            if appState.commonAlbums.isEmpty {
                Text("Not in any album")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .italic()
            } else {
                FlowLayout(spacing: 6) {
                    ForEach(appState.commonAlbums) { album in
                        AlbumChip(album: album) {
                            Task {
                                await appState.removeSelectedPhotosFromAlbum(album)
                            }
                        }
                    }
                }
            }
        }
    }

    private var commonAlbumsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Common Albums")
                    .font(.subheadline)
                    .fontWeight(.medium)
                Spacer()
                if !appState.commonAlbums.isEmpty {
                    Text("\(appState.commonAlbums.count)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            Text("Albums containing all \(appState.selectedPhotoIds.count) selected photos")
                .font(.caption2)
                .foregroundStyle(.tertiary)

            if appState.commonAlbums.isEmpty {
                Text("No common albums")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .italic()
            } else {
                FlowLayout(spacing: 6) {
                    ForEach(appState.commonAlbums) { album in
                        AlbumChip(album: album) {
                            Task {
                                await appState.removeSelectedPhotosFromAlbum(album)
                            }
                        }
                    }
                }
            }
        }
    }

    private var otherAlbumsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            if !appState.partialAlbums.isEmpty {
                HStack {
                    Text("Other Albums")
                        .font(.subheadline)
                        .fontWeight(.medium)
                    Spacer()
                    Text("\(appState.partialAlbums.count)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Text("Albums containing some but not all selected photos")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)

                FlowLayout(spacing: 6) {
                    ForEach(appState.partialAlbums) { album in
                        AlbumChip(album: album, style: .partial)
                    }
                }
            }
        }
    }

    // MARK: - Album Input

    private var filteredAlbums: [Album] {
        let available = appState.availableAlbumsForSelection

        if showAlbumDropdown && albumSearchText.isEmpty {
            return Array(available.prefix(10))
        }

        guard !albumSearchText.isEmpty else { return [] }
        let query = albumSearchText.lowercased()
        return available
            .filter { $0.title.lowercased().contains(query) }
            .prefix(10)
            .map { $0 }
    }

    /// Whether the typed text exactly matches an existing album name
    private var typedAlbumExists: Bool {
        let trimmed = albumSearchText.trimmingCharacters(in: .whitespaces).lowercased()
        return appState.albums.contains { $0.title.lowercased() == trimmed }
    }

    /// Whether to show the "Create new album" option
    private var showCreateAlbumOption: Bool {
        !albumSearchText.trimmingCharacters(in: .whitespaces).isEmpty && !typedAlbumExists
    }

    private var shouldShowAlbumDropdown: Bool {
        isAlbumInputFocused && (!filteredAlbums.isEmpty || showAlbumDropdown || showCreateAlbumOption)
    }

    /// Total number of items in the album dropdown
    private var totalAlbumDropdownItems: Int {
        (showCreateAlbumOption ? 1 : 0) + filteredAlbums.count
    }

    private func submitSelectedAlbum() {
        let trimmedText = albumSearchText.trimmingCharacters(in: .whitespaces)
        guard !trimmedText.isEmpty else { return }

        if showCreateAlbumOption && selectedAlbumIndex == 0 {
            // "Create new album" is selected
            Task {
                await appState.createAlbumAndAddSelectedPhotos(name: trimmedText)
                albumSearchText = ""
                showAlbumDropdown = false
            }
        } else if !filteredAlbums.isEmpty {
            // An existing album is selected
            let albumIndex = selectedAlbumIndex - (showCreateAlbumOption ? 1 : 0)
            if albumIndex >= 0 && albumIndex < filteredAlbums.count {
                let selectedAlbum = filteredAlbums[albumIndex]
                Task {
                    await appState.addSelectedPhotosToAlbum(selectedAlbum)
                    albumSearchText = ""
                    showAlbumDropdown = false
                }
            } else {
                // Fallback: create the album
                Task {
                    await appState.createAlbumAndAddSelectedPhotos(name: trimmedText)
                    albumSearchText = ""
                    showAlbumDropdown = false
                }
            }
        } else {
            // No suggestions, create the album
            Task {
                await appState.createAlbumAndAddSelectedPhotos(name: trimmedText)
                albumSearchText = ""
                showAlbumDropdown = false
            }
        }
    }

    private var albumInputSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Add to Album")
                .font(.subheadline)
                .fontWeight(.medium)

            HStack {
                TextField("Search or create album...", text: $albumSearchText)
                    .textFieldStyle(.roundedBorder)
                    .focused($isAlbumInputFocused)
                    .onSubmit {
                        submitSelectedAlbum()
                    }
                    .onKeyPress(.escape) {
                        if showAlbumDropdown {
                            showAlbumDropdown = false
                            return .handled
                        }
                        isAlbumInputFocused = false
                        return .handled
                    }
                    .onKeyPress(.downArrow) {
                        if shouldShowAlbumDropdown && totalAlbumDropdownItems > 0 {
                            selectedAlbumIndex = min(selectedAlbumIndex + 1, totalAlbumDropdownItems - 1)
                            return .handled
                        }
                        return .ignored
                    }
                    .onKeyPress(.upArrow) {
                        if shouldShowAlbumDropdown && totalAlbumDropdownItems > 0 {
                            selectedAlbumIndex = max(selectedAlbumIndex - 1, 0)
                            return .handled
                        }
                        return .ignored
                    }
                    .onKeyPress(characters: .init(charactersIn: " "), phases: .down) { keyPress in
                        // Control+Space to show all albums
                        if keyPress.modifiers.contains(.control) {
                            showAlbumDropdown = true
                            selectedAlbumIndex = 0
                            return .handled
                        }
                        return .ignored
                    }
                    .onChange(of: albumSearchText) { _, _ in
                        selectedAlbumIndex = 0
                    }

                Button {
                    guard !albumSearchText.isEmpty else { return }
                    submitSelectedAlbum()
                } label: {
                    Image(systemName: "folder.badge.plus")
                }
                .buttonStyle(.plain)
                .disabled(albumSearchText.isEmpty)
            }

            // Album dropdown
            if shouldShowAlbumDropdown && totalAlbumDropdownItems > 0 {
                VStack(alignment: .leading, spacing: 2) {
                    // "Create new album" option
                    if showCreateAlbumOption {
                        let isSelected = selectedAlbumIndex == 0
                        HStack {
                            Image(systemName: "folder.badge.plus")
                                .font(.caption)
                                .foregroundColor(.accentColor)
                            Text("Create \"\(albumSearchText.trimmingCharacters(in: .whitespaces))\"")
                                .font(.caption)
                            Spacer()
                            if isSelected {
                                Text("⏎")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(isSelected ? Color.accentColor.opacity(0.2) : Color.secondary.opacity(0.1))
                        .cornerRadius(4)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            Task {
                                await appState.createAlbumAndAddSelectedPhotos(name: albumSearchText)
                                albumSearchText = ""
                                showAlbumDropdown = false
                            }
                        }
                    }

                    // Existing albums
                    ForEach(Array(filteredAlbums.enumerated()), id: \.element.id) { index, album in
                        let adjustedIndex = index + (showCreateAlbumOption ? 1 : 0)
                        let isSelected = adjustedIndex == selectedAlbumIndex
                        HStack {
                            Image(systemName: album.icon)
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Text(album.title)
                                .font(.caption)
                            Spacer()
                            if isSelected {
                                Text("⏎")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(isSelected ? Color.accentColor.opacity(0.2) : Color.secondary.opacity(0.1))
                        .cornerRadius(4)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            Task {
                                await appState.addSelectedPhotosToAlbum(album)
                                albumSearchText = ""
                                showAlbumDropdown = false
                            }
                        }
                    }
                }
            }

            Text("A to focus • Ctrl+Space for suggestions • ↑↓ to navigate")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
    }

    // MARK: - People Sections

    private var peopleSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("People & Pets")
                    .font(.subheadline)
                    .fontWeight(.medium)
                Spacer()
                if !appState.commonPeople.isEmpty {
                    Text("\(appState.commonPeople.count)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            if appState.commonPeople.isEmpty {
                Text("No people detected")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .italic()
            } else {
                FlowLayout(spacing: 6) {
                    ForEach(appState.commonPeople) { person in
                        PersonChip(person: person)
                    }
                }
            }
        }
    }

    private var commonPeopleSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Common People")
                    .font(.subheadline)
                    .fontWeight(.medium)
                Spacer()
                if !appState.commonPeople.isEmpty {
                    Text("\(appState.commonPeople.count)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            Text("People in all \(appState.selectedPhotoIds.count) selected photos")
                .font(.caption2)
                .foregroundStyle(.tertiary)

            if appState.commonPeople.isEmpty {
                Text("No common people")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .italic()
            } else {
                FlowLayout(spacing: 6) {
                    ForEach(appState.commonPeople) { person in
                        PersonChip(person: person)
                    }
                }
            }
        }
    }

    private var otherPeopleSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            if !appState.partialPeople.isEmpty {
                HStack {
                    Text("Other People")
                        .font(.subheadline)
                        .fontWeight(.medium)
                    Spacer()
                    Text("\(appState.partialPeople.count)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Text("People in some but not all selected photos")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)

                FlowLayout(spacing: 6) {
                    ForEach(appState.partialPeople) { person in
                        PersonChip(person: person, style: .partial)
                    }
                }
            }
        }
    }

    private var aiSuggestionsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("AI Suggestions")
                    .font(.subheadline)
                    .fontWeight(.medium)
                Spacer()
                if !appState.aiSuggestions.isEmpty {
                    Button("Accept All") {
                        appState.acceptAllSuggestions()
                    }
                    .font(.caption)
                    .buttonStyle(.plain)
                    .foregroundColor(.accentColor)
                }
            }

            if appState.aiSuggestions.isEmpty {
                Text("Select a photo to see suggestions")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .italic()
            } else {
                FlowLayout(spacing: 6) {
                    ForEach(Array(appState.aiSuggestions.prefix(9).enumerated()), id: \.element.id) { index, suggestion in
                        TagChip(
                            tag: suggestion.tag,
                            style: .suggestion,
                            shortcutIndex: index + 1,
                            confidence: suggestion.confidencePercentage
                        ) {
                            Task {
                                await appState.acceptSuggestion(suggestion)
                            }
                        }
                    }
                }
            }
        }
    }

    private var recommendedTagsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Suggested Tags")
                    .font(.subheadline)
                    .fontWeight(.medium)
                Spacer()
                if !appState.recommendedTags.isEmpty {
                    Text("\(appState.recommendedTags.count)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            if appState.recommendedTags.isEmpty {
                Text("No matching tags found")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .italic()
            } else {
                FlowLayout(spacing: 6) {
                    ForEach(appState.recommendedTags) { suggestion in
                        TagChip(
                            tag: suggestion.tag,
                            style: .recommended,
                            confidence: suggestion.confidencePercentage
                        ) {
                            Task {
                                await appState.addTag(suggestion.tag)
                            }
                        }
                    }
                }
            }
        }
    }

    private var filteredSuggestions: [String] {
        let availableTags = appState.allKnownTags.filter { !appState.commonTags.contains($0) }

        if showAllSuggestions && newTagText.isEmpty {
            // Control+Space: show all available tags
            return Array(availableTags.prefix(10))
        }

        guard !newTagText.isEmpty else { return [] }
        let query = newTagText.lowercased()
        return availableTags
            .filter { $0.lowercased().contains(query) }
            .prefix(10)
            .map { $0 }
    }

    /// Whether the typed text exactly matches an existing tag
    private var typedTagExists: Bool {
        let trimmed = newTagText.trimmingCharacters(in: .whitespaces).lowercased()
        return appState.allKnownTags.contains { $0.lowercased() == trimmed }
    }

    /// Whether to show the "Create new tag" option
    private var showCreateNewOption: Bool {
        !newTagText.trimmingCharacters(in: .whitespaces).isEmpty && !typedTagExists
    }

    private var shouldShowSuggestions: Bool {
        isTagInputFocused && (!filteredSuggestions.isEmpty || showAllSuggestions || showCreateNewOption)
    }

    /// Total number of items in the dropdown (create option + suggestions)
    private var totalDropdownItems: Int {
        (showCreateNewOption ? 1 : 0) + filteredSuggestions.count
    }

    /// Submits the currently selected tag (either create new or existing suggestion)
    private func submitSelectedTag() {
        let trimmedText = newTagText.trimmingCharacters(in: .whitespaces)
        guard !trimmedText.isEmpty else { return }

        if showCreateNewOption && selectedSuggestionIndex == 0 {
            // "Create new tag" is selected
            Task {
                await appState.addTag(trimmedText)
                newTagText = ""
                showAllSuggestions = false
            }
        } else if !filteredSuggestions.isEmpty {
            // An existing suggestion is selected
            let suggestionIndex = selectedSuggestionIndex - (showCreateNewOption ? 1 : 0)
            if suggestionIndex >= 0 && suggestionIndex < filteredSuggestions.count {
                let selectedTag = filteredSuggestions[suggestionIndex]
                Task {
                    await appState.addTag(selectedTag)
                    newTagText = ""
                    showAllSuggestions = false
                }
            } else {
                // Fallback: create the typed tag
                Task {
                    await appState.addTag(trimmedText)
                    newTagText = ""
                    showAllSuggestions = false
                }
            }
        } else {
            // No suggestions, create the typed tag
            Task {
                await appState.addTag(trimmedText)
                newTagText = ""
                showAllSuggestions = false
            }
        }
    }

    private var tagInputSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Add Tag")
                .font(.subheadline)
                .fontWeight(.medium)

            HStack {
                TextField("Type tag and press Enter...", text: $newTagText)
                    .textFieldStyle(.roundedBorder)
                    .focused($isTagInputFocused)
                    .onSubmit {
                        submitSelectedTag()
                    }
                    .onKeyPress(.escape) {
                        if showAllSuggestions {
                            showAllSuggestions = false
                            return .handled
                        }
                        isTagInputFocused = false
                        return .handled
                    }
                    .onKeyPress(.downArrow) {
                        if shouldShowSuggestions && totalDropdownItems > 0 {
                            selectedSuggestionIndex = min(selectedSuggestionIndex + 1, totalDropdownItems - 1)
                            return .handled
                        }
                        return .ignored
                    }
                    .onKeyPress(.upArrow) {
                        if shouldShowSuggestions && totalDropdownItems > 0 {
                            selectedSuggestionIndex = max(selectedSuggestionIndex - 1, 0)
                            return .handled
                        }
                        return .ignored
                    }
                    .onKeyPress(characters: .init(charactersIn: " "), phases: .down) { keyPress in
                        // Control+Space to show all suggestions
                        if keyPress.modifiers.contains(.control) {
                            showAllSuggestions = true
                            selectedSuggestionIndex = 0
                            return .handled
                        }
                        return .ignored
                    }
                    .onChange(of: newTagText) { _, _ in
                        // Reset selection when text changes
                        selectedSuggestionIndex = 0
                    }

                Button {
                    guard !newTagText.isEmpty else { return }
                    Task {
                        await appState.addTag(newTagText)
                        newTagText = ""
                        showAllSuggestions = false
                    }
                } label: {
                    Image(systemName: "plus.circle.fill")
                }
                .buttonStyle(.plain)
                .disabled(newTagText.isEmpty)
            }

            // Auto-suggest dropdown
            if shouldShowSuggestions && totalDropdownItems > 0 {
                VStack(alignment: .leading, spacing: 2) {
                    // "Create new tag" option
                    if showCreateNewOption {
                        let isSelected = selectedSuggestionIndex == 0
                        HStack {
                            Image(systemName: "plus.circle")
                                .font(.caption)
                                .foregroundColor(.accentColor)
                            Text("Create \"\(newTagText.trimmingCharacters(in: .whitespaces))\"")
                                .font(.caption)
                            Spacer()
                            if isSelected {
                                Text("⏎")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(isSelected ? Color.accentColor.opacity(0.2) : Color.secondary.opacity(0.1))
                        .cornerRadius(4)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            Task {
                                await appState.addTag(newTagText)
                                newTagText = ""
                                showAllSuggestions = false
                            }
                        }
                    }

                    // Existing tag suggestions
                    ForEach(Array(filteredSuggestions.enumerated()), id: \.element) { index, suggestion in
                        let adjustedIndex = index + (showCreateNewOption ? 1 : 0)
                        let isSelected = adjustedIndex == selectedSuggestionIndex
                        HStack {
                            Text(suggestion)
                                .font(.caption)
                            Spacer()
                            if isSelected {
                                Text("⏎")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(isSelected ? Color.accentColor.opacity(0.2) : Color.secondary.opacity(0.1))
                        .cornerRadius(4)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            Task {
                                await appState.addTag(suggestion)
                                newTagText = ""
                                showAllSuggestions = false
                            }
                        }
                    }
                }
            }

            Text("T to focus • Ctrl+Space for suggestions • ↑↓ to navigate")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
    }

}

struct TagChip: View {
    let tag: String
    let style: TagChipStyle
    var shortcutIndex: Int? = nil
    var confidence: Int? = nil
    var onAction: (() -> Void)? = nil

    enum TagChipStyle {
        case applied
        case suggestion
        case partial  // Tag exists on some but not all selected photos
        case recommended  // Existing tag recommended based on Vision analysis
    }

    var body: some View {
        HStack(spacing: 4) {
            if let index = shortcutIndex {
                Text("\(index)")
                    .font(.caption2)
                    .fontWeight(.bold)
                    .foregroundColor(.secondary)
            }

            if style == .partial {
                Image(systemName: "plus.circle")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }

            Text(tag)
                .font(.caption)

            if let confidence = confidence {
                Text("\(confidence)%")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }

            if style == .applied {
                Button {
                    onAction?()
                } label: {
                    Image(systemName: "xmark")
                        .font(.caption2)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(backgroundColor)
        .foregroundColor(foregroundColor)
        .clipShape(Capsule())
        .contentShape(Capsule())
        .onTapGesture {
            if style == .suggestion || style == .partial {
                onAction?()
            }
        }
    }

    private var backgroundColor: Color {
        switch style {
        case .applied:
            return Color.accentColor.opacity(0.2)
        case .suggestion:
            return Color.secondary.opacity(0.15)
        case .partial:
            return Color.orange.opacity(0.15)
        case .recommended:
            return Color.green.opacity(0.2)
        }
    }

    private var foregroundColor: Color {
        switch style {
        case .applied:
            return .primary
        case .suggestion, .recommended:
            return .primary
        case .partial:
            return .primary
        }
    }
}

struct AlbumChip: View {
    let album: Album
    var style: AlbumChipStyle = .normal
    var onRemove: (() -> Void)? = nil

    enum AlbumChipStyle {
        case normal
        case partial
    }

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: album.icon)
                .font(.caption2)

            Text(album.title)
                .font(.caption)
                .lineLimit(1)

            if style == .normal, onRemove != nil {
                Button {
                    onRemove?()
                } label: {
                    Image(systemName: "xmark")
                        .font(.caption2)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(backgroundColor)
        .foregroundColor(.primary)
        .clipShape(Capsule())
    }

    private var backgroundColor: Color {
        switch style {
        case .normal:
            return Color.blue.opacity(0.15)
        case .partial:
            return Color.orange.opacity(0.15)
        }
    }
}

struct PersonChip: View {
    let person: PersonInfo
    var style: PersonChipStyle = .normal

    enum PersonChipStyle {
        case normal
        case partial
    }

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "person.fill")
                .font(.caption2)

            Text(person.name)
                .font(.caption)
                .lineLimit(1)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(backgroundColor)
        .foregroundColor(.primary)
        .clipShape(Capsule())
    }

    private var backgroundColor: Color {
        switch style {
        case .normal:
            return Color.green.opacity(0.15)
        case .partial:
            return Color.orange.opacity(0.15)
        }
    }
}

struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = FlowResult(in: proposal.width ?? 0, subviews: subviews, spacing: spacing)
        return result.size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = FlowResult(in: bounds.width, subviews: subviews, spacing: spacing)

        for (index, subview) in subviews.enumerated() {
            let position = result.positions[index]
            subview.place(
                at: CGPoint(x: bounds.minX + position.x, y: bounds.minY + position.y),
                proposal: .unspecified
            )
        }
    }

    struct FlowResult {
        var size: CGSize = .zero
        var positions: [CGPoint] = []

        init(in maxWidth: CGFloat, subviews: Subviews, spacing: CGFloat) {
            var currentX: CGFloat = 0
            var currentY: CGFloat = 0
            var lineHeight: CGFloat = 0

            for subview in subviews {
                let size = subview.sizeThatFits(.unspecified)

                if currentX + size.width > maxWidth && currentX > 0 {
                    currentX = 0
                    currentY += lineHeight + spacing
                    lineHeight = 0
                }

                positions.append(CGPoint(x: currentX, y: currentY))
                lineHeight = max(lineHeight, size.height)
                currentX += size.width + spacing

                self.size.width = max(self.size.width, currentX)
            }

            self.size.height = currentY + lineHeight
        }
    }
}

struct PhotoPreviewView: View {
    let photo: PhotoAsset
    @EnvironmentObject var appState: AppState
    @State private var previewImage: NSImage?

    var body: some View {
        VStack {
            if let image = previewImage {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(maxWidth: .infinity)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            } else {
                Rectangle()
                    .fill(Color.gray.opacity(0.2))
                    .aspectRatio(photo.aspectRatio, contentMode: .fit)
                    .frame(maxWidth: .infinity)
                    .overlay {
                        ProgressView()
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            }
        }
        .task(id: photo.id) {
            await loadPreviewImage()
        }
    }

    private func loadPreviewImage() async {
        // Load a larger image for preview
        previewImage = try? await appState.photoLibraryService.loadFullImage(for: photo.phAsset, maxDimension: 800)
    }
}

#Preview {
    TagPanelView()
        .environmentObject(AppState())
        .frame(width: 280)
}
