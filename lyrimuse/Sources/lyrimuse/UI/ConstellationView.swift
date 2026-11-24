import Foundation
import LyrimuseCore
import SwiftUI

enum ConstellationStyle {
    static let backgroundCenter = Color(red: 0.16, green: 0.13, blue: 0.36)
    static let backgroundEdge = Color(red: 0.03, green: 0.03, blue: 0.09)
    static let line = Color.white.opacity(0.42)
    static let activeText = Color.white
    static let activeFontSize: CGFloat = 18
    static let pastFontSize: CGFloat = 13
    static let activeStarRadius: CGFloat = 13
    static let pastStarRadius: CGFloat = 7
    static let haloRadius: CGFloat = 21
    static let labelGap: CGFloat = 14
    static let dustCount = 90
    static let starWaist: CGFloat = 0.17
    static let borderFallback = Color(red: 0.98, green: 0.45, blue: 0.22)
    static let borderSamples = 72
}

struct ConstellationView: View {
    let lineKey: String
    let words: [SyncedLyricWord]
    let plainText: String?
    let nowMs: () -> Int
    let paused: Bool
    var levels: [Double] = []
    var accent: Color?
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

        let reveal = ConstellationReveal.at(nowMs: nowMs, words: words)
        guard let active = reveal.activeIndex else { return }

        drawEdges(in: &context, points: points, through: active, nowMs: nowMs)
        for index in 0...active {
            drawNode(in: &context, size: size, index: index, active: active, point: points[index],
                     emphasis: weights[index], nowMs: nowMs)
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
        let profile = ConstellationBorder.profile(samples: ConstellationStyle.borderSamples,
                                                  nowSeconds: seconds, levels: beat)
        guard profile.count > 1 else { return }
        let tint: Color = accent ?? ConstellationStyle.borderFallback
        let reach: CGFloat = ConstellationBorder.maximumThickness
        drawEdge(in: &context, profile: profile, size: size, tint: tint, reach: reach, edge: .top)
        drawEdge(in: &context, profile: profile, size: size, tint: tint, reach: reach, edge: .bottom)
        drawEdge(in: &context, profile: profile, size: size, tint: tint, reach: reach, edge: .leading)
        drawEdge(in: &context, profile: profile, size: size, tint: tint, reach: reach, edge: .trailing)
    }

    private enum BorderEdge { case top, bottom, leading, trailing }

    private func drawEdge(in context: inout GraphicsContext, profile: [CGFloat], size: CGSize,
                          tint: Color, reach: CGFloat, edge: BorderEdge) {
        let steps = profile.count - 1
        var path = Path()
        for step in 0...steps {
            let fraction: CGFloat = CGFloat(step) / CGFloat(steps)
            let point = borderPoint(edge: edge, fraction: fraction, depth: 0, size: size)
            if step == 0 { path.move(to: point) } else { path.addLine(to: point) }
        }
        for step in stride(from: steps, through: 0, by: -1) {
            let fraction: CGFloat = CGFloat(step) / CGFloat(steps)
            let point = borderPoint(edge: edge, fraction: fraction, depth: profile[step], size: size)
            path.addLine(to: point)
        }
        path.closeSubpath()

        let stops: [Gradient.Stop] = [
            Gradient.Stop(color: tint.opacity(0.92), location: 0),
            Gradient.Stop(color: tint.opacity(0.55), location: 0.16),
            Gradient.Stop(color: tint.opacity(0.14), location: 0.52),
            Gradient.Stop(color: tint.opacity(0), location: 1),
        ]
        let start = borderPoint(edge: edge, fraction: 0.5, depth: 0, size: size)
        let end = borderPoint(edge: edge, fraction: 0.5, depth: reach, size: size)
        context.fill(path, with: .linearGradient(Gradient(stops: stops), startPoint: start, endPoint: end))
    }

    private func borderPoint(edge: BorderEdge, fraction: CGFloat, depth: CGFloat, size: CGSize) -> CGPoint {
        switch edge {
        case .top: return CGPoint(x: size.width * fraction, y: depth)
        case .bottom: return CGPoint(x: size.width * fraction, y: size.height - depth)
        case .leading: return CGPoint(x: depth, y: size.height * fraction)
        case .trailing: return CGPoint(x: size.width - depth, y: size.height * fraction)
        }
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

        context.fill(starPath(center: point, radius: starRadius),
                     with: .color(.white.opacity(starAlpha)))

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
