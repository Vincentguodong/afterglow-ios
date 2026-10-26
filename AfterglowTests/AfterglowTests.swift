import XCTest
import CoreImage
import UIKit
@testable import Afterglow

final class AfterglowTests: XCTestCase {
    func testRecipeRoundTripAndBounds() throws {
        var recipe = FilmRecipe(stock: .neon, exposure: 9, grain: -1, warmth: 3, fade: 2, vignette: 2, lightLeak: 2)
        recipe = recipe.normalized()
        XCTAssertEqual(recipe.exposure, 2)
        XCTAssertEqual(recipe.grain, 0)
        XCTAssertEqual(recipe.warmth, 1)
        XCTAssertEqual(recipe, try JSONDecoder().decode(FilmRecipe.self, from: JSONEncoder().encode(recipe)))
    }
    func testRendererAllStocksKeepImageExtent() throws {
        let input = CIImage(color: CIColor(red: 0.4, green: 0.5, blue: 0.6)).cropped(to: CGRect(x: 0, y: 0, width: 120, height: 160))
        for stock in FilmStock.allCases {
            let result = try FilmRenderer().render(input, recipe: FilmRecipe(stock: stock), maxEdge: 80)
            XCTAssertEqual(result.cgImage?.width, 60)
            XCTAssertEqual(result.cgImage?.height, 80)
        }
    }
    func testExposureChangesActualPixels() throws {
        let input = CIImage(color: CIColor(red: 0.25, green: 0.25, blue: 0.25)).cropped(to: CGRect(x: 0, y: 0, width: 16, height: 16))
        let renderer = FilmRenderer()
        let low = try renderer.render(input, recipe: FilmRecipe(exposure: -1, grain: 0, fade: 0, vignette: 0))
        let high = try renderer.render(input, recipe: FilmRecipe(exposure: 1, grain: 0, fade: 0, vignette: 0))
        func mean(_ image: UIImage) -> Double {
            let data = image.cgImage!.dataProvider!.data! as Data
            return stride(from: 0, to: data.count, by: 4).map { Double(data[$0]) }.reduce(0, +) / Double(data.count / 4)
        }
        XCTAssertGreaterThan(mean(high), mean(low))
    }
    func testRepositoryPreservesOriginalAcrossReloadAndDelete() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let repository = PhotoRepository(root: root)
        let data = UIGraphicsImageRenderer(size: CGSize(width: 40, height: 60)).jpegData(withCompressionQuality: 0.9) { c in
            UIColor.orange.setFill(); c.fill(CGRect(x: 0, y: 0, width: 40, height: 60))
        }
        let photo = try await repository.add(original: data, developed: data, recipe: FilmRecipe())
        let restored = PhotoRepository(root: root)
        let photos = try await restored.load()
        let original = try await restored.data(for: photo, original: true)
        XCTAssertEqual(photos, [photo])
        XCTAssertEqual(original, data)
        try await restored.remove(photo)
        let empty = try await restored.load()
        XCTAssertTrue(empty.isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent(photo.originalFile).path))
    }
    func testCorruptIndexIsNotOverwritten() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let damaged = Data("not json".utf8)
        try damaged.write(to: root.appendingPathComponent("photos.json"))
        do { _ = try await PhotoRepository(root: root).load(); XCTFail("Corruption must be surfaced") }
        catch { XCTAssertEqual(try Data(contentsOf: root.appendingPathComponent("photos.json")), damaged) }
    }
    func testDraftRestoresOriginalAndRecipeAndIgnoresOldEdits() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let repository = PhotoRepository(root: root)
        let first = try await repository.saveDraft(Data([1, 2, 3]), recipe: FilmRecipe(stock: .jade))
        let nextRecipe = FilmRecipe(stock: .silver, exposure: 0.4)
        let second = try await repository.saveDraft(Data([4, 5, 6]), recipe: nextRecipe)
        try await repository.updateDraftRecipe(FilmRecipe(stock: .neon), id: first.id)
        let restored = try await PhotoRepository(root: root).loadDraft()
        XCTAssertEqual(restored?.metadata.id, second.id)
        XCTAssertEqual(restored?.metadata.recipe, nextRecipe)
        XCTAssertEqual(restored?.data, Data([4, 5, 6]))
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent(first.originalFile).path))
    }
    func testDeletingPhotoWithMissingThumbnailStillRemovesRemainingFiles() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let repository = PhotoRepository(root: root)
        let data = UIGraphicsImageRenderer(size: CGSize(width: 20, height: 30)).jpegData(withCompressionQuality: 0.9) { c in
            UIColor.blue.setFill(); c.fill(CGRect(x: 0, y: 0, width: 20, height: 30))
        }
        let photo = try await repository.add(original: data, developed: data, recipe: FilmRecipe())
        try FileManager.default.removeItem(at: root.appendingPathComponent(photo.thumbnailFile))
        let cleaned = try await repository.remove(photo)
        let photos = try await repository.load()
        XCTAssertTrue(cleaned); XCTAssertTrue(photos.isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent(photo.originalFile).path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent(photo.developedFile).path))
    }
    func testCameraFramingMatchesPreviewAspect() throws {
        let format = UIGraphicsImageRendererFormat(); format.scale = 1
        let input = UIGraphicsImageRenderer(size: CGSize(width: 120, height: 160), format: format).jpegData(withCompressionQuality: 1) { c in
            UIColor.red.setFill(); c.fill(CGRect(x: 0, y: 0, width: 120, height: 160))
        }
        let cropped = try CameraService.framedJPEG(input, aspectRatio: 4.0 / 3.0)
        let image = try FilmRenderer.decode(cropped, maxEdge: 4096)
        XCTAssertEqual(image.cgImage?.width, 120)
        XCTAssertEqual(image.cgImage?.height, 90)
    }
    func testOriginalSharePreservesPNGBytesAndExtension() async throws {
        let data = UIGraphicsImageRenderer(size: CGSize(width: 20, height: 20)).pngData { c in
            UIColor.green.setFill(); c.fill(CGRect(x: 0, y: 0, width: 20, height: 20))
        }
        let url = try await RenderWorker().shareURL(data, name: "test-original", original: true)
        defer { try? FileManager.default.removeItem(at: url) }
        XCTAssertEqual(url.pathExtension, "png")
        XCTAssertEqual(try Data(contentsOf: url), data)
    }
    func testUnindexedCaptureIsPreservedForRecovery() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try Data("[]".utf8).write(to: root.appendingPathComponent("photos.json"))
        let recovered = root.appendingPathComponent(UUID().uuidString + "-original.image")
        try Data([1, 2, 3]).write(to: recovered)
        _ = try await PhotoRepository(root: root).load()
        XCTAssertEqual(try Data(contentsOf: recovered), Data([1, 2, 3]))
    }
}
