import CoreGraphics
import Foundation

public enum ConstellationLayout {
    public static let stepRange: ClosedRange<CGFloat> = 80...120
    public static let turnRange: ClosedRange<CGFloat> = 30...75
    public static let minSeparation: CGFloat = 64
    public static let defaultMargin: CGFloat = 96

    public struct Canvas: Equatable, Sendable {
        public var size: CGSize
        public var margin: CGFloat

        public init(size: CGSize, margin: CGFloat = ConstellationLayout.defaultMargin) {
            self.size = size
            self.margin = margin
        }

        public var inner: CGRect {
            let capped = max(0, min(margin, min(size.width, size.height) / 4))
            let rect = CGRect(origin: .zero, size: size).insetBy(dx: capped, dy: capped)
            guard rect.width > 0, rect.height > 0 else {
                return CGRect(x: size.width / 2, y: size.height / 2, width: 0, height: 0)
            }
            return rect
        }
    }

    public static func seed(for key: String) -> UInt64 {
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        for byte in key.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x0000_0100_0000_01B3
        }
        return hash == 0 ? 0x9E37_79B9_7F4A_7C15 : hash
    }

    public static func separation(count: Int, canvas: Canvas) -> CGFloat {
        let inner = canvas.inner
        guard count > 1, inner.width > 0, inner.height > 0 else { return 0 }
        return min(minSeparation * densityScale(count: count, inner: inner), min(inner.width, inner.height) / 2)
    }

    public static func points(count: Int, seed: UInt64, canvas: Canvas) -> [CGPoint] {
        guard count > 0 else { return [] }
        let inner = canvas.inner
        guard inner.width > 0, inner.height > 0 else {
            return Array(repeating: CGPoint(x: canvas.size.width / 2, y: canvas.size.height / 2), count: count)
        }
        var attemptScale = densityScale(count: count, inner: inner)
        var best: (points: [CGPoint], spread: CGFloat)?
        for attempt in 0..<4 {
            if attempt > 0 { attemptScale *= 0.75 }
            let walked = walk(count: count, seed: seed, inner: inner, scale: attemptScale)
            if walked.spread >= walked.separation { return walked.points }
            if let current = best, walked.spread <= current.spread { continue }
            best = (walked.points, walked.spread)
        }
        return best?.points ?? []
    }

    private static func densityScale(count: Int, inner: CGRect) -> CGFloat {
        guard count > 1 else { return 1 }
        let room = (max(inner.width * inner.height, 1) / CGFloat(count)).squareRoot() * 0.78
        return min(max(room / minSeparation, 0.3), 1)
    }

    private static func walk(count: Int, seed: UInt64, inner: CGRect,
                             scale: CGFloat) -> (points: [CGPoint], separation: CGFloat, spread: CGFloat) {
        var rng = SeededRandom(seed: seed)
        let separation = min(minSeparation * scale, min(inner.width, inner.height) / 2)
        let shortest = stepRange.lowerBound * scale
        let longest = stepRange.upperBound * scale
        var placed: [CGPoint] = []
        placed.reserveCapacity(count)
        placed.append(CGPoint(x: inner.minX + inner.width * CGFloat(rng.double(0.22, 0.78)),
                              y: inner.minY + inner.height * CGFloat(rng.double(0.22, 0.78))))

        var heading = CGFloat(rng.double(0, 2 * .pi))
        var turnSign: CGFloat = rng.unit() < 0.5 ? -1 : 1

        while placed.count < count {
            let previous = placed[placed.count - 1]
            var accepted: (point: CGPoint, heading: CGFloat)?

            for attempt in 0..<12 {
                let turn = CGFloat(rng.double(Double(turnRange.lowerBound), Double(turnRange.upperBound)))
                let sign = attempt.isMultiple(of: 2) ? turnSign : -turnSign
                let candidateHeading = heading + sign * turn * .pi / 180
                let step = CGFloat(rng.double(Double(shortest), Double(longest)))
                let candidate = CGPoint(x: previous.x + cos(candidateHeading) * step,
                                        y: previous.y + sin(candidateHeading) * step)
                guard inner.contains(candidate), clearance(of: candidate, from: placed) >= separation else { continue }
                accepted = (candidate, candidateHeading)
                break
            }

            if accepted == nil {
                accepted = sweep(from: previous, heading: heading, inner: inner, placed: placed,
                                 shortest: shortest, longest: longest)
            }

            guard let next = accepted else { break }
            heading = next.heading
            turnSign = -turnSign
            placed.append(next.point)
        }

        while placed.count < count {
            placed.append(placed.last ?? CGPoint(x: inner.midX, y: inner.midY))
        }
        return (placed, separation, spread(of: placed))
    }

    private static func spread(of points: [CGPoint]) -> CGFloat {
        guard points.count > 1 else { return .greatestFiniteMagnitude }
        var smallest = CGFloat.greatestFiniteMagnitude
        for index in 1..<points.count {
            for other in 0..<index {
                smallest = min(smallest, hypot(points[index].x - points[other].x, points[index].y - points[other].y))
            }
        }
        return smallest
    }

    private static func sweep(from previous: CGPoint, heading: CGFloat, inner: CGRect, placed: [CGPoint],
                              shortest: CGFloat, longest: CGFloat) -> (point: CGPoint, heading: CGFloat)? {
        var best: (point: CGPoint, heading: CGFloat, clearance: CGFloat)?
        let steps: [CGFloat] = [longest, (shortest + longest) / 2, shortest]
        for turnIndex in 0..<48 {
            let candidateHeading = heading + CGFloat(turnIndex) * (2 * .pi / 48)
            for step in steps {
                let raw = CGPoint(x: previous.x + cos(candidateHeading) * step,
                                  y: previous.y + sin(candidateHeading) * step)
                let candidate = CGPoint(x: min(max(raw.x, inner.minX), inner.maxX),
                                        y: min(max(raw.y, inner.minY), inner.maxY))
                let room = clearance(of: candidate, from: placed)
                if let current = best, room <= current.clearance { continue }
                best = (candidate, candidateHeading, room)
            }
        }
        guard let best else { return nil }
        return (best.point, best.heading)
    }

    public static let emphasisReferenceMs = 420
    public static let emphasisRange: ClosedRange<CGFloat> = 0.85...1.6
    public static let emphasisJitter: CGFloat = 0.08

    public static func emphasis(durationMs: Int, index: Int, seed: UInt64) -> CGFloat {
        let reference = Double(emphasisReferenceMs)
        let held = max(Double(durationMs), 1) / reference
        let byDuration = CGFloat(pow(held, 0.35))
        var rng = SeededRandom(seed: seed &+ UInt64(max(index, 0)) &* 0x9E37_79B9)
        let jitter = 1 + CGFloat(rng.double(Double(-emphasisJitter), Double(emphasisJitter)))
        let scaled = min(max(byDuration, emphasisRange.lowerBound), emphasisRange.upperBound) * jitter
        return min(max(scaled, emphasisRange.lowerBound * (1 - emphasisJitter)),
                   emphasisRange.upperBound * (1 + emphasisJitter))
    }

    public static func dust(count: Int, seed: UInt64, size: CGSize) -> [ConstellationDust] {
        guard count > 0, size.width > 0, size.height > 0 else { return [] }
        var rng = SeededRandom(seed: seed &+ 0x5DEE_CE66)
        var grains: [ConstellationDust] = []
        grains.reserveCapacity(count)
        for _ in 0..<count {
            grains.append(ConstellationDust(
                point: CGPoint(x: size.width * CGFloat(rng.unit()), y: size.height * CGFloat(rng.unit())),
                radius: CGFloat(rng.double(0.5, 1.4)),
                opacity: rng.double(0.08, 0.34)))
        }
        return grains
    }

    private static func clearance(of candidate: CGPoint, from placed: [CGPoint]) -> CGFloat {
        var smallest = CGFloat.greatestFiniteMagnitude
        for point in placed {
            smallest = min(smallest, hypot(candidate.x - point.x, candidate.y - point.y))
        }
        return smallest
    }
}

