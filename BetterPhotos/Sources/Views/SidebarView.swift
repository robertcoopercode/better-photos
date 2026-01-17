import SwiftUI
import Photos

struct SidebarView: View {
    @EnvironmentObject var appState: AppState
    @State private var editingAlbumId: String?
    @State private var editingTagId: String?

    var body: some View {
        List {
            allPhotosRow
            withoutFacesRow
            albumsSection
            tagsSection
        }
        .listStyle(.sidebar)
        .navigationTitle("BetterPhotos")
    }

    private var allPhotosRow: some View {
        SidebarRow(
            title: "All Photos",
            icon: "photo.on.rectangle",
            count: appState.totalPhotoCount,
            isSelected: appState.selectedAlbum == nil && appState.selectedKeyword == nil && !appState.showPhotosWithoutFaces
        ) {
            Task {
                await appState.selectAlbum(id: nil)
            }
        }
    }

    private var withoutFacesRow: some View {
        SidebarRow(
            title: "Without Faces",
            icon: "person.crop.rectangle.badge.questionmark",
            count: appState.photosWithoutFacesCount,
            isSelected: appState.showPhotosWithoutFaces
        ) {
            Task {
                await appState.selectPhotosWithoutFaces()
            }
        }
    }

    @ViewBuilder
    private var albumsSection: some View {
        if !appState.albumItems.isEmpty {
            Section("Albums") {
                ForEach(Array(appState.albumItems.enumerated()), id: \.element.id) { index, item in
                    SidebarItemRow(
                        item: item,
                        editingAlbumId: $editingAlbumId,
                        editingTagId: $editingTagId
                    )
                    .environmentObject(appState)
                }
            }
        }
    }

    @ViewBuilder
    private var tagsSection: some View {
        if !appState.keywordsWithCounts.isEmpty {
            Section("Tags") {
                ForEach(Array(appState.keywordsWithCounts.enumerated()), id: \.element.id) { index, tag in
                    tagRow(for: tag, at: index)
                }
            }
        }
    }

    private func tagRow(for tag: KeywordWithCount, at index: Int) -> some View {
        SelectableTagRow(
            tag: tag,
            index: index,
            isSelected: appState.selectedKeywordIds.contains(tag.keyword),
            isEditing: editingTagId == tag.id,
            onTap: { modifiers in
                if modifiers.contains(.command) || modifiers.contains(.shift) {
                    appState.selectKeywordWithModifiers(tag.keyword, index: index, modifiers: modifiers)
                } else {
                    Task {
                        await appState.selectKeyword(tag.keyword)
                    }
                }
            },
            onDoubleClick: {
                editingTagId = tag.id
                editingAlbumId = nil
            },
            onRename: { newName in
                let oldName = tag.keyword
                editingTagId = nil
                Task {
                    await appState.renameKeyword(from: oldName, to: newName)
                }
            },
            onCancel: {
                editingTagId = nil
            }
        )
        .contextMenu {
            if appState.selectedKeywordIds.count > 1 && appState.selectedKeywordIds.contains(tag.keyword) {
                // Multi-select context menu
                Button(role: .destructive) {
                    Task {
                        await appState.deleteSelectedKeywords()
                    }
                } label: {
                    Label("Delete \(appState.selectedKeywordIds.count) Tags", systemImage: "trash")
                }
            } else {
                // Single item context menu
                Button {
                    editingTagId = tag.id
                    editingAlbumId = nil
                } label: {
                    Label("Rename", systemImage: "pencil")
                }

                Divider()

                Button(role: .destructive) {
                    Task {
                        await appState.deleteKeyword(tag.keyword)
                    }
                } label: {
                    Label("Delete Tag", systemImage: "trash")
                }
            }
        }
    }
}

// MARK: - Hierarchical Sidebar Item View

struct SidebarItemRow: View {
    let item: SidebarItem
    @Binding var editingAlbumId: String?
    @Binding var editingTagId: String?
    @EnvironmentObject var appState: AppState

    var body: some View {
        switch item {
        case .album(let album):
            albumRow(for: album)
        case .folder(let folder):
            folderRow(for: folder)
        }
    }

    @ViewBuilder
    private func albumRow(for album: Album) -> some View {
        EditableSidebarRow(
            title: album.title,
            icon: album.icon,
            count: album.count,
            isSelected: appState.selectedAlbum?.id == album.id,
            isEditing: editingAlbumId == album.id,
            onTap: {
                Task {
                    await appState.selectAlbum(id: album.id)
                }
            },
            onDoubleClick: {
                editingAlbumId = album.id
                editingTagId = nil
            },
            onRename: { newName in
                editingAlbumId = nil
                Task {
                    await appState.renameAlbum(album, to: newName)
                }
            },
            onCancel: {
                editingAlbumId = nil
            }
        )
        .contextMenu {
            Button {
                editingAlbumId = album.id
                editingTagId = nil
            } label: {
                Label("Rename", systemImage: "pencil")
            }

            Divider()

            Button(role: .destructive) {
                Task {
                    await appState.deleteAlbum(album)
                }
            } label: {
                Label("Delete Album", systemImage: "trash")
            }
        }
    }

