# BetterPhotos

A fast, keyboard-driven photo tagging app for macOS that syncs with Apple Photos.

## Features

- **Keyboard-First Navigation**: Use arrow keys to navigate, number keys for quick tags
- **AI-Powered Suggestions**: Apple Vision analyzes photos and suggests relevant tags
- **iCloud Sync**: Tags sync to Apple Photos and across all your devices
- **Bulk Tagging**: Select multiple photos and tag them all at once

## Requirements

- macOS 14.0 (Sonoma) or later
- Photos.app must be running to save tags
- Xcode 15+ (for development)

## Setup

### Option 1: Using XcodeGen (Recommended)

1. Install XcodeGen if you don't have it:
   ```bash
   brew install xcodegen
   ```

2. Generate the Xcode project:
   ```bash
   cd ~/Projects/better-photos
   xcodegen generate
   ```

3. Open the project:
   ```bash
   open BetterPhotos.xcodeproj
   ```

### Option 2: Create Xcode Project Manually

1. Open Xcode and create a new macOS App project
2. Choose SwiftUI for the interface
3. Copy all files from `BetterPhotos/Sources/` into your project
4. Add the Info.plist keys for Photos and AppleScript access
5. Disable App Sandbox in Signing & Capabilities

## Keyboard Shortcuts

### Navigation
| Key | Action |
|-----|--------|
| Arrow Keys | Navigate photos |
| Enter/Space | Toggle preview |
| Esc | Clear selection |

### Selection
| Key | Action |
|-----|--------|
| ⌘A | Select all |
| Shift+Click | Range select |
| ⌘+Click | Toggle select |

### Tagging
| Key | Action |
|-----|--------|
| T | Focus tag input |
| 1-9 | Apply quick tag |
| A | Accept all AI suggestions |
| ⌥1-9 | Accept specific AI suggestion |
| ⌘Enter | Apply and move to next |

## Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                        SwiftUI App                              │
├─────────────────┬─────────────────────────┬────────────────────┤
│    PhotoKit     │     AppleScript         │   Apple Vision     │
│  (Read photos)  │  (Write keywords)       │  (AI suggestions)  │
├─────────────────┴─────────────────────────┴────────────────────┤
│                      Apple Photos                               │
│                    (iCloud Sync)                                │
└─────────────────────────────────────────────────────────────────┘
```

**Important**: PhotoKit cannot write keywords. AppleScript is the only way to modify keywords programmatically, which is why Photos.app must be running.

## Project Structure

```
BetterPhotos/Sources/
├── BetterPhotosApp.swift          # App entry point
├── Models/
│   ├── AppState.swift             # Central state management
│   ├── PhotoAsset.swift           # Photo data model
│   └── TagSuggestion.swift        # AI suggestion model
├── Views/
│   ├── ContentView.swift          # Main layout
│   ├── SidebarView.swift          # Left sidebar
│   ├── PhotoGridView.swift        # Photo grid with keyboard nav
│   ├── TagPanelView.swift         # Right panel for tagging
│   └── SettingsView.swift         # Preferences
└── Services/
    ├── PhotoLibraryService.swift  # PhotoKit integration
    ├── AppleScriptKeywordService.swift  # Keyword writing
    ├── ThumbnailCache.swift       # Image caching
    ├── VisionTaggingService.swift # AI analysis
    └── PhotosAppMonitor.swift     # Photos.app status
```

## Privacy

- All AI analysis happens on-device using Apple's Vision framework
- No photos or data are sent to external servers
- Tags are stored in Apple Photos and sync via your iCloud account

## License

MIT
