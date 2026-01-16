import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var appState: AppState
    @AppStorage("thumbnailSize") private var thumbnailSize: Double = 120
    @AppStorage("gridColumns") private var gridColumns: Int = 4

    var body: some View {
        TabView {
            GeneralSettingsView(thumbnailSize: $thumbnailSize, gridColumns: $gridColumns)
                .tabItem {
                    Label("General", systemImage: "gear")
                }

            KeyboardShortcutsView()
                .tabItem {
                    Label("Shortcuts", systemImage: "keyboard")
                }
        }
        .frame(width: 450, height: 300)
    }
}

struct GeneralSettingsView: View {
    @Binding var thumbnailSize: Double
    @Binding var gridColumns: Int

    var body: some View {
        Form {
            Section("Display") {
                Slider(value: $thumbnailSize, in: 80...200, step: 20) {
                    Text("Thumbnail Size")
                }

                Picker("Grid Columns", selection: $gridColumns) {
                    ForEach(2...8, id: \.self) { count in
                        Text("\(count)").tag(count)
                    }
                }
            }

            Section("Performance") {
                Text("Thumbnail caching is automatic based on available memory")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding()
    }
}

struct KeyboardShortcutsView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                ShortcutSection(title: "Navigation") {
                    ShortcutRow(keys: ["Arrow Keys"], action: "Navigate photos")
                    ShortcutRow(keys: ["Shift", "Arrow"], action: "Extend selection")
                    ShortcutRow(keys: ["Esc"], action: "Clear selection")
                }

                ShortcutSection(title: "Selection") {
                    ShortcutRow(keys: ["Cmd", "A"], action: "Select all")
                    ShortcutRow(keys: ["Shift", "Click"], action: "Range select")
                    ShortcutRow(keys: ["Cmd", "Click"], action: "Toggle select")
                }

                ShortcutSection(title: "Tagging") {
                    ShortcutRow(keys: ["T"], action: "Focus tag input")
                    ShortcutRow(keys: ["Ctrl", "Space"], action: "Show all tag suggestions")
                    ShortcutRow(keys: ["↑", "↓"], action: "Navigate suggestions")
                    ShortcutRow(keys: ["A"], action: "Accept all AI suggestions")
                    ShortcutRow(keys: ["Esc"], action: "Unfocus tag input")
                }

                ShortcutSection(title: "Preview") {
                    ShortcutRow(keys: ["Space"], action: "Quick preview (hold)")
                }

                ShortcutSection(title: "Other") {
                    ShortcutRow(keys: ["Cmd", "Delete"], action: "Delete selected")
                    ShortcutRow(keys: ["Cmd", "R"], action: "Refresh photos")
                }
            }
            .padding()
        }
    }
}

struct ShortcutSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.headline)
            content
        }
    }
}

struct ShortcutRow: View {
    let keys: [String]
    let action: String

    var body: some View {
        HStack {
            HStack(spacing: 4) {
                ForEach(keys, id: \.self) { key in
                    Text(key)
                        .font(.caption)
                        .fontWeight(.medium)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.secondary.opacity(0.2))
                        .cornerRadius(4)
                }
            }
            .frame(width: 120, alignment: .leading)

            Text(action)
                .font(.caption)
                .foregroundColor(.secondary)

            Spacer()
        }
    }
}

#Preview {
    SettingsView()
        .environmentObject(AppState())
}
