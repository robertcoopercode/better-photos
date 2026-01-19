import SwiftUI
import AVKit
import Photos

struct ContentView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        Group {
            if appState.photoLibraryAuthorized {
                MainLayout()
            } else {
                AuthorizationView()
            }
        }
        .task {
            await appState.requestAuthorization()
        }
        .alert("Error", isPresented: $appState.showError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(appState.errorMessage ?? "An unknown error occurred")
        }
    }
}

struct AuthorizationView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "photo.on.rectangle.angled")
                .font(.system(size: 64))
                .foregroundColor(.secondary)

            Text("Photo Library Access Required")
                .font(.title2)
                .fontWeight(.semibold)

            Text("BetterPhotos needs access to your photo library to display and tag photos.")
                .multilineTextAlignment(.center)
                .foregroundColor(.secondary)
                .frame(maxWidth: 400)

            Button("Grant Access") {
                Task {
                    await appState.requestAuthorization()
                }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)

            Text("You can change this later in System Settings > Privacy & Security > Photos")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding(40)
    }
}

struct MainLayout: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        ThreeColumnSplitView(
            sidebar: { SidebarView() },
            content: { PhotoGridView() },
            detail: { TagPanelView() },
            sidebarMinWidth: 150,
            sidebarMaxWidth: 280,
            detailMinWidth: 280,
            detailMaxWidth: 400
        )
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                PhotosStatusIndicator()
                SyncStatusIndicator()
                RefreshButton()
            }
        }
        .overlay {
            if appState.showQuickPreview, let photo = appState.selectedPhoto {
                QuickPreviewOverlay(photo: photo)
            }
        }
    }
}

/// Native AppKit NSSplitView wrapper for smooth resizing
struct ThreeColumnSplitView<Sidebar: View, Content: View, Detail: View>: NSViewRepresentable {
    let sidebar: () -> Sidebar
    let content: () -> Content
    let detail: () -> Detail
    let sidebarMinWidth: CGFloat
    let sidebarMaxWidth: CGFloat
    let detailMinWidth: CGFloat
    let detailMaxWidth: CGFloat

    func makeNSView(context: Context) -> NSSplitView {
        let splitView = NSSplitView()
        splitView.isVertical = true
        splitView.dividerStyle = .thin
        splitView.delegate = context.coordinator

        // Create hosting views for each SwiftUI view
        let sidebarHost = NSHostingView(rootView: sidebar())
        let contentHost = NSHostingView(rootView: content())
        let detailHost = NSHostingView(rootView: detail())

        // Set holding priorities to control which views resize
        sidebarHost.setContentHuggingPriority(.defaultHigh, for: .horizontal)
        detailHost.setContentHuggingPriority(.defaultHigh, for: .horizontal)
        contentHost.setContentHuggingPriority(.defaultLow, for: .horizontal)

        splitView.addArrangedSubview(sidebarHost)
        splitView.addArrangedSubview(contentHost)
        splitView.addArrangedSubview(detailHost)

        // Set holding priorities on split view items
        splitView.setHoldingPriority(.defaultHigh, forSubviewAt: 0)
        splitView.setHoldingPriority(.defaultLow, forSubviewAt: 1)
        splitView.setHoldingPriority(.defaultHigh, forSubviewAt: 2)

        // Set minimum widths on subviews
        sidebarHost.widthAnchor.constraint(greaterThanOrEqualToConstant: sidebarMinWidth).isActive = true
        detailHost.widthAnchor.constraint(greaterThanOrEqualToConstant: detailMinWidth).isActive = true

        // Set initial positions after a brief delay to ensure proper layout
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            if splitView.bounds.width > 100 {
                splitView.setPosition(180, ofDividerAt: 0)
                splitView.setPosition(splitView.bounds.width - 320, ofDividerAt: 1)
            }
        }

