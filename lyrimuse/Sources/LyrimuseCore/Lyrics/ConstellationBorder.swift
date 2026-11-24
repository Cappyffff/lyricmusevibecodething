import CoreGraphics
import Foundation

public enum ConstellationBorder {
    public static let baseThickness: CGFloat = 34
    public static let energyThickness: CGFloat = 26
    public static let spikeThickness: CGFloat = 64
    public static let minimumThickness: CGFloat = 6
    public static let idleBandCount = RealAudioSpectrum.bandCount

    public struct Wave: Equatable, Sendable {
        public let band: Int
        public let cycles: Double
        public let speed: Double
        public let phase: Double
        public let weight: Double

        public init(band: Int, cycles: Double, speed: Double, phase: Double, weight: Double) {
            self.band = band
            self.cycles = cycles
            self.speed = speed
            self.phase = phase
            self.weight = weight
        }
    }

    public static let waves: [Wave] = [
        Wave(band: 0, cycles: 1, speed: 0.07, phase: 0.00, weight: 0.42),
        Wave(band: 2, cycles: 2, speed: -0.11, phase: 0.37, weight: 0.33),
        Wave(band: 4, cycles: 3, speed: 0.17, phase: 0.71, weight: 0.25),
    ]

    public static var maximumThickness: CGFloat {
        baseThickness + energyThickness + spikeThickness
    }

    /// Breathing levels for when no real audio is available: each band drifts on its own period, so the
    /// border keeps moving, it just is not following the music.
    public static func idleLevels(nowSeconds: Double) -> [Double] {
        (0..<idleBandCount).map { band in
            let period: Double = 5.5 + Double(band) * 1.7
            let phase: Double = Double(band) * 0.6
            let swing: Double = sin(2 * .pi * nowSeconds / period + phase)
            return 0.22 + 0.1 * swing
        }
    }

    /// Thickness at `u` (0…1) along one edge. `levels` are 0…1 band levels; missing or non-finite values count as 0.
    public static func thickness(at u: Double, nowSeconds: Double, levels: [Double]) -> CGFloat {
        let safe: [Double] = levels.map { $0.isFinite ? min(1, max(0, $0)) : 0 }
        let energy: Double = safe.isEmpty ? 0 : safe.reduce(0, +) / Double(safe.count)

        var wobble: Double = 0
        var weightSum: Double = 0
        for wave in waves {
            let level: Double = wave.band < safe.count ? safe[wave.band] : 0
            let turns: Double = wave.cycles * u + wave.speed * nowSeconds + wave.phase
            let swing: Double = sin(2 * .pi * turns)
            wobble += wave.weight * level * swing
            weightSum += wave.weight
        }
        if weightSum > 0 { wobble /= weightSum }

        let steady: CGFloat = baseThickness + energyThickness * CGFloat(energy)
        let spike: CGFloat = spikeThickness * CGFloat(wobble)
        return min(max(steady + spike, minimumThickness), maximumThickness)
    }

    /// One edge sampled into `samples + 1` thicknesses, which the view joins into the inner boundary.
    public static func profile(samples: Int, nowSeconds: Double, levels: [Double]) -> [CGFloat] {
        guard samples > 0 else { return [] }
        return (0...samples).map { step in
            thickness(at: Double(step) / Double(samples), nowSeconds: nowSeconds, levels: levels)
        }
    }
}
