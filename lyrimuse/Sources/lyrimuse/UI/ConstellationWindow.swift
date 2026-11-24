import AppKit
import Combine
import LyrimuseCore
import SwiftUI

enum ConstellationWindowID {
    static let scene = "constellation"
    static let defaultSize = CGSize(width: 1000, height: 620)
}

@MainActor
final class ConstellationWindowController: ObservableObject {
    static let shared = ConstellationWindowController()

    @Published private(set) var isOpen = false

    private weak var window: NSWindow?
    private var capabilityObserver: NSObjectProtocol?
    private var closeObserver: NSObjectProtocol?
    private var firstShowObserver: NSObjectProtocol?

    private init() {}

    func attach(_ window: NSWindow) {
        guard self.window !== window else {
            markOpen()
            return
        }
        self.window = window
        window.animationBehavior = .none
        Self.enforceFullScreenCapability(window)

        if let capabilityObserver { NotificationCenter.default.removeObserver(capabilityObserver) }
        capabilityObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didUpdateNotification, object: window, queue: .main
        ) { note in
            guard let win = note.object as? NSWindow else { return }
            MainActor.assumeIsolated { Self.enforceFullScreenCapability(win) }
        }

        if let closeObserver { NotificationCenter.default.removeObserver(closeObserver) }
        closeObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification, object: window, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.markClosed() }
        }

        if let firstShowObserver { NotificationCenter.default.removeObserver(firstShowObserver) }
        firstShowObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didBecomeKeyNotification, object: window, queue: .main
        ) { [weak self] note in
            guard let win = note.object as? NSWindow else { return }
            MainActor.assumeIsolated { self?.enterFullScreenIfWanted(win) }
        }

        markOpen()
    }

    private func markOpen() {
        guard !isOpen else { return }
        isOpen = true
    }

    private func markClosed() {
        guard isOpen else { return }
        isOpen = false
        if let firstShowObserver {
            NotificationCenter.default.removeObserver(firstShowObserver)
            self.firstShowObserver = nil
        }
    }

    /// The green button must show the full-screen arrows and reach its own Space. SwiftUI `Window` strips
    /// `.fullScreenPrimary` and rewrites it every update cycle, so this re-applies it on `didUpdateNotification`.
    /// Writes only when a flag is missing, so it never feeds itself.
    private static func enforceFullScreenCapability(_ window: NSWindow) {
        let wanted: NSWindow.CollectionBehavior = [.fullScreenPrimary]
        let unwanted: NSWindow.CollectionBehavior = [.fullScreenNone, .fullScreenAuxiliary, .canJoinAllSpaces]
        var behavior = window.collectionBehavior
        guard !behavior.isSuperset(of: wanted) || !behavior.isDisjoint(with: unwanted) else { return }
        behavior.subtract(unwanted)
        behavior.formUnion(wanted)
        window.collectionBehavior = behavior
    }

    private func enterFullScreenIfWanted(_ window: NSWindow) {
        if let firstShowObserver {
            NotificationCenter.default.removeObserver(firstShowObserver)
            self.firstShowObserver = nil
        }
        guard !window.styleMask.contains(.fullScreen) else { return }
        Self.enforceFullScreenCapability(window)
        window.toggleFullScreen(nil)
    }
}

@MainActor
final class ConstellationFeed: ObservableObject, RealAudioListener {
    @Published private(set) var lineKey = ""
    @Published private(set) var words: [SyncedLyricWord] = []
    @Published private(set) var plainText: String?
    @Published private(set) var clockRunning = false
    @Published private(set) var accent: Color?
    /// Cover-art colours for the border gradient.
    @Published private(set) var palette: [Color] = []
    /// Real band levels; empty means no audio is being followed and the border breathes on its own.
    @Published private(set) var levels: [Double] = []

    @Published private(set) var borderEnabled = AppSettings.shared.constellationBorder

    private var subscriptions: Set<AnyCancellable> = []
    private var listening = false
    private var windowOpen = false
    private var lastLineKey: String?
    private var runCapacity = ConstellationLayout.runLengthRange.upperBound

    init(live: Bool = true) {
        guard live else { return }
        let coordinator = PlaybackCoordinator.shared
        coordinator.$currentLine
            .sink { [weak self] line in
                guard let self else { return }
                let text = line?.plainText ?? line?.mainText
                plainText = text
                take(line?.words ?? [], key: text ?? "")
            }
            .store(in: &subscriptions)
        coordinator.$isPlayingSmoothed
            .removeDuplicates()
            .sink { [weak self] playing in self?.clockRunning = playing }
            .store(in: &subscriptions)
        coordinator.$artworkAccentColor
            .removeDuplicates()
            .sink { [weak self] color in self?.accent = color }
            .store(in: &subscriptions)
        coordinator.$artworkImage
            .removeDuplicates()
            .sink { [weak self] image in self?.palette = Self.paletteColors(from: image) }
            .store(in: &subscriptions)
        AppSettings.shared.$constellationBorder
            .removeDuplicates()
            .sink { [weak self] on in
                guard let self else { return }
                borderEnabled = on
                syncAudio()
            }
            .store(in: &subscriptions)
    }

