import Foundation

/// A file held on the shelf. We store a bookmark (a reference that survives
/// renames/moves), not the file itself, unless the user opted to copy.
struct ShelfItem: Identifiable, Codable, Equatable {
    let id: UUID
    var bookmark: Data
    var fileName: String
    /// Last known path, used as a fallback if the bookmark can't be resolved.
    var path: String
    var addedAt: Date
    /// True if the file is our own copy in Application Support (deleted on removal).
    var isCopy: Bool

    init(url: URL, bookmark: Data, isCopy: Bool) {
        self.id = UUID()
        self.bookmark = bookmark
        self.fileName = url.lastPathComponent
        self.path = url.path
        self.addedAt = .now
        self.isCopy = isCopy
    }
}

enum Sandbox {
    /// True when running inside the App Sandbox (security-scoped bookmarks required).
    static let isActive = ProcessInfo.processInfo.environment["APP_SANDBOX_CONTAINER_ID"] != nil

    static var bookmarkCreationOptions: URL.BookmarkCreationOptions {
        isActive ? [.withSecurityScope, .securityScopeAllowOnlyReadAccess] : []
    }

    static var bookmarkResolutionOptions: URL.BookmarkResolutionOptions {
        isActive ? [.withSecurityScope, .withoutUI] : [.withoutUI]
    }
}
