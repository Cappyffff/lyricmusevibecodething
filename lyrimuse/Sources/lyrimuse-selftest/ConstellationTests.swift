import CoreGraphics
import Foundation
import LyrimuseCore

func runConstellationTests() {
    checkConstellationLayout()
    checkConstellationReveal()
    checkConstellationWiring()
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
    print("\n== 星座:节点布点 ==")
    typealias L = ConstellationLayout
    let phrase = "i never knew somebody like you were too close to the stars"
    let seed = L.seed(for: phrase)

    expectEqual(L.points(count: 0, seed: seed, canvas: L.Canvas(size: CGSize(width: 1000, height: 620))), [],
                "星座布点: 没有词就没有星")

    let canvas = L.Canvas(size: CGSize(width: 1512, height: 945))
    let once = L.points(count: 12, seed: seed, canvas: canvas)
    let twice = L.points(count: 12, seed: seed, canvas: canvas)
    expectEqual(once, twice, "星座布点: 同一句同一块画布,两次摆出来逐点一致")
    expectEqual(once.count, 12, "星座布点: 每个词各有一颗星")
    expectEqual(L.points(count: 12, seed: L.seed(for: "the road runs now"), canvas: canvas) == once, false,
                "星座布点: 换一句就是另一个形状")

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
            let label = "\(Int(size.width))x\(Int(size.height)) \(count) 词"
            if points.contains(where: { !inner.contains($0) }) { outside.append(label) }
            guard count > 1 else { continue }
            let wanted = L.separation(count: count, canvas: canvas)
            let closest = minimumDistance(points)
            if closest < wanted * 0.75 * 0.75 * 0.75 { belowFloor.append("\(label):最近 \(Int(closest))") }
            if roomy.contains(size), closest < wanted * 0.999 {
                crowded.append("\(label):最近 \(Int(closest)) < \(Int(wanted))")
            }
        }
    }
    expectEqual(outside, [], "星座布点: 每颗星都夹在留白之内,不会掉出画布")
    expectEqual(crowded, [], "星座布点: 画布够大时任意两颗星都不比最小间距更近")
    expectEqual(belowFloor, [], "星座布点: 画布摆不开时也不低于最小间距的 0.75³")

    let walked = L.points(count: 8, seed: seed, canvas: canvas)
    var steps: [CGFloat] = []
    for index in 1..<walked.count {
        steps.append(hypot(walked[index].x - walked[index - 1].x, walked[index].y - walked[index - 1].y))
    }
    expectEqual(steps.allSatisfy { $0 >= L.stepRange.lowerBound - 0.5 && $0 <= L.stepRange.upperBound + 0.5 }, true,
                "星座布点: 画布放得下时,相邻两颗星的间距落在 80–120pt")

    expectEqual(L.separation(count: 25, canvas: L.Canvas(size: CGSize(width: 600, height: 360))) < L.minSeparation, true,
                "星座布点: 词多到摆不下时,最小间距按面积收窄")
    expectEqual(L.separation(count: 6, canvas: canvas), L.minSeparation,
                "星座布点: 画布放得下时,最小间距就是 64pt")

    let grains = L.dust(count: 40, seed: L.seed(for: "dust"), size: CGSize(width: 800, height: 600))
    expectEqual(grains.count, 40, "星座背景: 背景星尘按要的颗数生成")
    expectEqual(grains == L.dust(count: 40, seed: L.seed(for: "dust"), size: CGSize(width: 800, height: 600)), true,
                "星座背景: 背景星尘每次都落在同一处")
    expectEqual(grains.allSatisfy { $0.point.x >= 0 && $0.point.x <= 800 && $0.point.y >= 0 && $0.point.y <= 600 },
                true, "星座背景: 背景星尘不出画布")
}

