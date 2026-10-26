import SwiftUI

enum FilmStock: String, Codable, CaseIterable, Identifiable {
    case amber, jade, neon, coastal, rose, silver
    var id: String { rawValue }
    var name: String {
        switch self {
        case .amber: return "日落 400"
        case .jade: return "青野 200"
        case .neon: return "霓虹 800"
        case .coastal: return "海岸 100"
        case .rose: return "玫瑰 160"
        case .silver: return "银盐 400"
        }
    }
    var code: String {
        switch self {
        case .amber: return "AMBER"
        case .jade: return "JADE"
        case .neon: return "NEON"
        case .coastal: return "COAST"
        case .rose: return "ROSE"
        case .silver: return "SILVER"
        }
    }
    var note: String {
        switch self {
        case .amber: return "暖金高光 · 柔和肤色"
        case .jade: return "青绿阴影 · 日系日常"
        case .neon: return "冷调夜色 · 红色光晕"
        case .coastal: return "清透蓝调 · 海边晴日"
        case .rose: return "柔粉色彩 · 浪漫人像"
        case .silver: return "经典黑白 · 银盐颗粒"
        }
    }
    var tint: Color {
        switch self {
        case .amber: return Color(red: 0.96, green: 0.64, blue: 0.28)
        case .jade: return Color(red: 0.55, green: 0.69, blue: 0.47)
        case .neon: return Color(red: 0.93, green: 0.37, blue: 0.34)
        case .coastal: return Color(red: 0.40, green: 0.69, blue: 0.80)
        case .rose: return Color(red: 0.83, green: 0.53, blue: 0.62)
        case .silver: return Color(white: 0.75)
        }
    }
    // Original creative looks, not licensed emulations of commercial film stocks.
    var color: (r: Double, g: Double, b: Double, saturation: Double, contrast: Double) {
        switch self {
        case .amber: return (1.075, 1.015, 0.91, 0.88, 1.06)
        case .jade: return (0.96, 1.055, 0.98, 0.78, 0.99)
        case .neon: return (1.045, 0.97, 1.065, 1.08, 1.13)
        case .coastal: return (0.97, 1.025, 1.065, 0.92, 1.02)
        case .rose: return (1.06, 0.98, 1.015, 0.77, 0.97)
        case .silver: return (1, 1, 1, 0, 1.13)
        }
    }
}

struct FilmRecipe: Codable, Equatable {
    var stock: FilmStock = .amber
    var exposure: Double = 0
    var grain: Double = 0.32
    var warmth: Double = 0
    var fade: Double = 0.16
    var vignette: Double = 0.25
    var lightLeak: Double = 0
    func normalized() -> FilmRecipe {
        var r = self
        func clamp(_ x: Double, _ low: Double, _ high: Double) -> Double {
            x.isFinite ? min(high, max(low, x)) : low
        }
        r.exposure = clamp(exposure, -2, 2)
        r.grain = clamp(grain, 0, 1)
        r.warmth = clamp(warmth, -1, 1)
        r.fade = clamp(fade, 0, 1)
        r.vignette = clamp(vignette, 0, 1)
        r.lightLeak = clamp(lightLeak, 0, 1)
        return r
    }
}

enum Palette {
    static let background = Color(red: 0.065, green: 0.067, blue: 0.063)
    static let panel = Color(red: 0.11, green: 0.115, blue: 0.105)
    static let cream = Color(red: 0.94, green: 0.91, blue: 0.84)
    static let muted = Color(red: 0.62, green: 0.63, blue: 0.57)
    static let orange = Color(red: 1, green: 0.35, blue: 0.18)
}
