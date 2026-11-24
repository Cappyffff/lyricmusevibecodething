import Foundation
import LyrimuseCore
import SwiftUI

enum ConstellationStyle {
    static let backgroundCenter = Color(red: 0.045, green: 0.035, blue: 0.105)
    static let backgroundEdge = Color(red: 0.006, green: 0.006, blue: 0.019)
    static let line = Color.white.opacity(0.42)
    static let activeText = Color.white
    static let activeFontSize: CGFloat = 34
    static let pastFontSize: CGFloat = 12
    static let activeStarRadius: CGFloat = 16
    static let pastStarRadius: CGFloat = 6
    static let haloRadius: CGFloat = 26
    static let labelGap: CGFloat = 16
    static let dustCount = 90
    static let starWaist: CGFloat = 0.17
    static let borderFallback = Color(red: 0.98, green: 0.45, blue: 0.22)
}

struct ConstellationView: View {
    let lineKey: String
    let words: [SyncedLyricWord]
    let plainText: String?
    let nowMs: () -> Int
    let paused: Bool
    var levels: [Double] = []
    var accent: Color?
    var palette: [ConstellationSwatch] = []
    var borderEnabled = true

    @State private var points: [CGPoint] = []
    @State private var dust: [ConstellationDust] = []
    @State private var emphasis: [CGFloat] = []

    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size
            TimelineView(.animation(minimumInterval: nil, paused: paused)) { timeline in
                let now = nowMs()
                let seconds = timeline.date.timeIntervalSinceReferenceDate
                Canvas(opaque: true, colorMode: .nonLinear, rendersAsynchronously: false) { context, _ in
                    draw(in: &context, size: size, nowMs: now, seconds: seconds)
                }
            }
            .onAppear { layOut(in: size) }
            .onChange(of: size) { _, next in layOut(in: next) }
            .onChange(of: lineKey) { _, _ in layOut(in: size) }
            .onChange(of: words.count) { _, _ in layOut(in: size) }
        }
        .background(ConstellationStyle.backgroundEdge)
        .accessibilityElement()
        .accessibilityLabel(Text(verbatim: plainText ?? ""))
    }

    private func layOut(in size: CGSize) {
        let made = Self.layout(lineKey: lineKey, count: words.count, size: size)
        if made != points { points = made }
        let grains = Self.dustGrains(in: size)
        if grains != dust { dust = grains }
        let weights = Self.emphasisWeights(lineKey: lineKey, words: words)
        if weights != emphasis { emphasis = weights }
    }

    private static func emphasisWeights(lineKey: String, words: [SyncedLyricWord]) -> [CGFloat] {
        let seed = ConstellationLayout.seed(for: lineKey)
        return words.enumerated().map { index, word in
            ConstellationLayout.emphasis(durationMs: word.durationMs, index: index, seed: seed)
        }
    }

    private static func dustGrains(in size: CGSize) -> [ConstellationDust] {
        ConstellationLayout.dust(count: ConstellationStyle.dustCount,
                                 seed: ConstellationLayout.seed(for: "dust"), size: size)
    }

    private static func layout(lineKey: String, count: Int, size: CGSize) -> [CGPoint] {
        ConstellationLayout.points(count: count, seed: ConstellationLayout.seed(for: lineKey),
                                   canvas: ConstellationLayout.Canvas(size: size))
    }

    private func draw(in context: inout GraphicsContext, size: CGSize, nowMs: Int, seconds: Double) {
        drawBackdrop(in: &context, size: size)
        drawBorder(in: &context, size: size, seconds: seconds)
        guard !words.isEmpty else {
            drawPlainFallback(in: &context, size: size)
            return
        }

        let points = self.points.count == words.count
            ? self.points
            : Self.layout(lineKey: lineKey, count: words.count, size: size)
        let weights = emphasis.count == words.count ? emphasis : Self.emphasisWeights(lineKey: lineKey, words: words)

        let lit = nowMs + ConstellationReveal.leadMs
        let reveal = ConstellationReveal.at(nowMs: lit, words: words)
        guard let active = reveal.activeIndex else { return }

        drawEdges(in: &context, points: points, through: active, nowMs: lit)
        for index in 0...active {
            drawNode(in: &context, size: size, index: index, active: active, point: points[index],
                     emphasis: weights[index], nowMs: lit)
        }
    }

    private func drawBackdrop(in context: inout GraphicsContext, size: CGSize) {
        let rect = CGRect(origin: .zero, size: size)
        let colors: [Color] = [ConstellationStyle.backgroundCenter, ConstellationStyle.backgroundEdge]
        let centerX: CGFloat = size.width * 0.5
        let centerY: CGFloat = size.height * 0.42
        let endRadius: CGFloat = max(size.width, size.height) * 0.72
        let shading: GraphicsContext.Shading = .radialGradient(
            Gradient(colors: colors),
            center: CGPoint(x: centerX, y: centerY),
            startRadius: 0,
            endRadius: endRadius)
        context.fill(Path(rect), with: shading)

        for grain in dust.isEmpty ? Self.dustGrains(in: size) : dust {
            let radius: CGFloat = grain.radius
            let box = CGRect(x: grain.point.x - radius, y: grain.point.y - radius,
                             width: radius * 2, height: radius * 2)
            context.fill(Path(ellipseIn: box), with: .color(.white.opacity(grain.opacity)))
        }
    }

    private func drawBorder(in context: inout GraphicsContext, size: CGSize, seconds: Double) {
        guard borderEnabled, size.width > 0, size.height > 0 else { return }
        let beat: [Double] = levels.isEmpty ? ConstellationBorder.idleLevels(nowSeconds: seconds) : levels
        let ring = borderRing(size: size)
        guard ring.count > 1 else { return }
        let stops = borderStops()

        var lit: [Double] = []
        lit.reserveCapacity(ring.count)
        for sample in ring {
            lit.append(ConstellationBorder.intensity(at: sample.loop, nowSeconds: seconds, levels: beat))
        }

        // One continuous ring of quads: neighbours share an edge, so nothing double-blends and the
        // corners cannot show a brighter patch where two bands would have overlapped.
        for index in 0..<(ring.count - 1) {
            let here = lit[index]
            let next = lit[index + 1]
            guard max(here, next) >= ConstellationBorder.visibleIntensity else { continue }
            let reach = ConstellationBorder.maximumThickness
            let colour = borderColour(at: ring[index].loop, stops: stops)
            drawRingQuad(in: &context, from: ring[index], to: ring[index + 1],
                         depthFrom: reach * CGFloat(here), depthTo: reach * CGFloat(next),
                         inner: 0, outer: 0.62, colour: colour, alpha: 0.98 * min(1, max(here, next)))
            drawRingQuad(in: &context, from: ring[index], to: ring[index + 1],
                         depthFrom: reach * CGFloat(here), depthTo: reach * CGFloat(next),
                         inner: 0.62, outer: 1, colour: colour, alpha: 0.34 * min(1, max(here, next)))
        }
    }

    private struct RingSample {
        let point: CGPoint
        let inward: CGSize
        let loop: Double
    }

    /// The window edge walked as one loop, corners included twice so the two sides meet exactly.
    private func borderRing(size: CGSize) -> [RingSample] {
        let corners: [CGPoint] = [
            CGPoint(x: 0, y: 0), CGPoint(x: size.width, y: 0),
            CGPoint(x: size.width, y: size.height), CGPoint(x: 0, y: size.height),
        ]
        let inwards: [CGSize] = [
            CGSize(width: 0, height: 1), CGSize(width: -1, height: 0),
            CGSize(width: 0, height: -1), CGSize(width: 1, height: 0),
        ]
        var ring: [RingSample] = []
        for edge in 0..<4 {
            let from = corners[edge]
            let to = corners[(edge + 1) % 4]
            let span = max(abs(to.x - from.x), abs(to.y - from.y))
            let steps = max(2, Int((span / 14).rounded()))
            for step in 0...steps {
                let fraction = Double(step) / Double(steps)
                let point = CGPoint(x: from.x + (to.x - from.x) * CGFloat(fraction),
                                    y: from.y + (to.y - from.y) * CGFloat(fraction))
                let loop = ConstellationBorder.loopPosition(edge: edge, fraction: fraction,
                                                            width: size.width, height: size.height)
                ring.append(RingSample(point: point, inward: inwards[edge], loop: loop))
            }
        }
        if let first = ring.first { ring.append(first) }
        return ring
    }

    private func drawRingQuad(in context: inout GraphicsContext, from: RingSample, to: RingSample,
                              depthFrom: CGFloat, depthTo: CGFloat, inner: CGFloat, outer: CGFloat,
                              colour: Color, alpha: Double) {
        func offset(_ sample: RingSample, _ depth: CGFloat) -> CGPoint {
            CGPoint(x: sample.point.x + sample.inward.width * depth,
                    y: sample.point.y + sample.inward.height * depth)
        }
        var path = Path()
        path.move(to: offset(from, depthFrom * inner))
        path.addLine(to: offset(to, depthTo * inner))
        path.addLine(to: offset(to, depthTo * outer))
        path.addLine(to: offset(from, depthFrom * outer))
        path.closeSubpath()
        context.fill(path, with: .color(colour.opacity(alpha)))
    }

    /// Colours taken from the cover art, walked around the loop so the ring is not one flat tint.
    private func borderStops() -> [ConstellationSwatch] {
        if palette.count >= 2 { return palette }
        if let accent {
            let parts = NSColor(accent).usingColorSpace(.sRGB)
            let red = Double(parts?.redComponent ?? 1)
            let green = Double(parts?.greenComponent ?? 0.45)
            let blue = Double(parts?.blueComponent ?? 0.22)
            let one = ConstellationSwatch(red: red, green: green, blue: blue, hue: 0)
            return [one, one]
        }
        let fallback = ConstellationSwatch(red: 0.98, green: 0.45, blue: 0.22, hue: 0)
        return [fallback, fallback]
    }

    /// Blends between neighbouring stops and wraps back to the first, so the ring has no seam and
    /// no hard edge where one cover colour gives way to the next.
    private func borderColour(at loop: Double, stops: [ConstellationSwatch]) -> Color {
        guard let first = stops.first else { return ConstellationStyle.borderFallback }
        guard stops.count > 1 else { return Color(red: first.red, green: first.green, blue: first.blue) }
        let scaled = loop * Double(stops.count)
        let index = min(stops.count - 1, max(0, Int(scaled)))
        let next = stops[(index + 1) % stops.count]
        let here = stops[index]
        let blend = min(1, max(0, scaled - Double(index)))
        let eased = blend * blend * (3 - 2 * blend)
        return Color(red: here.red + (next.red - here.red) * eased,
                     green: here.green + (next.green - here.green) * eased,
                     blue: here.blue + (next.blue - here.blue) * eased)
    }

    private func drawPlainFallback(in context: inout GraphicsContext, size: CGSize) {
        guard let plainText, !plainText.isEmpty else { return }
        var resolved = context.resolve(Text(verbatim: plainText).font(.system(size: 22, weight: .semibold)))
        resolved.shading = .color(ConstellationStyle.activeText)
        context.draw(resolved, at: CGPoint(x: size.width / 2, y: size.height / 2), anchor: .center)
    }

    private func drawEdges(in context: inout GraphicsContext, points: [CGPoint], through active: Int, nowMs: Int) {
        guard active >= 0, points.count > 1 else { return }
        for index in 0..<min(active + 1, points.count - 1) {
            let progress = ConstellationReveal.edgeProgress(index: index, nowMs: nowMs, words: words)
            guard progress > 0 else { continue }
            let from = points[index]
            let to = points[index + 1]
            let drawn = CGFloat(progress)
            let head = CGPoint(x: from.x + (to.x - from.x) * drawn,
                               y: from.y + (to.y - from.y) * drawn)
            var path = Path()
            path.move(to: from)
            path.addLine(to: head)
            context.stroke(path, with: .color(ConstellationStyle.line), lineWidth: 1)
        }
    }

    private func drawNode(in context: inout GraphicsContext, size: CGSize, index: Int, active: Int,
                          point: CGPoint, emphasis: CGFloat, nowMs: Int) {
        let appear = ease(ConstellationReveal.appearProgress(index: index, nowMs: nowMs, words: words))
        guard appear > 0 else { return }
        let settle = index == active ? 0 : ease(ConstellationReveal.settleProgress(index: index, nowMs: nowMs, words: words))

        let grown: CGFloat = CGFloat(appear) * emphasis
        let baseStar: CGFloat = mix(ConstellationStyle.activeStarRadius, ConstellationStyle.pastStarRadius, settle)
        let starRadius: CGFloat = baseStar * grown
        let baseFont: CGFloat = mix(ConstellationStyle.activeFontSize, ConstellationStyle.pastFontSize, settle)
        let fontSize: CGFloat = baseFont * emphasis
        let textAlpha: Double = blend(1, 0.4, settle) * appear
        let starAlpha: Double = blend(1, 0.55, settle) * appear

        if settle < 1 {
            let halo: CGFloat = ConstellationStyle.haloRadius * grown
            let box = CGRect(x: point.x - halo, y: point.y - halo, width: halo * 2, height: halo * 2)
            let haloAlpha: Double = 0.34 * (1 - settle) * appear
            context.stroke(Path(ellipseIn: box), with: .color(.white.opacity(haloAlpha)), lineWidth: 1)
        }

        let starInk: Color = index == active ? (accent ?? .white) : .white
        context.fill(starPath(center: point, radius: starRadius),
                     with: .color(starInk.opacity(starAlpha)))

        let label: String = words[index].text.trimmingCharacters(in: .whitespaces)
        let weight: Font.Weight = index == active ? .bold : .medium
        let font: Font = .system(size: fontSize, weight: weight)
        var resolved = context.resolve(Text(verbatim: label).font(font))
        resolved.shading = .color(.white.opacity(textAlpha))
        let measured: CGSize = resolved.measure(in: size)
        let above: CGFloat = point.y - starRadius - ConstellationStyle.labelGap
        let fitsAbove: Bool = above - measured.height >= 0
        let anchor: UnitPoint = fitsAbove ? .bottom : .top
        let below: CGFloat = point.y + starRadius + ConstellationStyle.labelGap
        let labelY: CGFloat = fitsAbove ? above : below
        context.draw(resolved, at: CGPoint(x: point.x, y: labelY), anchor: anchor)
    }

    private func starPath(center: CGPoint, radius: CGFloat) -> Path {
        let waist: CGFloat = radius * ConstellationStyle.starWaist
        let top = CGPoint(x: center.x, y: center.y - radius)
        let right = CGPoint(x: center.x + radius, y: center.y)
        let bottom = CGPoint(x: center.x, y: center.y + radius)
        let left = CGPoint(x: center.x - radius, y: center.y)
        let topRight = CGPoint(x: center.x + waist, y: center.y - waist)
        let bottomRight = CGPoint(x: center.x + waist, y: center.y + waist)
        let bottomLeft = CGPoint(x: center.x - waist, y: center.y + waist)
        let topLeft = CGPoint(x: center.x - waist, y: center.y - waist)
        var path = Path()
        path.move(to: top)
        path.addQuadCurve(to: right, control: topRight)
        path.addQuadCurve(to: bottom, control: bottomRight)
        path.addQuadCurve(to: left, control: bottomLeft)
        path.addQuadCurve(to: top, control: topLeft)
        path.closeSubpath()
        return path
    }

    private func mix(_ from: CGFloat, _ to: CGFloat, _ amount: Double) -> CGFloat {
        from + (to - from) * CGFloat(amount)
    }

    private func blend(_ from: Double, _ to: Double, _ amount: Double) -> Double {
        from + (to - from) * amount
    }

    private func ease(_ value: Double) -> Double {
        let remaining = 1 - min(max(value, 0), 1)
        return 1 - remaining * remaining * remaining
    }
}
