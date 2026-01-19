import SwiftUI

@main
struct BetterPhotosApp: App {
    @StateObject private var appState = AppState()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(appState)
                .frame(minWidth: 900, minHeight: 600)
        }
        .windowStyle(.automatic)
        .commands {
            PhotoCommands(appState: appState)
        }

        Settings {
            SettingsView()
                .environmentObject(appState)
        }
    }
}

struct PhotoCommands: Commands {
    @ObservedObject var appState: AppState

    var body: some Commands {
        CommandGroup(after: .newItem) {
            Button("Resync with Database") {
                Task {
                    await appState.resyncWithDatabase()
                }
            }
            .keyboardShortcut("r", modifiers: .command)
        }

        CommandMenu("Tags") {
            Button("Focus Tag Input") {
                appState.focusTagInput = true
            }
            .keyboardShortcut("t", modifiers: [])

            Button("Focus Album Input") {
                appState.focusAlbumInput = true
            }
            .keyboardShortcut("a", modifiers: [])

            Divider()

            Button("Accept All AI Suggestions") {
                appState.acceptAllSuggestions()
            }
        }

        CommandMenu("Selection") {
            Button("Select All Photos") {
                appState.selectAll()
            }
            // No keyboard shortcut here - handled in KeyboardNSView to allow Cmd+A in text fields

            Button("Clear Selection") {
                appState.clearSelection()
            }
            .keyboardShortcut(.escape, modifiers: [])

            Divider()

            Button("Send to Photos for Tagging") {
                Task {
                    await appState.sendSelectedPhotosToPhotosForTagging()
                }
            }
            .keyboardShortcut("t", modifiers: [.command, .shift])
            .disabled(appState.selectedPhotoIds.isEmpty)
        }
    }
}
