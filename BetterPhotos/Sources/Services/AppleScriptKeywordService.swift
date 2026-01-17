import Foundation
import AppKit

enum AppleScriptError: LocalizedError {
    case executionFailed(String)
    case photosNotRunning
    case invalidPhotoId

    var errorDescription: String? {
        switch self {
        case .executionFailed(let message):
            return "AppleScript error: \(message)"
        case .photosNotRunning:
            return "Photos.app must be running to save tags"
        case .invalidPhotoId:
            return "Invalid photo identifier"
        }
    }
}

actor AppleScriptKeywordService {
    private var operationQueue: [() async throws -> Void] = []
    private var isProcessing = false

    /// Ensures Photos.app is running (required for AppleScript)
    func ensurePhotosRunning() async throws {
        let script = """
        tell application "Photos"
            if not running then
                activate
                delay 2
            end if
        end tell
        """
        _ = try await executeScript(script)
    }

    /// Gets current keywords for a photo
    func getKeywords(photoId: String) async throws -> [String] {
        let escapedId = escapeForAppleScript(photoId)
        let script = """
        tell application "Photos"
            try
                set thePhoto to media item id "\(escapedId)"
                set theKeywords to keywords of thePhoto
                if theKeywords is missing value then
                    return ""
                else
                    set AppleScript's text item delimiters to "|||"
                    return theKeywords as text
                end if
            on error
                return ""
            end try
        end tell
        """

        let result = try await executeScript(script)
        if result.isEmpty || result == "missing value" {
            return []
        }
        return result.components(separatedBy: "|||").map { $0.trimmingCharacters(in: .whitespaces) }
    }

    /// Sets keywords for a photo (replaces existing)
    func setKeywords(photoId: String, keywords: [String]) async throws {
        let escapedId = escapeForAppleScript(photoId)
        let keywordsList = keywords.map { "\"\(escapeForAppleScript($0))\"" }.joined(separator: ", ")

        let script = """
        tell application "Photos"
            set thePhoto to media item id "\(escapedId)"
            set keywords of thePhoto to {\(keywordsList)}
        end tell
        """

        _ = try await executeScript(script)
    }

    /// Adds keywords without replacing existing ones
    func addKeywords(photoId: String, newKeywords: [String]) async throws {
        let escapedId = escapeForAppleScript(photoId)
        let keywordsList = newKeywords.map { "\"\(escapeForAppleScript($0))\"" }.joined(separator: ", ")

        let script = """
        tell application "Photos"
            set thePhoto to media item id "\(escapedId)"
            set currentKeywords to keywords of thePhoto
            if currentKeywords is missing value then
                set keywords of thePhoto to {\(keywordsList)}
            else
                -- Add only keywords that don't already exist
                repeat with newKw in {\(keywordsList)}
                    if newKw is not in currentKeywords then
                        set end of currentKeywords to newKw
                    end if
                end repeat
                set keywords of thePhoto to currentKeywords
            end if
        end tell
        """

        _ = try await executeScript(script)
    }

    /// Removes specific keywords from a photo
    func removeKeywords(photoId: String, keywordsToRemove: [String]) async throws {
        let currentKeywords = try await getKeywords(photoId: photoId)
        let newKeywords = currentKeywords.filter { !keywordsToRemove.contains($0) }
        try await setKeywords(photoId: photoId, keywords: newKeywords)
    }

    /// Batch apply keywords to multiple photos
    func batchAddKeywords(photoIds: [String], keywords: [String], progress: ((Int, Int) -> Void)? = nil) async throws {
        for (index, photoId) in photoIds.enumerated() {
            try await addKeywords(photoId: photoId, newKeywords: keywords)
            progress?(index + 1, photoIds.count)
            // Small delay to prevent overwhelming Photos.app
            try await Task.sleep(nanoseconds: 100_000_000) // 0.1 second
        }
    }

    // MARK: - Album Management

    /// Adds a photo to an album
    func addToAlbum(photoId: String, albumId: String) async throws {
        let escapedPhotoId = escapeForAppleScript(photoId)
        let escapedAlbumId = escapeForAppleScript(albumId)

        let script = """
        tell application "Photos"
            set thePhoto to media item id "\(escapedPhotoId)"
            set theAlbum to album id "\(escapedAlbumId)"
            add {thePhoto} to theAlbum
        end tell
        """

        _ = try await executeScript(script)
    }

    /// Removes a photo from an album
    func removeFromAlbum(photoId: String, albumId: String) async throws {
        let escapedPhotoId = escapeForAppleScript(photoId)
        let escapedAlbumId = escapeForAppleScript(albumId)

        // Note: Photos doesn't have a direct "remove from album" command
        // We need to use a workaround - this removes the photo from the album but not from the library
        let script = """
        tell application "Photos"
            set theAlbum to album id "\(escapedAlbumId)"
            set thePhoto to media item id "\(escapedPhotoId)"
            remove {thePhoto} from theAlbum
        end tell
        """

        _ = try await executeScript(script)
    }

    /// Creates a new album and returns its ID
    func createAlbum(name: String) async throws -> String {
        let escapedName = escapeForAppleScript(name)

        let script = """
        tell application "Photos"
            set newAlbum to make new album named "\(escapedName)"
            return id of newAlbum
        end tell
        """

        return try await executeScript(script)
    }

    /// Opens selected photos in Photos.app by creating a temporary album for tagging
    /// The album is cleared and replaced each time to keep a clean slate
    func openPhotosForTagging(photoIds: [String], albumName: String = "BetterPhotos - To Tag") async throws {
        // Build list of photo IDs for AppleScript
        let escapedIds = photoIds.map { "\"\(escapeForAppleScript($0))\"" }.joined(separator: ", ")
        let escapedAlbumName = escapeForAppleScript(albumName)

        let script = """
        tell application "Photos"
            activate

            -- Delete existing album if it exists
            try
                set existingAlbum to album "\(escapedAlbumName)"
                delete existingAlbum
            end try

            -- Create new album
            set targetAlbum to make new album named "\(escapedAlbumName)"

            -- Add photos to album
            set photoIds to {\(escapedIds)}
            repeat with photoId in photoIds
                try
                    set thePhoto to media item id photoId
                    add {thePhoto} to targetAlbum
                end try
            end repeat

            -- Select the album in the sidebar
            delay 0.5
        end tell
        """

        _ = try await executeScript(script)
    }

    /// Fetches all unique keywords from the entire Photos library
    func getAllKeywords() async throws -> [String] {
        // Fast approach: get keywords property from all media items at once
        // This is much faster than iterating in AppleScript
        let script = """
        tell application "Photos"
            set kwList to keywords of every media item
            set allKw to {}
            repeat with kw in kwList
                if kw is not missing value then
                    repeat with k in kw
                        set end of allKw to (k as text)
                    end repeat
                end if
            end repeat
            set AppleScript's text item delimiters to "|||"
            return allKw as text
        end tell
        """

        let result = try await executeScript(script)
        if result.isEmpty {
            return []
        }

        // Deduplicate in Swift (much faster than AppleScript)
        let keywords = result.components(separatedBy: "|||")
            .map { $0.trimmingCharacters(in: .whitespaces).lowercased() }
            .filter { !$0.isEmpty }

        return Array(Set(keywords)).sorted()
    }

    // MARK: - Private

    private func executeScript(_ source: String) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                var errorDict: NSDictionary?
                let script = NSAppleScript(source: source)

                if let result = script?.executeAndReturnError(&errorDict) {
                    continuation.resume(returning: result.stringValue ?? "")
                } else if let error = errorDict {
                    let message = error["NSAppleScriptErrorMessage"] as? String ?? "Unknown AppleScript error"
                    continuation.resume(throwing: AppleScriptError.executionFailed(message))
                } else {
                    continuation.resume(returning: "")
                }
            }
        }
    }

    private func escapeForAppleScript(_ string: String) -> String {
        string
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
    }
}