    /// Cover art down to 24x24, then the dominant hues out of it.
    private static func paletteColors(from image: NSImage?) -> [Color] {
        guard let image, let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return [] }
        let side = 24
        let space = CGColorSpaceCreateDeviceRGB()
        let info = CGImageAlphaInfo.premultipliedLast.rawValue
        guard let context = CGContext(data: nil, width: side, height: side, bitsPerComponent: 8,
                                      bytesPerRow: side * 4, space: space, bitmapInfo: info) else { return [] }
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: side, height: side))
        guard let raw = context.data else { return [] }
        let bytes = raw.bindMemory(to: UInt8.self, capacity: side * side * 4)
        let pixels = [UInt8](UnsafeBufferPointer(start: bytes, count: side * side * 4))
        let swatches = ConstellationPalette.swatches(premultipliedRGBA: pixels)
        guard swatches.count >= 2 else { return [] }
        return swatches.map { Color(red: $0.red, green: $0.green, blue: $0.blue) }
    }

    /// One constellation spans several lines: words pile up until the run is full, then it clears and
    /// a new one starts. A run keeps its seed so the stars already on screen never move.
    private func take(_ incoming: [SyncedLyricWord], key: String) {
        guard !incoming.isEmpty, key != lastLineKey else { return }
        lastLineKey = key
        let rewound = incoming[0].startMs < (words.last?.startMs ?? Int.min)
        if rewound || words.count + incoming.count > runCapacity {
            startRun(with: incoming, key: key)
            return
        }
        if words.isEmpty { startRun(with: incoming, key: key); return }
        words += incoming
    }

    private func startRun(with incoming: [SyncedLyricWord], key: String) {
        words = incoming
        lineKey = key
        runCapacity = ConstellationLayout.runLength(seed: ConstellationLayout.seed(for: key))
    }

    /// Audio is read only while the window is open and the border is on; the settings preview never reads it.
    func followAudio(_ follow: Bool) {
        windowOpen = follow
        syncAudio()
    }

    private func syncAudio() {
        let wanted = windowOpen && borderEnabled
        guard wanted != listening else { return }
        listening = wanted
        RealAudioMeter.shared.setListening(self, wanted, ignoresSetting: true)
        if !wanted { levels = [] }
    }

    func realAudioModeChanged(live: Bool) {
        if !live { levels = [] }
    }

    func applyRealLevels(_ levels: [Double]) {
        self.levels = levels
    }
}

struct ConstellationScene: View {
    @StateObject private var feed = ConstellationFeed()

    var body: some View {
        ConstellationView(
            lineKey: feed.lineKey,
            words: feed.words,
            plainText: feed.plainText,
            nowMs: { PlaybackCoordinator.shared.lyricsTimelineMs() },
            paused: !feed.clockRunning,
            levels: feed.levels,
            accent: feed.accent,
            palette: feed.palette,
            borderEnabled: feed.borderEnabled)
            .ignoresSafeArea()
            .background(ConstellationWindowCapture())
            .onAppear { feed.followAudio(true) }
            .onDisappear { feed.followAudio(false) }
    }
}

private struct ConstellationWindowCapture: NSViewRepresentable {
    final class CaptureView: NSView {
        var onWindow: ((NSWindow) -> Void)?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if let window { onWindow?(window) }
        }
    }

    func makeNSView(context: Context) -> CaptureView {
        let view = CaptureView(frame: .zero)
        view.onWindow = { window in ConstellationWindowController.shared.attach(window) }
        return view
    }

    func updateNSView(_ nsView: CaptureView, context: Context) {
        if let window = nsView.window { ConstellationWindowController.shared.attach(window) }
    }
}

struct ConstellationPreviewStage: View {
    @StateObject private var feed = ConstellationFeed()

    var body: some View {
        ConstellationView(
            lineKey: feed.lineKey,
            words: feed.words,
            plainText: feed.plainText,
            nowMs: { PlaybackCoordinator.shared.lyricsTimelineMs() },
            paused: !feed.clockRunning,
            accent: feed.accent,
            palette: feed.palette,
            borderEnabled: feed.borderEnabled)
            .frame(height: 220)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.07), lineWidth: 0.5))
    }
}
