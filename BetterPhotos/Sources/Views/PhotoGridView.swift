import SwiftUI
import Photos

struct PhotoGridView: View {
    @EnvironmentObject var appState: AppState

    private let columns = [
        GridItem(.adaptive(minimum: 120, maximum: 150), spacing: 4)
    ]

    private let thumbnailSize = CGSize(width: 200, height: 200)
    private let itemMinWidth: CGFloat = 120
    private let itemSpacing: CGFloat = 4

    var body: some View {
        VStack(spacing: 0) {
            if appState.isLoadingPhotos {
                loadingView
            } else if appState.photos.isEmpty {
                emptyView
            } else {
                gridContent
            }

            statusBar
        }
        .background(KeyboardHandler(appState: appState))
    }

    private var loadingView: some View {
        VStack(spacing: 16) {
            ProgressView()
            Text("Loading photos...")
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyView: some View {
        VStack(spacing: 16) {
            Image(systemName: "photo.on.rectangle.angled")
                .font(.system(size: 48))
                .foregroundColor(.secondary)
            Text("No Photos")
                .font(.title2)
            Text("Your photo library appears to be empty")
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var gridContent: some View {
        GeometryReader { geometry in
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVGrid(columns: columns, spacing: 4) {
                        ForEach(Array(appState.photos.enumerated()), id: \.element.id) { index, photo in
                            ClickablePhotoThumbnail(
                                photo: photo,
                                index: index,
                                isSelected: appState.selectedPhotoIds.contains(photo.id),
                                isFocused: appState.focusedPhotoId == photo.id,
                                thumbnailSize: thumbnailSize
                            )
                            .id(photo.id)
                        }
                    }
                    .padding(8)
                }
                .onChange(of: appState.focusedPhotoId) { _, newId in
                    if let id = newId {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            proxy.scrollTo(id, anchor: .center)
                        }
                    }
                }
            }
            .onChange(of: geometry.size.width, initial: true) { _, newWidth in
                let availableWidth = newWidth - 16 // Account for padding
                let columnCount = max(1, Int(availableWidth / (itemMinWidth + itemSpacing)))
                appState.gridColumnCount = columnCount
            }
        }
    }

    private var statusBar: some View {
        HStack {
            Text(statusText)
                .font(.caption)
                .foregroundColor(.secondary)

            Spacer()

            if !appState.selectedPhotoIds.isEmpty {
                Text("Press T to tag")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(.bar)
    }

    private var statusText: String {
        let total = appState.photos.count
        let selected = appState.selectedPhotoIds.count

        if selected == 0 {
            return "\(total) items"
        } else if selected == 1 {
            return "1 of \(total) selected"
        } else {
            return "\(selected) of \(total) selected"
        }
    }
}

struct PhotoThumbnailView: View {
    let photo: PhotoAsset
    let isSelected: Bool
    let isFocused: Bool
    let thumbnailSize: CGSize

    @State private var thumbnail: NSImage?
    @EnvironmentObject var appState: AppState

    var body: some View {
        ZStack {
            if let thumbnail = thumbnail {
                Image(nsImage: thumbnail)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                Rectangle()
                    .fill(Color.gray.opacity(0.2))
                    .overlay {
                        ProgressView()
                            .scaleEffect(0.5)
                    }
            }
        }
        .frame(width: thumbnailSize.width * 0.6, height: thumbnailSize.height * 0.6)
        .clipped()
        .clipShape(RoundedRectangle(cornerRadius: 4))
        .contentShape(RoundedRectangle(cornerRadius: 4))
        .overlay {
            RoundedRectangle(cornerRadius: 4)
                .stroke(borderColor, lineWidth: borderWidth)
        }
        .overlay(alignment: .bottomLeading) {
            // Video indicator
            if photo.isVideo {
                HStack(spacing: 3) {
                    Image(systemName: "play.fill")
                        .font(.system(size: 8))
                    Text(photo.formattedDuration)
                        .font(.system(size: 9, weight: .medium))
                }
                .foregroundColor(.white)
                .padding(.horizontal, 5)
                .padding(.vertical, 2)
                .background(
                    Capsule()
                        .fill(.black.opacity(0.6))
                )
                .padding(4)
            }
        }
        .shadow(color: shadowColor, radius: isFocused ? 4 : 0)
        .task {
            await loadThumbnail()
        }
    }

    private var borderColor: Color {
        if isSelected {
            return .accentColor
        } else if isFocused {
            return .accentColor.opacity(0.5)
        }
        return .clear
    }

    private var borderWidth: CGFloat {
        if isSelected { return 3 }
        if isFocused { return 2 }
        return 0
    }

    private var shadowColor: Color {
        isFocused ? .accentColor.opacity(0.3) : .clear
    }

    private func loadThumbnail() async {
        thumbnail = await appState.thumbnailCache.thumbnail(for: photo.phAsset, size: thumbnailSize)
    }
}

struct ClickablePhotoThumbnail: View {
    let photo: PhotoAsset
    let index: Int
    let isSelected: Bool
    let isFocused: Bool
    let thumbnailSize: CGSize

    @EnvironmentObject var appState: AppState

    var body: some View {
        PhotoThumbnailView(
            photo: photo,
            isSelected: isSelected,
            isFocused: isFocused,
            thumbnailSize: thumbnailSize
        )
        .overlay {
            ClickDetector { modifiers in
                let eventModifiers = convertModifiers(modifiers)
                appState.selectPhoto(id: photo.id, index: index, modifiers: eventModifiers)
            }
        }
    }

    private func convertModifiers(_ flags: NSEvent.ModifierFlags) -> EventModifiers {
        var modifiers: EventModifiers = []
        if flags.contains(.command) {
            modifiers.insert(.command)
        }
        if flags.contains(.shift) {
            modifiers.insert(.shift)
        }
        return modifiers
    }
}

struct ClickDetector: NSViewRepresentable {
    let onClick: (NSEvent.ModifierFlags) -> Void

    func makeNSView(context: Context) -> ClickDetectorNSView {
        let view = ClickDetectorNSView()
        view.onClick = onClick
        return view
    }

    func updateNSView(_ nsView: ClickDetectorNSView, context: Context) {
        nsView.onClick = onClick
    }
}

class ClickDetectorNSView: NSView {
    var onClick: ((NSEvent.ModifierFlags) -> Void)?

    override var acceptsFirstResponder: Bool { true }

    override func mouseDown(with event: NSEvent) {
        onClick?(event.modifierFlags)
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        return true
    }
}

struct KeyboardHandler: NSViewRepresentable {
    let appState: AppState

    func makeNSView(context: Context) -> KeyboardNSView {
        let view = KeyboardNSView()
        view.appState = appState
        return view
    }

    func updateNSView(_ nsView: KeyboardNSView, context: Context) {
        nsView.appState = appState
    }
}

class KeyboardNSView: NSView {
    var appState: AppState?
    private var keyDownMonitor: Any?
    private var keyUpMonitor: Any?

    override var acceptsFirstResponder: Bool { true }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()

        if window != nil {
            // Add local event monitor for key down events
            keyDownMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                if self?.handleKeyDownEvent(event) == true {
                    return nil // Consume the event
                }
                return event // Pass through
            }

            // Add local event monitor for key up events (for Quick Preview)
            keyUpMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyUp) { [weak self] event in
                if self?.handleKeyUpEvent(event) == true {
                    return nil // Consume the event
                }
                return event // Pass through
            }
        } else {
            if let monitor = keyDownMonitor {
                NSEvent.removeMonitor(monitor)
                self.keyDownMonitor = nil
            }
            if let monitor = keyUpMonitor {
                NSEvent.removeMonitor(monitor)
                self.keyUpMonitor = nil
            }
        }
    }

