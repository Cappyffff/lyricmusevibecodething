import CoreGraphics
import Foundation
import LyrimuseCore

func runConstellationTests() {
    checkConstellationLayout()
    checkConstellationReveal()
    checkConstellationBorder()
    checkConstellationWiring()
}

private func checkConstellationBorder() {
    print("\n== constellation: music-driven border ==")
    typealias B = ConstellationBorder

    let loud: [Double] = [1, 1, 1, 1, 1]
    let quiet: [Double] = [0, 0, 0, 0, 0]

    expectEqual(B.loopDistance(0.05, 0.95) < 0.11, true, "constellation border: the perimeter wraps, so the ends are neighbours")
    expectEqual(B.loopDistance(0.1, 0.6), 0.5, "constellation border: opposite sides are half a loop apart")

    var outOfRange: [String] = []
    let messy: [[Double]] = [[], [0.5], loud, quiet, [-4, 9, .nan, .infinity, 0.3], [0.2, 0.9, 0.1]]
    for levels in messy {
        for tick in 0..<200 {
            let seconds: Double = Double(tick) * 0.41 - 15
            for step in 0...20 {
                let p: Double = Double(step) / 20
                let lit = B.intensity(at: p, nowSeconds: seconds, levels: levels)
                if !(lit >= 0 && lit <= 1) { outOfRange.append("\(levels.count) bands t=\(seconds) p=\(p): \(lit)") }
            }
        }
    }
    expectEqual(outOfRange.first, nil, "constellation border: brightness stays within 0…1 for any levels")

    expectEqual(B.intensity(at: 0.3, nowSeconds: 7, levels: loud),
                B.intensity(at: 0.3, nowSeconds: 7, levels: loud),
                "constellation border: same moment and position is the same brightness")

    func brightest(_ levels: [Double], _ seconds: Double) -> Double {
        (0...240).map { B.intensity(at: Double($0) / 240, nowSeconds: seconds, levels: levels) }.max() ?? 0
    }
    expectEqual(brightest(loud, 3) > brightest(quiet, 3), true, "constellation border: louder burns brighter")
    expectEqual(brightest(quiet, 3) < 0.2, true, "constellation border: silence leaves only a trace")

    func peakPosition(_ seconds: Double) -> Double {
        var best = (position: 0.0, lit: -1.0)
        for step in 0...240 {
            let p = Double(step) / 240
            let lit = B.intensity(at: p, nowSeconds: seconds, levels: [1, 0, 0, 0, 0])
            if lit > best.lit { best = (p, lit) }
        }
        return best.position
    }
    expectEqual(peakPosition(0) != peakPosition(6), true, "constellation border: the bright patch travels around the loop")

    let flat = (0...60).map { B.intensity(at: Double($0) / 60, nowSeconds: 2, levels: [0.5, 0.5, 0.5, 0.5, 0.5]) }
    expectEqual(Set(flat.map { ($0 * 1000).rounded() }).count > 1, true,
                "constellation border: the inner edge ripples rather than sitting flat")

    let corners = (0..<4).map { B.loopPosition(edge: $0, fraction: 0, width: 800, height: 400) }
    expectEqual(corners.sorted() == corners && corners[0] == 0, true,
                "constellation border: the four edges run in order around one loop")
    expectEqual(B.loopPosition(edge: 3, fraction: 1, width: 800, height: 400) < 0.001, true,
                "constellation border: the end of the last edge meets the start of the first")

    let idle = B.idleLevels(nowSeconds: 9)
    expectEqual(idle.count, RealAudioSpectrum.bandCount, "constellation border: idle levels fill all five bands")
    expectEqual(idle.allSatisfy { $0 >= 0 && $0 <= 1 }, true, "constellation border: breathing levels stay within 0…1")
    expectEqual(B.idleLevels(nowSeconds: 9) == B.idleLevels(nowSeconds: 14), false,
                "constellation border: the glow still drifts without audio")

    let art: [UInt8] = (0..<256).flatMap { index -> [UInt8] in
        index % 2 == 0 ? [220, 40, 30, 255] : [30, 60, 210, 255]
    }
    let swatches = ConstellationPalette.swatches(premultipliedRGBA: art)
    expectEqual(swatches.count, 2, "constellation palette: two strong hues come back as two stops")
    expectEqual(swatches.map(\.hue) == swatches.map(\.hue).sorted(), true,
                "constellation palette: stops are ordered around the colour wheel")
    expectEqual(ConstellationPalette.swatches(premultipliedRGBA: [8, 8, 8, 255]).isEmpty, true,
                "constellation palette: a near-black sleeve yields nothing rather than mud")
}

