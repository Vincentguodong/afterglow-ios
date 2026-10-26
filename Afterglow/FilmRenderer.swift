import UIKit
import CoreImage
import CoreImage.CIFilterBuiltins
import ImageIO
import UniformTypeIdentifiers

enum ImageFailure: LocalizedError {
    case unreadable, rendering, storage, tooLarge
    var errorDescription: String? {
        switch self {
        case .unreadable: return "无法读取这张照片，请选择另一张照片。"
        case .rendering: return "冲洗未完成，请重试。"
        case .storage: return "照片未保存。请检查剩余空间后重试。"
        case .tooLarge: return "请选择小于 100 MB 的照片。"
        }
    }
}

final class FilmRenderer {
    private let context = CIContext(options: [.cacheIntermediates: false])
    private static let noise: CIImage = {
        var seed: UInt64 = 13579
        var bytes = [UInt8](repeating: 0, count: 128 * 128 * 4)
        for i in stride(from: 0, to: bytes.count, by: 4) {
            seed = 2862933555777941757 &* seed &+ 3037000493
            let v = UInt8((seed >> 32) & 255)
            bytes[i] = v; bytes[i + 1] = v; bytes[i + 2] = v; bytes[i + 3] = 255
        }
        return CIImage(bitmapData: Data(bytes), bytesPerRow: 128 * 4,
                       size: CGSize(width: 128, height: 128), format: .RGBA8,
                       colorSpace: CGColorSpaceCreateDeviceRGB())
    }()

    func render(_ original: CIImage, recipe input: FilmRecipe, maxEdge: CGFloat = 4096) throws -> UIImage {
        let recipe = input.normalized()
        let size = original.extent.size
        guard size.width > 0, size.height > 0, size.width.isFinite, size.height.isFinite else { throw ImageFailure.unreadable }
        let scale = min(1, maxEdge / max(size.width, size.height))
        var image = original.transformed(by: CGAffineTransform(translationX: -original.extent.minX, y: -original.extent.minY))
            .transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        let extent = image.extent.integral
        let c = recipe.stock.color
        image = image.applyingFilter("CIExposureAdjust", parameters: [kCIInputEVKey: recipe.exposure])
        image = image.applyingFilter("CIColorControls", parameters: [kCIInputSaturationKey: c.saturation, kCIInputContrastKey: c.contrast])
        image = image.applyingFilter("CIColorMatrix", parameters: [
            "inputRVector": CIVector(x: c.r + recipe.warmth * 0.08, y: 0, z: 0, w: 0),
            "inputGVector": CIVector(x: 0, y: c.g, z: 0, w: 0),
            "inputBVector": CIVector(x: 0, y: 0, z: c.b - recipe.warmth * 0.08, w: 0)
        ])
        let lift = recipe.fade * 0.11
        image = image.applyingFilter("CIToneCurve", parameters: [
            "inputPoint0": CIVector(x: 0, y: lift),
            "inputPoint1": CIVector(x: 0.25, y: 0.23 + lift * 0.5),
            "inputPoint2": CIVector(x: 0.5, y: 0.50),
            "inputPoint3": CIVector(x: 0.75, y: 0.77),
            "inputPoint4": CIVector(x: 1, y: 0.985)
        ])
        if recipe.grain > 0 {
            let grainScale = max(0.65, max(extent.width, extent.height) / 1500)
            let noise = Self.noise.applyingFilter("CIAffineTile")
                .transformed(by: CGAffineTransform(scaleX: grainScale, y: grainScale))
                .cropped(to: extent)
                .applyingFilter("CIColorMatrix", parameters: ["inputAVector": CIVector(x: 0, y: 0, z: 0, w: recipe.grain * 0.24)])
            image = noise.applyingFilter("CISoftLightBlendMode", parameters: [kCIInputBackgroundImageKey: image])
        }
        if recipe.lightLeak > 0 {
            let gradient = CIFilter.linearGradient()
            gradient.point0 = CGPoint(x: 0, y: extent.midY)
            gradient.point1 = CGPoint(x: extent.width * 0.62, y: extent.midY)
            gradient.color0 = CIColor(red: 1, green: 0.18, blue: 0.035, alpha: recipe.lightLeak * 0.62)
            gradient.color1 = CIColor(red: 1, green: 0.42, blue: 0.06, alpha: 0)
            if let leak = gradient.outputImage?.cropped(to: extent) {
                image = leak.applyingFilter("CIScreenBlendMode", parameters: [kCIInputBackgroundImageKey: image])
            }
        }
        image = image.applyingFilter("CIVignette", parameters: [kCIInputIntensityKey: recipe.vignette * 1.7, kCIInputRadiusKey: max(extent.width, extent.height) * 0.7])
        guard let cg = context.createCGImage(image.cropped(to: extent), from: extent, format: .RGBA8, colorSpace: CGColorSpace(name: CGColorSpace.sRGB)) else { throw ImageFailure.rendering }
        return UIImage(cgImage: cg)
    }

    func render(data: Data, recipe: FilmRecipe, maxEdge: CGFloat = 4096) throws -> UIImage {
        let image = try Self.decode(data, maxEdge: maxEdge)
        guard let ci = CIImage(image: image) else { throw ImageFailure.unreadable }
        return try render(ci, recipe: recipe, maxEdge: maxEdge)
    }

    static func decode(_ data: Data, maxEdge: CGFloat) throws -> UIImage {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: Int(maxEdge),
                kCGImageSourceShouldCacheImmediately: true
              ] as CFDictionary) else { throw ImageFailure.unreadable }
        return UIImage(cgImage: image)
    }
}

actor RenderWorker {
    private let renderer = FilmRenderer()
    func render(_ data: Data, recipe: FilmRecipe, maxEdge: CGFloat) throws -> UIImage {
        try autoreleasepool { try renderer.render(data: data, recipe: recipe, maxEdge: maxEdge) }
    }
    func original(_ data: Data) throws -> UIImage { try FilmRenderer.decode(data, maxEdge: 1400) }
    func jpeg(_ data: Data, recipe: FilmRecipe) throws -> Data {
        try autoreleasepool {
            let image = try renderer.render(data: data, recipe: recipe, maxEdge: 4096)
            guard let jpeg = image.jpegData(compressionQuality: 0.95) else { throw ImageFailure.rendering }
            return jpeg
        }
    }
    func shareURL(_ data: Data, name: String, original: Bool) throws -> URL {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("AfterglowExports", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        var extensionName = "jpg"
        if original, let source = CGImageSourceCreateWithData(data as CFData, nil), let type = CGImageSourceGetType(source),
           let detected = UTType(type as String)?.preferredFilenameExtension { extensionName = detected }
        let url = folder.appendingPathComponent("\(name)-\(UUID().uuidString).\(extensionName)")
        try data.write(to: url, options: .atomic)
        return url
    }
    func clearPreviousExports() {
        // Only temporary copies created by a previous app session are removed.
        // Never touch the originals, photo library, or current-session shares.
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("AfterglowExports", isDirectory: true)
        try? FileManager.default.removeItem(at: folder)
    }
}