    deinit {
        if let monitor = keyDownMonitor {
            NSEvent.removeMonitor(monitor)
        }
        if let monitor = keyUpMonitor {
            NSEvent.removeMonitor(monitor)
        }
    }

    private func handleKeyDownEvent(_ event: NSEvent) -> Bool {
        guard let appState = appState else { return false }

        let shiftPressed = event.modifierFlags.contains(.shift)
        let commandPressed = event.modifierFlags.contains(.command)
        let isInTextField = isTextFieldFocused()

        // Handle Command+Delete for photo deletion (works even in text fields)
        if commandPressed && (event.keyCode == 51 || event.keyCode == 117) {
            // keyCode 51 = backspace/delete, keyCode 117 = forward delete
            Task { @MainActor in
                await appState.deleteSelectedPhotos()
            }
            return true
        }

        // Handle Space for Quick Preview (only if not in text field and photo selected)
        if event.keyCode == 49 && !isInTextField {
            // keyCode 49 = space
            // If preview is already showing, consume repeat events to prevent system sound
            if appState.showQuickPreview {
                return true
            }
            // Only open on initial press, not repeat
            if !event.isARepeat && appState.selectedPhoto != nil {
                Task { @MainActor in
                    appState.showQuickPreview = true
                }
                return true
            }
        }

        // Handle Cmd+A for select all (only if not in text field)
        if commandPressed && event.keyCode == 0 { // keyCode 0 = 'a'
            if isInTextField {
                // Let the text field handle Cmd+A for select all text
                return false
            }
            Task { @MainActor in
                appState.selectAll()
            }
            return true
        }

        // If in text field, only capture Shift+Arrow (for multi-select)
        // Let regular arrows through for cursor movement
        if isInTextField && !shiftPressed {
            return false
        }

        switch event.keyCode {
        case 123: // Left arrow
            Task { @MainActor in
                appState.navigateSelection(direction: .left, extendSelection: shiftPressed)
            }
            return true
        case 124: // Right arrow
            Task { @MainActor in
                appState.navigateSelection(direction: .right, extendSelection: shiftPressed)
            }
            return true
        case 125: // Down arrow
            Task { @MainActor in
                appState.navigateSelection(direction: .down, extendSelection: shiftPressed)
            }
            return true
        case 126: // Up arrow
            Task { @MainActor in
                appState.navigateSelection(direction: .up, extendSelection: shiftPressed)
            }
            return true
        case 53: // Escape
            // Don't handle escape if in text field (let the field handle it)
            if isInTextField {
                return false
            }
            Task { @MainActor in
                appState.clearSelection()
            }
            return true
        default:
            return false
        }
    }

    private func handleKeyUpEvent(_ event: NSEvent) -> Bool {
        guard let appState = appState else { return false }

        // Handle Space release to close Quick Preview
        if event.keyCode == 49 { // keyCode 49 = space
            if appState.showQuickPreview {
                Task { @MainActor in
                    appState.showQuickPreview = false
                }
                return true
            }
        }

        return false
    }

    private func isTextFieldFocused() -> Bool {
        guard let responder = window?.firstResponder else { return false }
        return responder is NSTextView || responder is NSTextField
    }

    override func keyDown(with event: NSEvent) {
        if !handleKeyDownEvent(event) {
            super.keyDown(with: event)
        }
    }
}

#Preview {
    PhotoGridView()
        .environmentObject(AppState())
}
