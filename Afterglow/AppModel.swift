import SwiftUI
import Photos
import PhotosUI

@MainActor
final class AppModel: ObservableObject {
    enum Tab: String, CaseIterable { case camera = "相机", darkroom = "暗房", roll = "胶卷" }
    @Published var tab: Tab = .camera
    @Published var recipe = FilmRecipe()
    @Published private(set) var original: Data?
    @Published private(set) var originalPreview: UIImage?
    @Published private(set) var developed: UIImage?
    @Published private(set) var photos: [SavedPhoto] = []
    @Published private(set) var busy = false
    @Published private(set) var rendering = false
    @Published private(set) var draftStatus = "原片与冲洗照片独立保留"
    @Published var message: String?
    @Published var error: String?
    let repository = PhotoRepository()
    private let worker = RenderWorker()
    private var previewTask: Task<Void, Never>?
    private var settingsTask: Task<Void, Never>?
    private var revision = 0
    private var savedRevision: Int?
    private var draftID: UUID?
    private var initialized = false
    private var restoring = false
    var hasDraft: Bool { original != nil }
    var canDevelop: Bool { hasDraft && !busy && !rendering && savedRevision != revision }

    func initialize() async {
        guard !initialized else { return }
        initialized = true; restoring = true; busy = true
        defer { restoring = false; busy = false }
        await loadRoll()
        await worker.clearPreviousExports()
        do {
            if let saved = try await repository.loadRecipe() { recipe = saved }
        } catch { self.error = "调色设置暂时无法恢复，已保留原文件。" }
        do {
            if let draft = try await repository.loadDraft() {
                let image = try await worker.original(draft.data)
                original = draft.data; originalPreview = image
                recipe = draft.metadata.recipe.normalized(); draftID = draft.metadata.id
                draftStatus = "已恢复上次的本机草稿"
                renderPreview()
            }
        } catch {
            self.error = "上次的草稿暂时无法恢复；文件仍保留：\(error.localizedDescription)"
        }
    }
    func loadRoll() async {
        do { photos = try await repository.load() }
        catch { self.error = "胶卷无法读取，原有文件已保留：\(error.localizedDescription)" }
    }
    func importPhoto(_ item: PhotosPickerItem) async {
        guard !busy else { return }
        busy = true
        defer { busy = false }
        do {
            guard let data = try await item.loadTransferable(type: Data.self) else { throw ImageFailure.unreadable }
            try await replaceDraft(data, recipe: recipe)
        } catch { self.error = error.localizedDescription }
    }
    func accept(_ data: Data) async throws {
        guard !busy else { return }
        busy = true
        defer { busy = false }
        try await replaceDraft(data, recipe: recipe)
    }
    private func replaceDraft(_ data: Data, recipe settings: FilmRecipe) async throws {
        guard data.count <= 100 * 1024 * 1024 else { throw ImageFailure.tooLarge }
        let image = try await worker.original(data)
        settingsTask?.cancel(); previewTask?.cancel()
        original = data; originalPreview = image; developed = nil; savedRevision = nil
        recipe = settings.normalized(); draftID = nil
        do {
            let saved = try await repository.saveDraft(data, recipe: recipe)
            draftID = saved.id
            try await repository.saveRecipe(recipe)
            draftStatus = "草稿已自动保存 · 可关闭后继续冲洗"
        } catch {
            draftStatus = "自动保存未完成，请及时冲洗或分享导出"
            self.error = "草稿尚未自动保存：\(error.localizedDescription)"
        }
        tab = .darkroom
        renderPreview()
    }
    func renderPreview() {
        revision += 1
        previewTask?.cancel()
        if !restoring { saveSettingsSoon() }
        guard let data = original else { rendering = false; return }
        let settings = recipe.normalized()
        let currentRevision = revision
        rendering = true
        previewTask = Task { [weak self] in
            do {
                try await Task.sleep(for: .milliseconds(80))
                guard let self else { return }
                let image = try await worker.render(data, recipe: settings, maxEdge: 1400)
                guard !Task.isCancelled, currentRevision == revision else { return }
                developed = image; rendering = false
            } catch is CancellationError { }
            catch { if !Task.isCancelled { self?.rendering = false; self?.error = error.localizedDescription } }
        }
    }
    private func saveSettingsSoon() {
        settingsTask?.cancel()
        let settings = recipe.normalized(), id = draftID
        settingsTask = Task { [weak self] in
            do {
                try await Task.sleep(for: .milliseconds(350))
                guard let self, !Task.isCancelled else { return }
                try await repository.saveRecipe(settings)
                try Task.checkCancellation()
                if let id { try await repository.updateDraftRecipe(settings, id: id) }
            } catch is CancellationError { }
            catch { self?.draftStatus = "最新调色尚未自动保存，请及时导出" }
        }
    }
    func flushSettings() async {
        guard initialized, !restoring else { return }
        settingsTask?.cancel()
        let settings = recipe.normalized(), id = draftID
        do {
            try await repository.saveRecipe(settings)
            if let id { try await repository.updateDraftRecipe(settings, id: id) }
        } catch { draftStatus = "最新调色尚未自动保存，请及时导出" }
    }
    func develop() async {
        guard let data = original, canDevelop else { return }
        busy = true
        let settings = recipe.normalized(), currentRevision = revision
        defer { busy = false }
        do {
            let jpeg = try await worker.jpeg(data, recipe: settings)
            let photo = try await repository.add(original: data, developed: jpeg, recipe: settings)
            photos.insert(photo, at: 0)
            savedRevision = currentRevision
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            message = "已冲洗入卷，原片也已保留。"
            tab = .roll
        } catch { self.error = error.localizedDescription }
    }
    @discardableResult
    func edit(_ photo: SavedPhoto) async -> Bool {
        guard !busy else { return false }
        busy = true
        defer { busy = false }
        do {
            let data = try await repository.data(for: photo, original: true)
            try await replaceDraft(data, recipe: photo.recipe)
            return true
        } catch { self.error = error.localizedDescription; return false }
    }
    @discardableResult
    func remove(_ photo: SavedPhoto) async -> Bool {
        guard !busy else { return false }
        busy = true
        defer { busy = false }
        do {
            let cleaned = try await repository.remove(photo)
            photos.removeAll { $0.id == photo.id }
            savedRevision = nil
            message = cleaned ? "已从本机胶卷移除。" : "已移出胶卷，剩余缓存将在下次读取胶卷时重试清理。"
            return true
        } catch { self.error = error.localizedDescription; return false }
    }
    func export(_ photo: SavedPhoto) async {
        guard !busy else { return }
        busy = true
        defer { busy = false }
        let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        guard status == .authorized || status == .limited else {
            error = "请在系统设置中允许余光添加照片，或使用分享导出。"
            return
        }
        do {
            let data = try await repository.data(for: photo)
            try await PHPhotoLibrary.shared().performChanges {
                let request = PHAssetCreationRequest.forAsset()
                request.addResource(with: .photo, data: data, options: nil)
            }
            message = "已保存到系统相册。"
        } catch { self.error = error.localizedDescription }
    }
    func prepareDraftShare() async -> URL? {
        guard !busy, let original else { return nil }
        busy = true
        let settings = recipe.normalized()
        defer { busy = false }
        do {
            let jpeg = try await worker.jpeg(original, recipe: settings)
            return try await worker.shareURL(jpeg, name: "AFTERGLOW-\(settings.stock.code)", original: false)
        } catch { self.error = error.localizedDescription; return nil }
    }
    func prepareShare(_ photo: SavedPhoto, original: Bool = false) async -> URL? {
        guard !busy else { return nil }
        busy = true
        defer { busy = false }
        do {
            let data = try await repository.data(for: photo, original: original)
            return try await worker.shareURL(data, name: original ? "AFTERGLOW-original" : "AFTERGLOW-\(photo.recipe.stock.code)", original: original)
        } catch { self.error = error.localizedDescription; return nil }
    }
}
