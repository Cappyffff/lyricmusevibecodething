import CoreGraphics
import Foundation

public struct ConstellationSwatch: Equatable, Sendable {
    public let red: Double
    public let green: Double
    public let blue: Double
    /// 0…1 around the colour wheel; the gradient is ordered by it.
    public let hue: Double

    public init(red: Double, green: Double, blue: Double, hue: Double) {
        self.red = red
        self.green = green
        self.blue = blue
        self.hue = hue
    }
}

/// Picks a handful of colours out of the cover art for the window border.
///
/// Pixels are binned by hue and weighted by how colourful and bright they are, so a mostly dark
/// sleeve still yields its few saturated areas rather than averaging to mud. Near-black, near-white
/// and washed-out pixels are skipped: they would drag every stop towards grey.
public enum ConstellationPalette {
    public static let hueBins = 12
    public static let minimumSaturation: Double = 0.18
    public static let minimumValue: Double = 0.12
    public static let maximumValue: Double = 0.97

    public static func hsv(red: Double, green: Double, blue: Double) -> (hue: Double, saturation: Double, value: Double) {
        let high = max(red, max(green, blue))
        let low = min(red, min(green, blue))
        let span = high - low
        guard span > 0, high > 0 else { return (0, 0, high) }
        var hue: Double
        if high == red {
            hue = (green - blue) / span
        } else if high == green {
            hue = 2 + (blue - red) / span
        } else {
            hue = 4 + (red - green) / span
        }
        hue /= 6
        if hue < 0 { hue += 1 }
        return (hue, span / high, high)
    }

    /// Up to `maximum` swatches, ordered around the colour wheel. Empty when the art has no usable colour.
    public static func swatches(premultipliedRGBA pixels: [UInt8], maximum: Int = 4) -> [ConstellationSwatch] {
        guard maximum > 0, pixels.count >= 4 else { return [] }
        var weights = [Double](repeating: 0, count: hueBins)
        var reds = [Double](repeating: 0, count: hueBins)
        var greens = [Double](repeating: 0, count: hueBins)
        var blues = [Double](repeating: 0, count: hueBins)

        var index = 0
        while index + 3 < pixels.count {
            let alpha = Double(pixels[index + 3]) / 255
            if alpha > 0.5 {
                let red = Double(pixels[index]) / 255
                let green = Double(pixels[index + 1]) / 255
                let blue = Double(pixels[index + 2]) / 255
                let parts = hsv(red: red, green: green, blue: blue)
                if parts.saturation >= minimumSaturation, parts.value >= minimumValue, parts.value <= maximumValue {
                    let bin = min(hueBins - 1, Int(parts.hue * Double(hueBins)))
                    let weight = parts.saturation * parts.value
                    weights[bin] += weight
                    reds[bin] += red * weight
                    greens[bin] += green * weight
                    blues[bin] += blue * weight
                }
            }
            index += 4
        }

        let ranked = (0..<hueBins).filter { weights[$0] > 0 }.sorted { weights[$0] > weights[$1] }
        let chosen = Array(ranked.prefix(maximum))
        guard !chosen.isEmpty else { return [] }
        let swatches: [ConstellationSwatch] = chosen.map { bin in
            let weight = weights[bin]
            let red = reds[bin] / weight
            let green = greens[bin] / weight
            let blue = blues[bin] / weight
            return ConstellationSwatch(red: red, green: green, blue: blue,
                                       hue: hsv(red: red, green: green, blue: blue).hue)
        }
        return swatches.sorted { $0.hue < $1.hue }
    }
}