private func minimumDistance(_ points: [CGPoint]) -> CGFloat {
    guard points.count > 1 else { return .greatestFiniteMagnitude }
    var smallest = CGFloat.greatestFiniteMagnitude
    for index in 1..<points.count {
        for other in 0..<index {
            smallest = min(smallest, hypot(points[index].x - points[other].x, points[index].y - points[other].y))
        }
    }
    return smallest
}

private func checkConstellationLayout() {
    print("\n== constellation: node layout ==")
    typealias L = ConstellationLayout
    let phrase = "i never knew somebody like you were too close to the stars"
    let seed = L.seed(for: phrase)

    expectEqual(L.points(count: 0, seed: seed, canvas: L.Canvas(size: CGSize(width: 1000, height: 620))), [],
                "constellation layout: no words, no stars")

    let canvas = L.Canvas(size: CGSize(width: 1512, height: 945))
    let once = L.points(count: 12, seed: seed, canvas: canvas)
    let twice = L.points(count: 12, seed: seed, canvas: canvas)
    expectEqual(once, twice, "constellation layout: same line and canvas lays out identically twice")
    expectEqual(once.count, 12, "constellation layout: one star per word")
    expectEqual(L.points(count: 12, seed: L.seed(for: "the road runs now"), canvas: canvas) == once, false,
                "constellation layout: a different line gives a different shape")

    let sizes = [CGSize(width: 1000, height: 620), CGSize(width: 1512, height: 945),
                 CGSize(width: 3456, height: 2160), CGSize(width: 600, height: 360)]
    let roomy = [CGSize(width: 1512, height: 945), CGSize(width: 3456, height: 2160)]
    var outside: [String] = []
    var crowded: [String] = []
    var belowFloor: [String] = []
    for size in sizes {
        let canvas = L.Canvas(size: size)
        let inner = canvas.inner
        for count in [1, 2, 3, 5, 8, 14, 20, 25] {
            let points = L.points(count: count, seed: seed, canvas: canvas)
            let label = "\(Int(size.width))x\(Int(size.height)) \(count) words"
            if points.contains(where: { !inner.contains($0) }) { outside.append(label) }
            guard count > 1 else { continue }
            let wanted: CGFloat = L.separation(count: count, canvas: canvas)
            let closest: CGFloat = minimumDistance(points)
            let lowest: CGFloat = wanted * 0.75 * 0.75 * 0.75
            if closest < lowest { belowFloor.append("\(label): closest \(Int(closest))") }
            let strict: CGFloat = wanted * 0.999
            if roomy.contains(size), closest < strict {
                crowded.append("\(label): closest \(Int(closest)) < \(Int(wanted))")
            }
        }
    }
    expectEqual(outside, [], "constellation layout: every star stays inside the margin, never off canvas")
    expectEqual(crowded, [], "constellation layout: on a roomy canvas no two stars are closer than the minimum separation")
    expectEqual(belowFloor, [], "constellation layout: even on a cramped canvas it stays above 0.75^3 of the minimum separation")

    let walked = L.points(count: 8, seed: seed, canvas: canvas)
    var steps: [CGFloat] = []
    for index in 1..<walked.count {
        steps.append(hypot(walked[index].x - walked[index - 1].x, walked[index].y - walked[index - 1].y))
    }
    let shortest: CGFloat = L.stepRange.lowerBound * L.spreadCeiling - 0.5
    let longest: CGFloat = L.stepRange.upperBound * L.spreadCeiling + 0.5
    let paced: Bool = steps.allSatisfy { $0 >= shortest && $0 <= longest }
    expectEqual(paced, true, "constellation layout: a roomy canvas stretches the stride so the run fills it")

    expectEqual(L.separation(count: 25, canvas: L.Canvas(size: CGSize(width: 600, height: 360))) < L.minSeparation, true,
                "constellation layout: too many words for the area narrows the minimum separation")
    expectEqual(L.separation(count: 6, canvas: canvas), L.minSeparation * L.spreadCeiling,
                "constellation layout: a roomy canvas widens the separation to its ceiling")

    let five = L.points(count: 5, seed: seed, canvas: canvas)
    let twelve = L.points(count: 12, seed: seed, canvas: canvas)
    let whole = L.points(count: L.runCapacity, seed: seed, canvas: canvas)
    expectEqual(Array(twelve.prefix(5)), five, "constellation layout: a star never moves once the next word lands")
    expectEqual(Array(whole.prefix(12)), twelve, "constellation layout: the whole run is laid out up front")

    let phraseSeed = L.seed(for: phrase)
    let longWord: CGFloat = L.emphasis(durationMs: 900, index: 3, seed: phraseSeed)
    let shortWord: CGFloat = L.emphasis(durationMs: 300, index: 3, seed: phraseSeed)
    expectEqual(longWord > shortWord, true, "constellation size: at the same index, a longer-held word is larger")
    let held: CGFloat = L.emphasis(durationMs: 1400, index: 0, seed: phraseSeed)
    let reference: CGFloat = L.emphasis(durationMs: 420, index: 0, seed: phraseSeed)
    expectEqual(held > reference, true, "constellation size: a held note beats the reference duration")
    expectEqual(L.emphasis(durationMs: 600, index: 2, seed: phraseSeed),
                L.emphasis(durationMs: 600, index: 2, seed: phraseSeed),
                "constellation size: the same word measures the same every time")
    var weights: [CGFloat] = []
    for index in 0..<24 { weights.append(L.emphasis(durationMs: 400, index: index, seed: phraseSeed)) }
    expectEqual(Set(weights).count > 1, true, "constellation size: equal-duration words still vary, never a uniform row")
    let bound: CGFloat = L.emphasisRange.upperBound * (1 + L.emphasisJitter)
    let floor: CGFloat = L.emphasisRange.lowerBound * (1 - L.emphasisJitter)
    var extremes: [CGFloat] = []
    let durations: [Int] = [1, 50, 420, 5000, 60_000]
    for duration in durations {
        for index in 0..<8 {
            extremes.append(L.emphasis(durationMs: duration, index: index, seed: phraseSeed))
        }
    }
    let withinBounds: Bool = extremes.allSatisfy { $0 >= floor && $0 <= bound }
    expectEqual(withinBounds, true, "constellation size: the shortest and longest words stay within the multiplier bounds")
    expectEqual(weights.allSatisfy { $0 > 0 }, true, "constellation size: the multiplier is always positive")

    let dustSize = CGSize(width: 800, height: 600)
    let dustSeed: UInt64 = L.seed(for: "dust")
    let grains = L.dust(count: 40, seed: dustSeed, size: dustSize)
    expectEqual(grains.count, 40, "constellation backdrop: dust comes out at the requested count")
    expectEqual(grains == L.dust(count: 40, seed: dustSeed, size: dustSize), true,
                "constellation backdrop: dust lands in the same places every time")
    let inCanvas: Bool = grains.allSatisfy { grain in
        grain.point.x >= 0 && grain.point.x <= dustSize.width
            && grain.point.y >= 0 && grain.point.y <= dustSize.height
    }
    expectEqual(inCanvas, true, "constellation backdrop: dust stays on canvas")
}

