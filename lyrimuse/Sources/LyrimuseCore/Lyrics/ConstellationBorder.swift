import CoreGraphics
import Foundation

/// The glow around the edge of the constellation window.
///
/// The perimeter is one loop, 0…1 clockwise from the top-left. A few lobes drift around that loop at
/// their own speeds; each is fed by one audio band, so the light gathers and travels rather than
/// pulsing everywhere at once. Quiet passages leave a single faint patch in one corner, loud ones
/// wrap most of the frame.
public enum ConstellationBorder {
    public static let maximumThickness: CGFloat = 34
    public static let maximumAlpha: Double = 1
    /// Never quite nothing, so the frame keeps an edge even in silence.
    public static let floorIntensity: Double = 0.03
    /// Below this a stretch of the ring is not drawn at all, so the glow stays a travelling
    /// band rather than a faint wash all the way round.
    public static let visibleIntensity: Double = 0.07
    /// The inner edge is never a straight line: two slow ripples run along the loop. Proportional,
    /// so a dark stretch stays dark instead of growing a band of its own.
    public static let rippleDepth: Double = 0.14

    public struct Lobe: Equatable, Sendable {
        public let band: Int
        /// Loops around the perimeter per second; negative runs anticlockwise.
        public let speed: Double
        /// Half-width on the loop, as a fraction of the perimeter.
        public let width: Double
        public let phase: Double

        public init(band: Int, speed: Double, width: Double, phase: Double) {
            self.band = band
            self.speed = speed
            self.width = width
            self.phase = phase
        }
    }

    /// One wide arc covering roughly 60% of the perimeter, plus a narrow bright crest riding inside
    /// it on the beat. Both negative, so the light only ever travels anticlockwise; `loopPosition`
    /// runs clockwise.
    public static let lobes: [Lobe] = [
        Lobe(band: 0, speed: -0.045, width: 0.19, phase: 0.00),
        Lobe(band: 3, speed: -0.045, width: 0.05, phase: 0.06),
    ]

    /// Breathing levels for when no real audio is available, so the glow still drifts.
    public static func idleLevels(nowSeconds: Double) -> [Double] {
        (0..<RealAudioSpectrum.bandCount).map { band in
            let period: Double = 6.5 + Double(band) * 2.3
            let phase: Double = Double(band) * 0.7
            return 0.30 + 0.18 * sin(2 * .pi * nowSeconds / period + phase)
        }
    }

    /// Shortest distance between two points on a 0…1 loop.
    public static func loopDistance(_ a: Double, _ b: Double) -> Double {
        let raw = abs(a - b).truncatingRemainder(dividingBy: 1)
        return min(raw, 1 - raw)
    }

    /// 0…1 brightness at perimeter position `p`.
    public static func intensity(at p: Double, nowSeconds: Double, levels: [Double]) -> Double {
        let safe: [Double] = levels.map { $0.isFinite ? min(1, max(0, $0)) : 0 }
        var total: Double = floorIntensity
        for lobe in lobes {
            let level: Double = lobe.band < safe.count ? safe[lobe.band] : 0
            guard level > 0, lobe.width > 0 else { continue }
            let centre: Double = (lobe.phase + lobe.speed * nowSeconds).truncatingRemainder(dividingBy: 1)
            let reach: Double = loopDistance(p, centre < 0 ? centre + 1 : centre) / lobe.width
            total += level * exp(-reach * reach)
        }
        let slow: Double = sin(2 * .pi * (p * 7 - nowSeconds * 0.18))
        let fast: Double = sin(2 * .pi * (p * 13 + nowSeconds * 0.11))
        let ripple: Double = rippleDepth * (0.6 * slow + 0.4 * fast)
        return min(max(total * (1 + ripple), 0), 1)
    }

    public static func thickness(at p: Double, nowSeconds: Double, levels: [Double]) -> CGFloat {
        maximumThickness * CGFloat(intensity(at: p, nowSeconds: nowSeconds, levels: levels))
    }

    public static func alpha(at p: Double, nowSeconds: Double, levels: [Double]) -> Double {
        maximumAlpha * intensity(at: p, nowSeconds: nowSeconds, levels: levels)
    }

    /// Where a point on one edge sits on the perimeter loop. `fraction` runs along the edge in the
    /// direction the loop travels, so the four edges join without a seam.
    public static func loopPosition(edge: Int, fraction: Double, width: CGFloat, height: CGFloat) -> Double {
        let w = Double(max(width, 1))
        let h = Double(max(height, 1))
        let perimeter = 2 * (w + h)
        let along: Double
        switch edge {
        case 0: along = w * fraction
        case 1: along = w + h * fraction
        case 2: along = w + h + w * fraction
        default: along = 2 * w + h + h * fraction
        }
        return (along / perimeter).truncatingRemainder(dividingBy: 1)
    }
}