private func checkConstellationReveal() {
    print("\n== 星座:逐词点亮 ==")
    let words = [
        SyncedLyricWord(text: "the", startMs: 1000, durationMs: 400),
        SyncedLyricWord(text: "road", startMs: 1400, durationMs: 600),
        SyncedLyricWord(text: "runs", startMs: 2000, durationMs: 500),
    ]
    func reveal(_ nowMs: Int) -> ConstellationReveal { ConstellationReveal.at(nowMs: nowMs, words: words) }

    expectEqual(reveal(0).revealedCount, 0, "星座点亮: 第一个词还没到,一颗星都不画")
    expectEqual(reveal(0).activeIndex, nil, "星座点亮: 第一个词还没到,没有当前词")
    expectEqual(reveal(1000).revealedCount, 1, "星座点亮: 到了起始时间那一刻就点亮")
    expectEqual(reveal(1399).activeIndex, 0, "星座点亮: 下一个词没开口前,当前词不变")
    expectEqual(reveal(1400).activeIndex, 1, "星座点亮: 下一个词开口,当前词跟着换")
    expectEqual(reveal(9999).revealedCount, 3, "星座点亮: 唱完整句三颗星都在")
    expectEqual(ConstellationReveal.at(nowMs: 500, words: []).activeIndex, nil, "星座点亮: 没有逐字数据时没有当前词")

    typealias Reveal = ConstellationReveal
    expectEqual(Reveal.edgeProgress(index: 0, nowMs: 1000, words: words), 0, "星座连线: 上一个词刚开口,线还没画")
    expectEqual(Reveal.edgeProgress(index: 0, nowMs: 1200, words: words), 0.5, "星座连线: 两个时间戳的正中间,线画一半")
    expectEqual(Reveal.edgeProgress(index: 0, nowMs: 1400, words: words), 1, "星座连线: 下一个词开口那一刻,线正好连上")
    expectEqual(Reveal.edgeProgress(index: 0, nowMs: 5000, words: words), 1, "星座连线: 过去的线一直连着")
    expectEqual(Reveal.edgeProgress(index: 2, nowMs: 5000, words: words), 0, "星座连线: 最后一个词后面没有线")
    expectEqual(Reveal.edgeProgress(index: -1, nowMs: 5000, words: words), 0, "星座连线: 越界的下标不画线")

    expectEqual(Reveal.appearProgress(index: 1, nowMs: 1399, words: words), 0, "星座出场: 没到起始时间不出场")
    expectEqual(Reveal.appearProgress(index: 1, nowMs: 1400, words: words), 0, "星座出场: 起始时间那一刻从零开始放大")
    expectEqual(Reveal.appearProgress(index: 1, nowMs: 1400 + Reveal.appearMs, words: words), 1,
                "星座出场: 放大用掉 appearMs 之后到位")
    expectEqual(Reveal.appearProgress(index: 1, nowMs: 9999, words: words), 1, "星座出场: 之后一直是满的")

    expectEqual(Reveal.settleProgress(index: 0, nowMs: 1399, words: words), 0, "星座收小: 还是当前词时不收")
    expectEqual(Reveal.settleProgress(index: 0, nowMs: 1400 + Reveal.settleMs / 2, words: words), 0.5,
                "星座收小: 下一个词开口后按 settleMs 收到一半")
    expectEqual(Reveal.settleProgress(index: 0, nowMs: 1400 + Reveal.settleMs, words: words), 1,
                "星座收小: settleMs 之后收到底(13pt / 40%)")
    expectEqual(Reveal.settleProgress(index: 2, nowMs: 9999, words: words), 0, "星座收小: 最后一个词后面没有词,不收")
}

private func checkConstellationWiring() {
    print("\n== 星座:接线 ==")
    expectEqual(OverlayVisibility.shouldShow(isVisible: true, hiddenForNoLyrics: false, coveredByFullScreen: false,
                                             hideWhenNotPlaying: false, isPlaying: true, hiddenForAd: false,
                                             constellationOpen: true), false,
                "星座接线: 星座窗口开着时悬浮歌词藏起来,同一句不画两遍")
    expectEqual(OverlayVisibility.shouldShow(isVisible: true, hiddenForNoLyrics: false, coveredByFullScreen: false,
                                             hideWhenNotPlaying: false, isPlaying: true, hiddenForAd: false), true,
                "星座接线: 星座窗口没开着时悬浮歌词照常显示")

    let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
    func source(_ path: String) -> String {
        (try? String(contentsOf: root.appendingPathComponent(path), encoding: .utf8)) ?? ""
    }
    let controller = source("lyrimuse/UI/LyricsOverlayWindowController.swift")
    expectEqual(controller.contains("ConstellationWindowController.shared.$isOpen")
                && controller.contains("constellationOpen: hiddenForConstellation"), true,
                "星座接线: 悬浮窗订阅星座窗口开关,并把它喂给显示判定")

    let window = source("lyrimuse/UI/ConstellationWindow.swift")
    expectEqual(window.contains("let wanted: NSWindow.CollectionBehavior = [.fullScreenPrimary]")
                && window.contains("NSWindow.didUpdateNotification"), true,
                "星座窗口: 绿键要显示成全屏箭头,collectionBehavior 每个更新周期都补一次")
    expectEqual(window.contains("window.toggleFullScreen(nil)"), true,
                "星座窗口: 打开时进原生全屏(自己的 Space)")

    let scenes = source("lyrimuse/App.swift")
    expectEqual(scenes.contains("id: ConstellationWindowID.scene"), true, "星座窗口: 场景挂在 App 的场景树上")
    expectEqual(source("lyrimuse/MenuBar/MenuBarSceneActions.swift").contains("AppActions.shared.openConstellation"),
                true, "星座窗口: 开窗的环境 action 在锚点视图里捕获")
    expectEqual(source("lyrimuse/SettingsView.swift").contains("AppActions.shared.openConstellation?()"), true,
                "星座窗口: 「歌词显示 › 星座」那一段有打开入口")
}