public struct ConstellationDust: Equatable, Sendable {
    public let point: CGPoint
    public let radius: CGFloat
    public let opacity: Double

    public init(point: CGPoint, radius: CGFloat, opacity: Double) {
        self.point = point
        self.radius = radius
        self.opacity = opacity
    }
}

public struct ConstellationReveal: Equatable, Sendable {
    public static let appearMs = 180
    public static let settleMs = 320

    public let revealedCount: Int
    public let activeIndex: Int?

    public init(revealedCount: Int, activeIndex: Int?) {
        self.revealedCount = revealedCount
        self.activeIndex = activeIndex
    }

    public static func at(nowMs: Int, words: [SyncedLyricWord]) -> ConstellationReveal {
        guard !words.isEmpty else { return ConstellationReveal(revealedCount: 0, activeIndex: nil) }
        var revealed = 0
        for word in words where word.startMs <= nowMs { revealed += 1 }
        return ConstellationReveal(revealedCount: revealed, activeIndex: revealed > 0 ? revealed - 1 : nil)
    }

    public static func edgeProgress(index: Int, nowMs: Int, words: [SyncedLyricWord]) -> Double {
        guard index >= 0, index + 1 < words.count else { return 0 }
        let from = words[index].startMs
        let to = words[index + 1].startMs
        guard to > from else { return nowMs >= to ? 1 : 0 }
        return clamp(Double(nowMs - from) / Double(to - from))
    }

    public static func appearProgress(index: Int, nowMs: Int, words: [SyncedLyricWord]) -> Double {
        guard index >= 0, index < words.count else { return 0 }
        let since = nowMs - words[index].startMs
        guard since >= 0 else { return 0 }
        return clamp(Double(since) / Double(appearMs))
    }

    public static func settleProgress(index: Int, nowMs: Int, words: [SyncedLyricWord]) -> Double {
        guard index >= 0, index + 1 < words.count else { return 0 }
        let since = nowMs - words[index + 1].startMs
        guard since >= 0 else { return 0 }
        return clamp(Double(since) / Double(settleMs))
    }

    private static func clamp(_ value: Double) -> Double { min(max(value, 0), 1) }
}
