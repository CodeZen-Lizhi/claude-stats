import SwiftUI

/// Stable, deterministic colors for models so charts and lists agree.
///
/// Models in the same family share a base hue (`opus` → violet, `sonnet` →
/// blue, `haiku` → teal, `gpt`/`codex`/`o1`/`o3` → green, `gemini` → amber);
/// different versions within a family get a brightness/saturation nudge so
/// they're still distinguishable. Anything unrecognised gets a hue spread
/// across the wheel from its name's hash.
///
/// (Substring matching mirrors how ``ModelPricing/rate(for:)`` resolves rates,
/// keeping family detection in one mental model.)
enum ModelPalette {
    static func color(for model: String) -> Color {
        let h = stableHash(model)
        if let baseHue = familyHue(for: model) {
            let brightness = 0.62 + Double(h % 3) * 0.13          // 0.62 / 0.75 / 0.88
            let saturation = 0.55 + Double((h >> 2) % 3) * 0.12   // 0.55 / 0.67 / 0.79
            return Color(hue: baseHue, saturation: saturation, brightness: brightness)
        }
        let hue = Double(h % 360) / 360
        return Color(hue: hue, saturation: 0.62, brightness: 0.85)
    }

    private static func familyHue(for model: String) -> Double? {
        let m = model.lowercased()
        if m.contains("opus")   { return 0.78 }   // violet
        if m.contains("haiku")  { return 0.45 }   // teal
        if m.contains("sonnet") { return 0.58 }   // blue
        if m.contains("gemini") { return 0.07 }   // amber
        if m.contains("gpt") || m.contains("codex") || m.contains("o1") || m.contains("o3") { return 0.33 } // green
        return nil
    }

    /// FNV-1a over UTF-8 — process-stable, unlike Swift's randomized
    /// `hashValue`. We only need a well-spread small integer.
    private static func stableHash(_ s: String) -> UInt64 {
        var hash: UInt64 = 0xcbf29ce484222325
        for byte in s.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x100000001b3
        }
        return hash
    }
}
