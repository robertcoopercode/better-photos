import Foundation
import SQLite3

struct PersonInfo: Identifiable, Equatable {
    let id: String
    let name: String
    let faceCount: Int

    init(id: String, name: String, faceCount: Int = 0) {
        self.id = id
        self.name = name
        self.faceCount = faceCount
    }
}

struct KeywordWithCount: Identifiable, Equatable {
    let id: String
    let keyword: String
    let count: Int

    init(keyword: String, count: Int) {
        self.id = keyword
        self.keyword = keyword
        self.count = count
    }
}

/// Service for directly querying the Photos SQLite database
/// Much faster than AppleScript for read-only operations like fetching all keywords
class PhotosDatabaseService {

    /// Opens the Photos database directly in read-only mode
    private func openDatabaseCopy() -> OpaquePointer? {
        guard let dbPath = findPhotosDatabasePath() else {
            return nil
        }

        // Open in read-only mode without immutable flag so we can see WAL changes
        let uri = "file:\(dbPath)?mode=ro"

        var db: OpaquePointer?
        let result = sqlite3_open_v2(uri, &db, SQLITE_OPEN_READONLY | SQLITE_OPEN_URI, nil)

        guard result == SQLITE_OK else {
            if let db = db {
                sqlite3_close(db)
            }
            return nil
        }

        return db
    }

    /// Fetches all unique keywords from the Photos library database
    func getAllKeywords() -> [String] {
        guard let db = openDatabaseCopy() else {
            return []
        }
        defer { sqlite3_close(db) }

        let query = "SELECT DISTINCT ZTITLE FROM ZKEYWORD WHERE ZTITLE IS NOT NULL ORDER BY ZTITLE"

        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, query, -1, &statement, nil) == SQLITE_OK else {
            return []
        }
        defer { sqlite3_finalize(statement) }

