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
}

struct ConstellationView: View {
    let lineKey: String
    let words: [SyncedLyricWord]
    let plainText: String?
    let nowMs: () -> Int
    let paused: Bool

    @State private var points: [CGPoint] = []
    @State private var dust: [ConstellationDust] = []

    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size
            TimelineView(.animation(minimumInterval: nil, paused: paused)) { _ in
                let now = nowMs()
                Canvas(opaque: true, colorMode: .nonLinear, rendersAsynchronously: false) { context, _ in
                    draw(in: &context, size: size, nowMs: now)
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
        let grains = Self.dust(in: size)
        if grains != dust { dust = grains }
    }

    private static func dust(in size: CGSize) -> [ConstellationDust] {
        ConstellationLayout.dust(count: ConstellationStyle.dustCount,
                                 seed: ConstellationLayout.seed(for: "dust"), size: size)
    }

    private static func layout(lineKey: String, count: Int, size: CGSize) -> [CGPoint] {
        ConstellationLayout.points(count: count, seed: ConstellationLayout.seed(for: lineKey),
                                   canvas: ConstellationLayout.Canvas(size: size))
    }

    private func draw(in context: inout GraphicsContext, size: CGSize, nowMs: Int) {
        drawBackdrop(in: &context, size: size)
        guard !words.isEmpty else {
            drawPlainFallback(in: &context, size: size)
            return
        }

        let points = self.points.count == words.count
            ? self.points
            : Self.layout(lineKey: lineKey, count: words.count, size: size)

        let reveal = ConstellationReveal.at(nowMs: nowMs, words: words)
        guard let active = reveal.activeIndex else { return }

        drawEdges(in: &context, points: points, through: active, nowMs: nowMs)
        for index in 0...active {
            drawNode(in: &context, size: size, index: index, active: active, point: points[index], nowMs: nowMs)
        }
    }

    private func drawBackdrop(in context: inout GraphicsContext, size: CGSize) {
        let rect = CGRect(origin: .zero, size: size)
        context.fill(
            Path(rect),
            with: .radialGradient(
                Gradient(colors: [ConstellationStyle.backgroundCenter, ConstellationStyle.backgroundEdge]),
                center: CGPoint(x: size.width * 0.5, y: size.height * 0.42),
                startRadius: 0,
                endRadius: max(size.width, size.height) * 0.72))

        for grain in dust.isEmpty ? Self.dust(in: size) : dust {
            let box = CGRect(x: grain.point.x - grain.radius, y: grain.point.y - grain.radius,
                             width: grain.radius * 2, height: grain.radius * 2)
            context.fill(Path(ellipseIn: box), with: .color(.white.opacity(grain.opacity)))
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
                          point: CGPoint, nowMs: Int) {
        let appear = ease(ConstellationReveal.appearProgress(index: index, nowMs: nowMs, words: words))
        guard appear > 0 else { return }
        let settle = index == active ? 0 : ease(ConstellationReveal.settleProgress(index: index, nowMs: nowMs, words: words))

        let starRadius = mix(ConstellationStyle.activeStarRadius, ConstellationStyle.pastStarRadius, settle) * CGFloat(appear)
        let fontSize = mix(ConstellationStyle.activeFontSize, ConstellationStyle.pastFontSize, settle)
        let textAlpha = blend(1, 0.4, settle) * appear
        let starAlpha = blend(1, 0.55, settle) * appear

        if settle < 1 {
            let halo = ConstellationStyle.haloRadius * CGFloat(appear)
            let box = CGRect(x: point.x - halo, y: point.y - halo, width: halo * 2, height: halo * 2)
            context.stroke(Path(ellipseIn: box),
                           with: .color(.white.opacity(0.34 * (1 - settle) * appear)),
                           lineWidth: 1)
        }

        context.fill(starPath(center: point, radius: starRadius),
                     with: .color(.white.opacity(starAlpha)))

        var resolved = context.resolve(
            Text(verbatim: words[index].text.trimmingCharacters(in: .whitespaces))
                .font(.system(size: fontSize, weight: index == active ? .bold : .medium)))
        resolved.shading = .color(.white.opacity(textAlpha))
        let measured = resolved.measure(in: size)
        let above = point.y - starRadius - ConstellationStyle.labelGap
        let anchor: UnitPoint = above - measured.height >= 0 ? .bottom : .top
        let labelY = anchor == .bottom ? above : point.y + starRadius + ConstellationStyle.labelGap
        context.draw(resolved, at: CGPoint(x: point.x, y: labelY), anchor: anchor)
    }

    private func starPath(center: CGPoint, radius: CGFloat) -> Path {
        let waist = radius * ConstellationStyle.starWaist
        var path = Path()
        path.move(to: CGPoint(x: center.x, y: center.y - radius))
        path.addQuadCurve(to: CGPoint(x: center.x + radius, y: center.y),
                          control: CGPoint(x: center.x + waist, y: center.y - waist))
        path.addQuadCurve(to: CGPoint(x: center.x, y: center.y + radius),
                          control: CGPoint(x: center.x + waist, y: center.y + waist))
        path.addQuadCurve(to: CGPoint(x: center.x - radius, y: center.y),
                          control: CGPoint(x: center.x - waist, y: center.y + waist))
        path.addQuadCurve(to: CGPoint(x: center.x, y: center.y - radius),
                          control: CGPoint(x: center.x - waist, y: center.y - waist))
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