    @ViewBuilder
    private func folderRow(for folder: Folder) -> some View {
        DisclosureGroup(
            isExpanded: Binding(
                get: { appState.expandedFolderIds.contains(folder.id) },
                set: { _ in appState.toggleFolderExpanded(folder.id) }
            )
        ) {
            ForEach(folder.children) { child in
                SidebarItemRow(
                    item: child,
                    editingAlbumId: $editingAlbumId,
                    editingTagId: $editingTagId
                )
                .environmentObject(appState)
            }
        } label: {
            Label {
                HStack {
                    Text(folder.title)
                    Spacer()
                    Text("\(folder.totalCount)")
                        .foregroundColor(.secondary)
                        .font(.caption)
                }
            } icon: {
                Image(systemName: "folder")
            }
        }
    }
}

struct SidebarRow: View {
    let title: String
    let icon: String
    let count: Int
    let isSelected: Bool
    let onTap: () -> Void

    var body: some View {
        Label {
            HStack {
                Text(title)
                Spacer()
                Text("\(count)")
                    .foregroundColor(.secondary)
                    .font(.caption)
            }
        } icon: {
            Image(systemName: icon)
        }
        .contentShape(Rectangle())
        .onTapGesture {
            onTap()
        }
        .listRowBackground(
            isSelected ? Color.accentColor.opacity(0.2) : Color.clear
        )
    }
}

struct EditableSidebarRow: View {
    let title: String
    let icon: String
    let count: Int
    let isSelected: Bool
    let isEditing: Bool
    let onTap: () -> Void
    let onDoubleClick: () -> Void
    let onRename: (String) -> Void
    let onCancel: () -> Void

    @State private var editText: String = ""
    @FocusState private var isFocused: Bool

    var body: some View {
        Label {
            HStack {
                if isEditing {
                    TextField("", text: $editText)
                        .textFieldStyle(.plain)
                        .focused($isFocused)
                        .onSubmit {
                            let trimmed = editText.trimmingCharacters(in: .whitespaces)
                            if !trimmed.isEmpty && trimmed != title {
                                onRename(trimmed)
                            } else {
                                onCancel()
                            }
                        }
                        .onExitCommand {
                            onCancel()
                        }
                        .onAppear {
                            editText = title
                            isFocused = true
                        }
                } else {
                    Text(title)
                    Spacer()
                    Text("\(count)")
                        .foregroundColor(.secondary)
                        .font(.caption)
                }
            }
        } icon: {
            Image(systemName: icon)
        }
        .contentShape(Rectangle())
        .onTapGesture(count: 2) {
            onDoubleClick()
        }
        .onTapGesture(count: 1) {
            onTap()
        }
        .listRowBackground(
            isSelected ? Color.accentColor.opacity(0.2) : Color.clear
        )
    }
}

struct SelectableTagRow: View {
    let tag: KeywordWithCount
    let index: Int
    let isSelected: Bool
    let isEditing: Bool
    let onTap: (EventModifiers) -> Void
    let onDoubleClick: () -> Void
    let onRename: (String) -> Void
    let onCancel: () -> Void

    @State private var editText: String = ""
    @FocusState private var isFocused: Bool

    var body: some View {
        Label {
            HStack {
                if isEditing {
                    TextField("", text: $editText)
                        .textFieldStyle(.plain)
                        .focused($isFocused)
                        .onSubmit {
                            let trimmed = editText.trimmingCharacters(in: .whitespaces)
                            if !trimmed.isEmpty && trimmed != tag.keyword {
                                onRename(trimmed)
                            } else {
                                onCancel()
                            }
                        }
                        .onExitCommand {
                            onCancel()
                        }
                        .onAppear {
                            editText = tag.keyword
                            isFocused = true
                        }
                } else {
                    Text(tag.keyword)
                    Spacer()
                    Text("\(tag.count)")
                        .foregroundColor(.secondary)
                        .font(.caption)
                }
            }
        } icon: {
            Image(systemName: "tag")
        }
        .contentShape(Rectangle())
        .overlay {
            if !isEditing {
                TagClickDetector { modifiers, clickCount in
                    if clickCount == 2 {
                        onDoubleClick()
                    } else {
                        onTap(modifiers)
                    }
                }
            }
        }
        .listRowBackground(
            isSelected ? Color.accentColor.opacity(0.2) : Color.clear
        )
    }
}

struct TagClickDetector: NSViewRepresentable {
    let onClick: (EventModifiers, Int) -> Void

    func makeNSView(context: Context) -> TagClickNSView {
        let view = TagClickNSView()
        view.onClick = onClick
        return view
    }

    func updateNSView(_ nsView: TagClickNSView, context: Context) {
        nsView.onClick = onClick
    }
}

class TagClickNSView: NSView {
    var onClick: ((EventModifiers, Int) -> Void)?

    override var acceptsFirstResponder: Bool { true }

    override func mouseDown(with event: NSEvent) {
        var modifiers: EventModifiers = []
        if event.modifierFlags.contains(.command) {
            modifiers.insert(.command)
        }
        if event.modifierFlags.contains(.shift) {
            modifiers.insert(.shift)
        }
        onClick?(modifiers, event.clickCount)
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        return true
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        // Make sure this view receives clicks
        return frame.contains(point) ? self : nil
    }
}

#Preview {
    SidebarView()
        .environmentObject(AppState())
        .frame(width: 200)
}