        return splitView
    }

    func updateNSView(_ nsView: NSSplitView, context: Context) {
        // Set initial positions after layout (only once)
        if !context.coordinator.hasSetInitialPositions && nsView.bounds.width > 100 {
            context.coordinator.hasSetInitialPositions = true
            let totalWidth = nsView.bounds.width
            nsView.setPosition(180, ofDividerAt: 0)
            nsView.setPosition(totalWidth - 320, ofDividerAt: 1)
        }

        // Update SwiftUI content
        if let sidebarHost = nsView.arrangedSubviews.first as? NSHostingView<Sidebar> {
            sidebarHost.rootView = sidebar()
        }
        if nsView.arrangedSubviews.count > 1,
           let contentHost = nsView.arrangedSubviews[1] as? NSHostingView<Content> {
            contentHost.rootView = content()
        }
        if nsView.arrangedSubviews.count > 2,
           let detailHost = nsView.arrangedSubviews[2] as? NSHostingView<Detail> {
            detailHost.rootView = detail()
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(
            sidebarMinWidth: sidebarMinWidth,
            sidebarMaxWidth: sidebarMaxWidth,
            detailMinWidth: detailMinWidth,
            detailMaxWidth: detailMaxWidth
        )
    }

    class Coordinator: NSObject, NSSplitViewDelegate {
        let sidebarMinWidth: CGFloat
        let sidebarMaxWidth: CGFloat
        let detailMinWidth: CGFloat
        let detailMaxWidth: CGFloat
        var hasSetInitialPositions = false

        init(sidebarMinWidth: CGFloat, sidebarMaxWidth: CGFloat,
             detailMinWidth: CGFloat, detailMaxWidth: CGFloat) {
            self.sidebarMinWidth = sidebarMinWidth
            self.sidebarMaxWidth = sidebarMaxWidth
            self.detailMinWidth = detailMinWidth
            self.detailMaxWidth = detailMaxWidth
        }

        func splitView(_ splitView: NSSplitView, constrainMinCoordinate proposedMinimumPosition: CGFloat, ofSubviewAt dividerIndex: Int) -> CGFloat {
            if dividerIndex == 0 {
                return sidebarMinWidth
            } else {
                // Second divider: ensure detail panel doesn't exceed max
                let sidebarWidth = splitView.arrangedSubviews[0].frame.width
                return sidebarWidth + 400 // minimum content width
            }
        }

        func splitView(_ splitView: NSSplitView, constrainMaxCoordinate proposedMaximumPosition: CGFloat, ofSubviewAt dividerIndex: Int) -> CGFloat {
            if dividerIndex == 0 {
                return sidebarMaxWidth
            } else {
                // Second divider: ensure detail panel doesn't go below min
                return splitView.bounds.width - detailMinWidth
            }
        }

        func splitView(_ splitView: NSSplitView, canCollapseSubview subview: NSView) -> Bool {
            return false
        }

        func splitView(_ splitView: NSSplitView, shouldAdjustSizeOfSubview view: NSView) -> Bool {
            // Only let the middle content view resize when window resizes
            if let index = splitView.arrangedSubviews.firstIndex(of: view) {
                return index == 1
            }
            return false
        }

        func splitViewDidResizeSubviews(_ notification: Notification) {
            guard let splitView = notification.object as? NSSplitView else { return }

            // Enforce detail max width
            if splitView.arrangedSubviews.count > 2 {
                let detailWidth = splitView.arrangedSubviews[2].frame.width
                if detailWidth > detailMaxWidth {
                    let newPosition = splitView.bounds.width - detailMaxWidth
                    splitView.setPosition(newPosition, ofDividerAt: 1)
                }
            }
        }
    }
}

struct QuickPreviewOverlay: View {
    let photo: PhotoAsset
    @EnvironmentObject var appState: AppState
    @State private var previewImage: NSImage?
    @StateObject private var videoPlayerManager = VideoPlayerManager()

    var body: some View {
        ZStack {
            // Semi-transparent background
            Color.black.opacity(0.85)
                .ignoresSafeArea()

            // Preview content
            VStack(spacing: 16) {
                if photo.isVideo {
                    // Video preview
                    videoPreviewContent
                } else {
                    // Photo preview
                    photoPreviewContent
                }

                // Info section
                infoSection
            }
            .padding(40)
        }
        .task(id: photo.id) {
            if photo.isVideo {
                await loadVideo()
            } else {
                await loadPreviewImage()
            }
        }
        .onDisappear {
            videoPlayerManager.pause()
        }
    }

    @ViewBuilder
    private var photoPreviewContent: some View {
        if let image = previewImage {
            Image(nsImage: image)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .shadow(radius: 20)
        } else {
            ProgressView()
                .scaleEffect(1.5)
                .tint(.white)
        }
    }

