import Foundation
import UIKit

struct SavedPhoto: Identifiable, Codable, Equatable {
    var id: UUID
    var createdAt: Date
    var recipe: FilmRecipe
    var originalFile: String { "\(id.uuidString)-original.image" }
    var developedFile: String { "\(id.uuidString)-developed.jpg" }
    var thumbnailFile: String { "\(id.uuidString)-thumb.jpg" }
}

struct SavedDraft: Codable, Equatable {
    var id: UUID
    var recipe: FilmRecipe
    var originalFile: String { "draft-\(id.uuidString).image" }
}

actor PhotoRepository {
    let root: URL
    init(root: URL? = nil) {
        self.root = root ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Afterglow", isDirectory: true)
    }
    private var indexURL: URL { root.appendingPathComponent("photos.json") }
    private var draftURL: URL { root.appendingPathComponent("draft.json") }
    private var recipeURL: URL { root.appendingPathComponent("recipe.json") }
    private var deletionsURL: URL { root.appendingPathComponent("pending-deletions.json") }
    func load() throws -> [SavedPhoto] {
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        guard FileManager.default.fileExists(atPath: indexURL.path) else { return [] }
        // A damaged index is surfaced, never silently overwritten with an empty roll.
        let photos = try JSONDecoder().decode([SavedPhoto].self, from: Data(contentsOf: indexURL))
        if let pending = try? pendingDeletions() { _ = retryDeletionCleanup(pending, keeping: photos) }
        return photos
    }
    func loadRecipe() throws -> FilmRecipe? {
        guard FileManager.default.fileExists(atPath: recipeURL.path) else { return nil }
        return try JSONDecoder().decode(FilmRecipe.self, from: Data(contentsOf: recipeURL)).normalized()
    }
    func saveRecipe(_ recipe: FilmRecipe) throws {
        try Task.checkCancellation()
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try JSONEncoder().encode(recipe.normalized()).write(to: recipeURL, options: .atomic)
    }
    func loadDraft() throws -> (metadata: SavedDraft, data: Data)? {
        guard FileManager.default.fileExists(atPath: draftURL.path) else { return nil }
        let draft = try JSONDecoder().decode(SavedDraft.self, from: Data(contentsOf: draftURL))
        return (draft, try Data(contentsOf: root.appendingPathComponent(draft.originalFile)))
    }
    @discardableResult
    func saveDraft(_ data: Data, recipe: FilmRecipe) throws -> SavedDraft {
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let old = (try? Data(contentsOf: draftURL)).flatMap { try? JSONDecoder().decode(SavedDraft.self, from: $0) }
        let draft = SavedDraft(id: UUID(), recipe: recipe.normalized())
        let sourceURL = root.appendingPathComponent(draft.originalFile)
        do {
            try data.write(to: sourceURL, options: .atomic)
            try JSONEncoder().encode(draft).write(to: draftURL, options: .atomic)
        } catch {
            try? FileManager.default.removeItem(at: sourceURL)
            throw error
        }
        // Commit metadata before removing the previous draft's source.
        if let old { try? FileManager.default.removeItem(at: root.appendingPathComponent(old.originalFile)) }
        return draft
    }
    func updateDraftRecipe(_ recipe: FilmRecipe, id: UUID) throws {
        try Task.checkCancellation()
        guard FileManager.default.fileExists(atPath: draftURL.path) else { return }
        var draft = try JSONDecoder().decode(SavedDraft.self, from: Data(contentsOf: draftURL))
        // An old debounced edit must never overwrite a newly imported draft.
        guard draft.id == id else { return }
        draft.recipe = recipe.normalized()
        try JSONEncoder().encode(draft).write(to: draftURL, options: .atomic)
    }
    func add(original: Data, developed: Data, recipe: FilmRecipe) throws -> SavedPhoto {
        var photos = try load()
        let photo = SavedPhoto(id: UUID(), createdAt: Date(), recipe: recipe)
        let thumb = try FilmRenderer.decode(developed, maxEdge: 500)
        guard let thumbnail = thumb.jpegData(compressionQuality: 0.8) else { throw ImageFailure.storage }
        let files = [(photo.originalFile, original), (photo.developedFile, developed), (photo.thumbnailFile, thumbnail)]
        do {
            for (name, bytes) in files { try bytes.write(to: root.appendingPathComponent(name), options: .atomic) }
            photos.insert(photo, at: 0)
            try JSONEncoder().encode(photos).write(to: indexURL, options: .atomic)
        } catch {
            for (name, _) in files { try? FileManager.default.removeItem(at: root.appendingPathComponent(name)) }
            throw error
        }
        return photo
    }
    func data(for photo: SavedPhoto, original: Bool = false) throws -> Data {
        try Data(contentsOf: root.appendingPathComponent(original ? photo.originalFile : photo.developedFile))
    }
    func thumbnail(for photo: SavedPhoto) throws -> UIImage {
        let data = try Data(contentsOf: root.appendingPathComponent(photo.thumbnailFile))
        guard let image = UIImage(data: data) else { throw ImageFailure.unreadable }
        return image
    }
    @discardableResult
    func remove(_ photo: SavedPhoto) throws -> Bool {
        var photos = try load()
        var pending = try pendingDeletions()
        if !pending.contains(photo.id) { pending.append(photo.id) }
        // Record explicit deletion intent first. A failed index write leaves the
        // photo visible, and cleanup always protects IDs still in that index.
        try JSONEncoder().encode(pending).write(to: deletionsURL, options: .atomic)
        photos.removeAll { $0.id == photo.id }
        try JSONEncoder().encode(photos).write(to: indexURL, options: .atomic)
        return !retryDeletionCleanup(pending, keeping: photos).contains(photo.id)
    }
    private func pendingDeletions() throws -> [UUID] {
        guard FileManager.default.fileExists(atPath: deletionsURL.path) else { return [] }
        return try JSONDecoder().decode([UUID].self, from: Data(contentsOf: deletionsURL))
    }
    private func retryDeletionCleanup(_ pending: [UUID], keeping photos: [SavedPhoto]) -> [UUID] {
        let keep = Set(photos.map(\.id))
        var remaining: [UUID] = []
        for id in pending {
            guard !keep.contains(id) else { remaining.append(id); continue }
            var cleaned = true
            for suffix in ["-original.image", "-developed.jpg", "-thumb.jpg"] {
                let file = root.appendingPathComponent(id.uuidString + suffix)
                guard FileManager.default.fileExists(atPath: file.path) else { continue }
                do { try FileManager.default.removeItem(at: file) } catch { cleaned = false }
            }
            if !cleaned { remaining.append(id) }
        }
        // Unreferenced files without a deletion record may be recoverable captures;
        // never sweep them automatically after a crash or index recovery.
        try? JSONEncoder().encode(remaining).write(to: deletionsURL, options: .atomic)
        return remaining
    }
}
