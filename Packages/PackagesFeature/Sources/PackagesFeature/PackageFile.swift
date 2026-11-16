import Foundation
import UniformTypeIdentifiers

/// The two kinds of Anki package Hayaki imports.
public enum PackageKind: Sendable, Hashable {
    /// A whole collection (`.colpkg`); importing it replaces the collection.
    case collectionPackage
    /// Chosen decks (`.apkg`); importing it merges them into the collection.
    case deckPackage

    /// The kind of package a file is, judged by its extension as Anki does;
    /// nil for any other file.
    init?(fileExtension: String) {
        switch fileExtension.lowercased() {
        case "colpkg": self = .collectionPackage
        case "apkg": self = .deckPackage
        default: return nil
        }
    }
}

/// A package the learner chose or opened from outside the app, copied into a
/// private staging folder so it stays readable for the whole import.
public struct PackageFile: Sendable, Equatable {
    public let kind: PackageKind
    /// The file's name as the learner knows it, such as "Spanish.apkg".
    public let name: String
    /// The staged copy the core reads.
    let url: URL

    /// Copies the package at `source` into a new staging folder. `source` may
    /// be a security-scoped URL from the file picker or from another app.
    @concurrent
    static func stage(_ source: URL) async throws -> PackageFile {
        guard let kind = PackageKind(fileExtension: source.pathExtension) else {
            throw NotAPackage()
        }
        let accessing = source.startAccessingSecurityScopedResource()
        defer { if accessing { source.stopAccessingSecurityScopedResource() } }

        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("Import-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let copy = folder.appendingPathComponent(source.lastPathComponent)
        // A file coordinator lets a file provider (iCloud Drive, another app's
        // storage) download or hand over the file before it is read.
        var coordinationError: NSError?
        var copyError: (any Error)?
        NSFileCoordinator().coordinate(readingItemAt: source, options: .withoutChanges, error: &coordinationError) { readable in
            do {
                try FileManager.default.copyItem(at: readable, to: copy)
            } catch {
                copyError = error
            }
        }
        if let error = coordinationError ?? copyError {
            try? FileManager.default.removeItem(at: folder)
            throw error
        }
        // A file another app handed over through the app's Inbox folder is the
        // app's own copy; it is not needed once staged.
        if isInInbox(source) {
            try? FileManager.default.removeItem(at: source)
        }
        return PackageFile(kind: kind, name: source.lastPathComponent, url: copy)
    }

    private static func isInInbox(_ url: URL) -> Bool {
        guard let documents = try? FileManager.default.url(
            for: .documentDirectory, in: .userDomainMask, appropriateFor: nil, create: false
        ) else { return false }
        let inbox = documents.appendingPathComponent("Inbox", isDirectory: true).resolvingSymlinksInPath()
        return url.deletingLastPathComponent().resolvingSymlinksInPath().path == inbox.path
    }

    /// Removes the staged copy.
    func discard() {
        try? FileManager.default.removeItem(at: url.deletingLastPathComponent())
    }
}

/// The file chosen is not a collection package or a deck package.
struct NotAPackage: Error {}

extension UTType {
    /// An Anki collection package (`.colpkg`), under the identifier desktop
    /// Anki declares for it (`net.ankiweb.anki.colpkg`). Hayaki imports the
    /// declaration in its Info.plist rather than owning the type.
    public static let ankiCollectionPackage = UTType(importedAs: "net.ankiweb.anki.colpkg", conformingTo: .data)

    /// An Anki deck package (`.apkg`), under the identifier desktop Anki
    /// declares for it (`net.ankiweb.anki.apkg`).
    public static let ankiDeckPackage = UTType(importedAs: "net.ankiweb.anki.apkg", conformingTo: .data)
}