    @ViewBuilder
    private var videoPreviewContent: some View {
        if videoPlayerManager.isLoading {
            VStack(spacing: 12) {
                ProgressView()
                    .scaleEffect(1.5)
                    .tint(.white)
                Text("Loading video...")
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.7))
            }
        } else if let player = videoPlayerManager.player {
            VStack(spacing: 12) {
                VideoPlayerView(player: player)
                    .aspectRatio(CGFloat(photo.pixelWidth) / CGFloat(photo.pixelHeight), contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .shadow(radius: 20)

                // Video controls
                HStack(spacing: 20) {
                    // Rewind 10s
                    Button {
                        videoPlayerManager.skip(by: -10)
                    } label: {
                        Image(systemName: "gobackward.10")
                            .font(.title2)
                            .foregroundColor(.white)
                    }
                    .buttonStyle(.plain)

                    // Play/Pause
                    Button {
                        videoPlayerManager.togglePlayPause()
                    } label: {
                        Image(systemName: videoPlayerManager.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                            .font(.system(size: 44))
                            .foregroundColor(.white)
                    }
                    .buttonStyle(.plain)

                    // Forward 10s
                    Button {
                        videoPlayerManager.skip(by: 10)
                    } label: {
                        Image(systemName: "goforward.10")
                            .font(.title2)
                            .foregroundColor(.white)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.top, 8)
            }
        } else {
            VStack(spacing: 12) {
                Image(systemName: "exclamationmark.triangle")
                    .font(.largeTitle)
                    .foregroundColor(.white.opacity(0.7))
                Text("Unable to load video")
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.7))
            }
        }
    }

    private var infoSection: some View {
        VStack(spacing: 4) {
            if let date = photo.creationDate {
                Text(date, style: .date)
                    .font(.headline)
                    .foregroundColor(.white)
            }

            if photo.isVideo {
                Text("\(photo.pixelWidth) × \(photo.pixelHeight) • \(photo.formattedDuration)")
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.7))
            } else {
                Text("\(photo.phAsset.pixelWidth) × \(photo.phAsset.pixelHeight)")
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.7))
            }

            Text("Release Space to close")
                .font(.caption2)
                .foregroundColor(.white.opacity(0.5))
                .padding(.top, 8)
        }
    }

    private func loadPreviewImage() async {
        previewImage = try? await appState.photoLibraryService.loadFullImage(for: photo.phAsset, maxDimension: 2048)
    }

    private func loadVideo() async {
        await videoPlayerManager.loadVideo(for: photo.phAsset)
    }
}

/// Manages video playback state
@MainActor
class VideoPlayerManager: ObservableObject {
    @Published var player: AVPlayer?
    @Published var isPlaying = false
    @Published var isLoading = true

    private var timeObserver: Any?

    func loadVideo(for asset: PHAsset) async {
        isLoading = true

        let options = PHVideoRequestOptions()
        options.isNetworkAccessAllowed = true
        options.deliveryMode = .highQualityFormat

        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            PHImageManager.default().requestAVAsset(forVideo: asset, options: options) { [weak self] avAsset, _, _ in
                Task { @MainActor in
                    guard let self = self else {
                        continuation.resume()
                        return
                    }

                    if let avAsset = avAsset {
                        let playerItem = AVPlayerItem(asset: avAsset)
                        self.player = AVPlayer(playerItem: playerItem)

                        // Observe when video ends to update isPlaying
                        NotificationCenter.default.addObserver(
                            forName: .AVPlayerItemDidPlayToEndTime,
                            object: playerItem,
                            queue: .main
                        ) { [weak self] _ in
                            Task { @MainActor in
                                self?.isPlaying = false
                            }
                        }
                    }

                    self.isLoading = false
                    continuation.resume()
                }
            }
        }
    }

    func togglePlayPause() {
        guard let player = player else { return }

        if isPlaying {
            player.pause()
            isPlaying = false
        } else {
            // If at end, restart from beginning
            if let currentItem = player.currentItem,
               currentItem.currentTime() >= currentItem.duration {
                player.seek(to: .zero)
            }
            player.play()
            isPlaying = true
        }
    }

    func pause() {
        player?.pause()
        isPlaying = false
    }

    func skip(by seconds: Double) {
        guard let player = player else { return }
        let currentTime = player.currentTime()
        let newTime = CMTimeAdd(currentTime, CMTimeMakeWithSeconds(seconds, preferredTimescale: 600))
        player.seek(to: newTime)
    }
}

/// NSViewRepresentable wrapper for AVPlayerView
struct VideoPlayerView: NSViewRepresentable {
    let player: AVPlayer

    func makeNSView(context: Context) -> AVPlayerView {
        let playerView = AVPlayerView()
        playerView.player = player
        playerView.controlsStyle = .none // We use our own controls
        playerView.showsFullScreenToggleButton = false
        return playerView
    }

    func updateNSView(_ nsView: AVPlayerView, context: Context) {
        nsView.player = player
    }
}

struct PhotosStatusIndicator: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        if !appState.isPhotosAppRunning {
            Button {
                appState.photosMonitor.launchPhotos()
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.orange)
                    Text("Photos Required")
                        .font(.caption)
                }
            }
            .help("Photos.app must be running to save tags. Click to launch.")
        }
    }
}

struct SyncStatusIndicator: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        if appState.isSyncing {
            HStack(spacing: 4) {
                ProgressView()
                    .scaleEffect(0.7)
                Text("Syncing...")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }
}

struct RefreshButton: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        Button {
            Task {
                await appState.resyncWithDatabase()
            }
        } label: {
            Image(systemName: "arrow.clockwise")
        }
        .disabled(appState.isLoadingPhotos)
        .help("Resync with Photos database (⌘R)")
    }
}

#Preview {
    ContentView()
        .environmentObject(AppState())
}
