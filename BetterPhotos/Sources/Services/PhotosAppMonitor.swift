import Foundation
import AppKit
import Combine

class PhotosAppMonitor: ObservableObject {
    @Published var isRunning = false

    private var timer: Timer?
    private let photosAppBundleId = "com.apple.Photos"

    init() {
        checkPhotosStatus()
        startMonitoring()
    }

    deinit {
        stopMonitoring()
    }

    func startMonitoring() {
        timer = Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { [weak self] _ in
            self?.checkPhotosStatus()
        }
    }

    func stopMonitoring() {
        timer?.invalidate()
        timer = nil
    }

    func checkPhotosStatus() {
        let runningApps = NSWorkspace.shared.runningApplications
        let newStatus = runningApps.contains { $0.bundleIdentifier == photosAppBundleId }

        if newStatus != isRunning {
            DispatchQueue.main.async {
                self.isRunning = newStatus
            }
        }
    }

    func launchPhotos() {
        guard let photosURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: photosAppBundleId) else {
            return
        }
        NSWorkspace.shared.openApplication(at: photosURL, configuration: NSWorkspace.OpenConfiguration())
    }

    func activatePhotos() {
        if let app = NSWorkspace.shared.runningApplications.first(where: {
            $0.bundleIdentifier == photosAppBundleId
        }) {
            app.activate(options: [])
        } else {
            launchPhotos()
        }
    }
}