private func checkConstellationReveal() {
    print("\n== constellation: word reveal ==")
    let words = [
        SyncedLyricWord(text: "the", startMs: 1000, durationMs: 400),
        SyncedLyricWord(text: "road", startMs: 1400, durationMs: 600),
        SyncedLyricWord(text: "runs", startMs: 2000, durationMs: 500),
    ]
    func reveal(_ nowMs: Int) -> ConstellationReveal { ConstellationReveal.at(nowMs: nowMs, words: words) }

    expectEqual(reveal(0).revealedCount, 0, "constellation reveal: before the first word, nothing is drawn")
    expectEqual(reveal(0).activeIndex, nil, "constellation reveal: before the first word there is no active word")
    expectEqual(reveal(1000).revealedCount, 1, "constellation reveal: a word lights the instant its start is reached")
    expectEqual(reveal(1399).activeIndex, 0, "constellation reveal: the active word holds until the next one starts")
    expectEqual(reveal(1400).activeIndex, 1, "constellation reveal: the next word starting moves the active word")
    expectEqual(reveal(9999).revealedCount, 3, "constellation reveal: after the line all three stars remain")
    expectEqual(ConstellationReveal.at(nowMs: 500, words: []).activeIndex, nil, "constellation reveal: no word timings means no active word")

    typealias Reveal = ConstellationReveal
    expectEqual(Reveal.edgeProgress(index: 0, nowMs: 1000, words: words), 0, "constellation edge: at the previous word's start the line has not begun")
    expectEqual(Reveal.edgeProgress(index: 0, nowMs: 1200, words: words), 0.5, "constellation edge: halfway between timestamps the line is half drawn")
    expectEqual(Reveal.edgeProgress(index: 0, nowMs: 1400, words: words), 1, "constellation edge: the line lands exactly as the next word starts")
    expectEqual(Reveal.edgeProgress(index: 0, nowMs: 5000, words: words), 1, "constellation edge: past lines stay connected")
    expectEqual(Reveal.edgeProgress(index: 2, nowMs: 5000, words: words), 0, "constellation edge: nothing is drawn past the last word")
    expectEqual(Reveal.edgeProgress(index: -1, nowMs: 5000, words: words), 0, "constellation edge: an out-of-range index draws nothing")

    expectEqual(Reveal.appearProgress(index: 1, nowMs: 1399, words: words), 0, "constellation appear: nothing before the start time")
    expectEqual(Reveal.appearProgress(index: 1, nowMs: 1400, words: words), 0, "constellation appear: growth starts from zero at the start time")
    expectEqual(Reveal.appearProgress(index: 1, nowMs: 1400 + Reveal.appearMs, words: words), 1,
                "constellation appear: fully grown after appearMs")
    expectEqual(Reveal.appearProgress(index: 1, nowMs: 9999, words: words), 1, "constellation appear: stays full afterwards")

    expectEqual(Reveal.settleProgress(index: 0, nowMs: 1399, words: words), 0, "constellation settle: the active word does not shrink")
    expectEqual(Reveal.settleProgress(index: 0, nowMs: 1400 + Reveal.settleMs / 2, words: words), 0.5,
                "constellation settle: half shrunk settleMs/2 after the next word starts")
    expectEqual(Reveal.settleProgress(index: 0, nowMs: 1400 + Reveal.settleMs, words: words), 1,
                "constellation settle: fully shrunk after settleMs (13pt / 40%)")
    expectEqual(Reveal.settleProgress(index: 2, nowMs: 9999, words: words), 0, "constellation settle: the last word has no successor, so it never shrinks")
}