        var keywords: [String] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            if let cString = sqlite3_column_text(statement, 0) {
                let keyword = String(cString: cString)
                keywords.append(keyword)
            }
        }

        return keywords
    }

    /// Fetches all keywords with their photo counts, ordered by count descending
    /// - Parameter includeEmpty: If true, includes keywords with zero photos
    func getKeywordsWithCounts(includeEmpty: Bool = false) -> [KeywordWithCount] {
        guard let db = openDatabaseCopy() else {
            return []
        }
        defer { sqlite3_close(db) }

        // First, discover the junction table column names (they vary by macOS version)
        let columnNames = discoverJunctionTableColumns(db)

        guard let keywordFK = columnNames.keywordFK,
              let assetAttrFK = columnNames.assetAttrFK else {
            return getAllKeywords().map { KeywordWithCount(keyword: $0, count: 0) }
        }

        // Query to get keywords with photo/video counts
        let havingClause = includeEmpty ? "" : "HAVING cnt > 0"
        let query = """
            SELECT k.ZTITLE, COUNT(DISTINCT CASE
                WHEN a.ZKIND IN (0, 1)
                     AND (a.ZTRASHEDSTATE = 0 OR a.ZTRASHEDSTATE IS NULL)
                     AND (a.ZHIDDEN = 0 OR a.ZHIDDEN IS NULL)
                THEN a.Z_PK
                ELSE NULL
            END) as cnt
            FROM ZKEYWORD k
            LEFT JOIN Z_1KEYWORDS jt ON jt.\(keywordFK) = k.Z_PK
            LEFT JOIN ZADDITIONALASSETATTRIBUTES attr ON attr.Z_PK = jt.\(assetAttrFK)
            LEFT JOIN ZASSET a ON a.Z_PK = attr.ZASSET
            WHERE k.ZTITLE IS NOT NULL
            GROUP BY k.ZTITLE
            \(havingClause)
            ORDER BY cnt DESC, k.ZTITLE ASC
        """

        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, query, -1, &statement, nil) == SQLITE_OK else {
            return getAllKeywords().map { KeywordWithCount(keyword: $0, count: 0) }
        }
        defer { sqlite3_finalize(statement) }

        var keywords: [KeywordWithCount] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            if let titleCString = sqlite3_column_text(statement, 0) {
                let keyword = String(cString: titleCString)
                let count = Int(sqlite3_column_int(statement, 1))
                keywords.append(KeywordWithCount(keyword: keyword, count: count))
            }
        }

        return keywords
    }

    /// Discovers the column names in Z_1KEYWORDS junction table (varies by macOS version)
    private func discoverJunctionTableColumns(_ db: OpaquePointer) -> (keywordFK: String?, assetAttrFK: String?) {
        let pragmaQuery = "PRAGMA table_info(Z_1KEYWORDS)"
        var pragmaStmt: OpaquePointer?

        guard sqlite3_prepare_v2(db, pragmaQuery, -1, &pragmaStmt, nil) == SQLITE_OK else {
            return (nil, nil)
        }
        defer { sqlite3_finalize(pragmaStmt) }

        var keywordFK: String?
        var assetAttrFK: String?

        while sqlite3_step(pragmaStmt) == SQLITE_ROW {
            if let nameCString = sqlite3_column_text(pragmaStmt, 1) {
                let columnName = String(cString: nameCString)
                // Look for keyword foreign key (contains "KEYWORDS" but not "ASSETATTRIBUTES")
                if columnName.contains("KEYWORDS") && !columnName.contains("ASSETATTRIBUTES") {
                    keywordFK = columnName
                }
                // Look for asset attributes foreign key
                if columnName.contains("ASSETATTRIBUTES") {
                    assetAttrFK = columnName
                }
            }
        }

        return (keywordFK, assetAttrFK)
    }

    /// Gets photo UUIDs that have a specific keyword
    func getPhotoUUIDsWithKeyword(_ keyword: String) -> [String] {
        guard let db = openDatabaseCopy() else {
            return []
        }
        defer { sqlite3_close(db) }

        let columnNames = discoverJunctionTableColumns(db)
        guard let keywordFK = columnNames.keywordFK,
              let assetAttrFK = columnNames.assetAttrFK else {
            return []
        }

        let escapedKeyword = keyword.replacingOccurrences(of: "'", with: "''")
        let query = """
            SELECT DISTINCT a.ZUUID
            FROM ZKEYWORD k
            JOIN Z_1KEYWORDS jt ON jt.\(keywordFK) = k.Z_PK
            JOIN ZADDITIONALASSETATTRIBUTES attr ON attr.Z_PK = jt.\(assetAttrFK)
            JOIN ZASSET a ON a.Z_PK = attr.ZASSET
            WHERE k.ZTITLE = '\(escapedKeyword)'
              AND a.ZKIND IN (0, 1)
              AND (a.ZTRASHEDSTATE = 0 OR a.ZTRASHEDSTATE IS NULL)
              AND (a.ZHIDDEN = 0 OR a.ZHIDDEN IS NULL)
            ORDER BY a.ZDATECREATED DESC
        """

        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, query, -1, &statement, nil) == SQLITE_OK else {
            return []
        }
        defer { sqlite3_finalize(statement) }

        var uuids: [String] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            if let uuidCString = sqlite3_column_text(statement, 0) {
                uuids.append(String(cString: uuidCString))
            }
        }

        return uuids
    }

    /// Fetches all known people from the Photos library database
    func getAllPeople() -> [PersonInfo] {
        guard let db = openDatabaseCopy() else {
            return []
        }
        defer { sqlite3_close(db) }

        let query = """
            SELECT Z_PK,
                   COALESCE(NULLIF(ZDISPLAYNAME, ''), ZFULLNAME) as name,
                   COALESCE(ZFACECOUNT, 0) as facecount
            FROM ZPERSON
            WHERE (ZFULLNAME IS NOT NULL AND ZFULLNAME != '')
               OR (ZDISPLAYNAME IS NOT NULL AND ZDISPLAYNAME != '')
            ORDER BY name
        """

        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, query, -1, &statement, nil) == SQLITE_OK else {
            return []
        }
        defer { sqlite3_finalize(statement) }

        var people: [PersonInfo] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            let pk = sqlite3_column_int64(statement, 0)
            if let nameCString = sqlite3_column_text(statement, 1) {
                let name = String(cString: nameCString)
                let faceCount = Int(sqlite3_column_int(statement, 2))

                people.append(PersonInfo(
                    id: String(pk),
                    name: name,
                    faceCount: faceCount
                ))
            }
        }

        return people
    }

    /// Returns UUIDs of photos/videos with no detected faces
    func getPhotoUUIDsWithoutFaces() -> [String] {
        guard let db = openDatabaseCopy() else {
            return []
        }
        defer { sqlite3_close(db) }

        let query = """
            SELECT a.ZUUID FROM ZASSET a
            WHERE a.ZKIND IN (0, 1)
              AND (a.ZTRASHEDSTATE = 0 OR a.ZTRASHEDSTATE IS NULL)
              AND (a.ZHIDDEN = 0 OR a.ZHIDDEN IS NULL)
              AND NOT EXISTS (SELECT 1 FROM ZDETECTEDFACE f WHERE f.ZASSETFORFACE = a.Z_PK)
            ORDER BY a.ZDATECREATED DESC
        """

        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, query, -1, &statement, nil) == SQLITE_OK else {
            return []
        }
        defer { sqlite3_finalize(statement) }

        var uuids: [String] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            if let uuidCString = sqlite3_column_text(statement, 0) {
                uuids.append(String(cString: uuidCString))
            }
        }

        return uuids
    }

    /// Returns count of photos/videos with no detected faces
    func getPhotosWithoutFacesCount() -> Int {
        guard let db = openDatabaseCopy() else {
            return 0
        }
        defer { sqlite3_close(db) }

        let query = """
            SELECT COUNT(*) FROM ZASSET a
            WHERE a.ZKIND IN (0, 1)
              AND (a.ZTRASHEDSTATE = 0 OR a.ZTRASHEDSTATE IS NULL)
              AND (a.ZHIDDEN = 0 OR a.ZHIDDEN IS NULL)
              AND NOT EXISTS (SELECT 1 FROM ZDETECTEDFACE f WHERE f.ZASSETFORFACE = a.Z_PK)
        """

        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, query, -1, &statement, nil) == SQLITE_OK else {
            return 0
        }
        defer { sqlite3_finalize(statement) }

        if sqlite3_step(statement) == SQLITE_ROW {
            return Int(sqlite3_column_int(statement, 0))
        }

        return 0
    }

    /// Fetches people/pets detected in a specific photo
    func getPeopleInPhoto(photoUUID: String) -> [PersonInfo] {
        guard let db = openDatabaseCopy() else {
            return []
        }
        defer { sqlite3_close(db) }

        // PhotoKit localIdentifier format: "UUID/L0/001" - extract just the UUID part
        let cleanUUID = photoUUID.components(separatedBy: "/").first ?? photoUUID

        let query = """
            SELECT DISTINCT p.Z_PK,
                   COALESCE(NULLIF(p.ZDISPLAYNAME, ''), p.ZFULLNAME) as name
            FROM ZPERSON p
            INNER JOIN ZDETECTEDFACE f ON f.ZPERSONFORFACE = p.Z_PK
            INNER JOIN ZASSET a ON f.ZASSETFORFACE = a.Z_PK
            WHERE a.ZUUID = '\(cleanUUID)'
              AND ((p.ZFULLNAME IS NOT NULL AND p.ZFULLNAME != '')
                   OR (p.ZDISPLAYNAME IS NOT NULL AND p.ZDISPLAYNAME != ''))
        """

        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, query, -1, &statement, nil) == SQLITE_OK else {
            return []
        }
        defer { sqlite3_finalize(statement) }

        var people: [PersonInfo] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            let pk = sqlite3_column_int64(statement, 0)
            if let nameCString = sqlite3_column_text(statement, 1) {
                let name = String(cString: nameCString)
                people.append(PersonInfo(
                    id: String(pk),
                    name: name
                ))
            }
        }

        return people
    }

    /// Finds the path to the Photos library database
    private func findPhotosDatabasePath() -> String? {
        let fileManager = FileManager.default
        let homeDir = fileManager.homeDirectoryForCurrentUser.path

        // Default location
        let defaultPath = "\(homeDir)/Pictures/Photos Library.photoslibrary/database/Photos.sqlite"

        if fileManager.fileExists(atPath: defaultPath) {
            return defaultPath
        }

        // Try alternative: look for any .photoslibrary in Pictures
        let picturesPath = "\(homeDir)/Pictures"
        if let contents = try? fileManager.contentsOfDirectory(atPath: picturesPath) {
            for item in contents where item.hasSuffix(".photoslibrary") {
                let dbPath = "\(picturesPath)/\(item)/database/Photos.sqlite"
                if fileManager.fileExists(atPath: dbPath) {
                    return dbPath
                }
            }
        }

        return nil
    }
}