private func checkConstellationWiring() {
    print("\n== constellation: wiring ==")
    expectEqual(OverlayVisibility.shouldShow(isVisible: true, hiddenForNoLyrics: false, coveredByFullScreen: false,
                                             hideWhenNotPlaying: false, isPlaying: true, hiddenForAd: false,
                                             constellationOpen: true), false,
                "constellation wiring: the floating overlay hides while the window is open, so no line is drawn twice")
    expectEqual(OverlayVisibility.shouldShow(isVisible: true, hiddenForNoLyrics: false, coveredByFullScreen: false,
                                             hideWhenNotPlaying: false, isPlaying: true, hiddenForAd: false), true,
                "constellation wiring: the overlay shows as usual when the window is closed")

    let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
    func source(_ path: String) -> String {
        (try? String(contentsOf: root.appendingPathComponent(path), encoding: .utf8)) ?? ""
    }
    let controller = source("lyrimuse/UI/LyricsOverlayWindowController.swift")
    expectEqual(controller.contains("ConstellationWindowController.shared.$isOpen")
                && controller.contains("constellationOpen: hiddenForConstellation"), true,
                "constellation wiring: the overlay subscribes to the window state and feeds it to the visibility rule")

    expectEqual(window.contains("let wanted: NSWindow.CollectionBehavior = [.fullScreenPrimary]")
                && window.contains("NSWindow.didUpdateNotification"), true,
                "constellation window: collectionBehavior is re-applied each update cycle so the green button shows arrows")
    expectEqual(window.contains("window.toggleFullScreen(nil)"), true,
                "constellation window: opening enters native full screen in its own Space")

    let window = source("lyrimuse/UI/ConstellationWindow.swift")
    expectEqual(window.contains("RealAudioMeter.shared.setListening(self, follow, ignoresSetting: true)"), true,
                "constellation border: the open window requests levels itself, ignoring the notch switch")
    expectEqual(window.contains("coordinator.$artworkAccentColor"), true,
                "constellation border: colour follows the cover accent")
    expectEqual(window.contains("let wanted = windowOpen && borderEnabled"), true,
                "constellation border: turning the border off stops reading audio")
    expectEqual(source("lyrimuse/SettingsView.swift").contains("isOn: $settings.constellationBorder"), true,
                "constellation border: the Constellation section has its own switch")
    expectEqual(source("lyrimuse/UI/ConstellationView.swift").contains("guard borderEnabled,"), true,
                "constellation border: off means it is not drawn")

    let scenes = source("lyrimuse/App.swift")
    expectEqual(scenes.contains("id: ConstellationWindowID.scene"), true, "constellation window: the scene is mounted in the app scene tree")
    expectEqual(source("lyrimuse/MenuBar/MenuBarSceneActions.swift").contains("AppActions.shared.openConstellation"),
                true, "constellation window: the open action is captured in the anchor view")
    expectEqual(source("lyrimuse/SettingsView.swift").contains("AppActions.shared.openConstellation?()"), true,
                "constellation window: the Lyrics display > Constellation section has an open button")
}
