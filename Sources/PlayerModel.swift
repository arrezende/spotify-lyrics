import Foundation
import Combine
import QuartzCore

struct LyricLine: Identifiable, Equatable {
    let id: Int
    let time: Double
    let text: String
}

struct SpotifySnapshot {
    let title: String
    let artist: String
    let album: String
    let playing: Bool
    let position: Double
    let duration: Double
}

final class PlayerModel: ObservableObject {
    @Published private(set) var title = "—"
    @Published private(set) var artist = ""
    @Published private(set) var album = ""
    @Published private(set) var isPlaying = false
    @Published private(set) var position: Double = 0
    @Published private(set) var duration: Double = 0
    @Published private(set) var lines: [LyricLine] = []
    @Published private(set) var currentIndex = -1
    @Published private(set) var statusText = "Conectando ao Spotify…"
    @Published private(set) var isSynced = false
    @Published private(set) var isDemo = false
    @Published private(set) var offset: Double = 0

    // MARK: - Derived text for the panel

    var previousLine: String {
        guard currentIndex > 0, currentIndex <= lines.count else { return " " }
        return lines[currentIndex - 1].text
    }

    var currentLine: String {
        if currentIndex >= 0, currentIndex < lines.count { return lines[currentIndex].text }
        if let first = lines.first { return first.text }
        return " "
    }

    var nextLine: String {
        let n = currentIndex < 0 ? 1 : currentIndex + 1
        guard n >= 0, n < lines.count else { return " " }
        return lines[n].text
    }

    var progress: Double {
        guard duration > 0 else { return 0 }
        return min(max(position / duration, 0), 1)
    }

    var hasLyrics: Bool { !lines.isEmpty }

    // MARK: - State

    private var pollTimer: Timer?
    private var uiTimer: Timer?
    private var polling = false
    private let pollQueue = DispatchQueue(label: "spotify.poll")
    private var lastRawPosition: Double = 0
    private var lastPollStamp: CFTimeInterval = 0
    private var lastTrackKey = ""
    private var failedPolls = 0
    private var offsets: [String: Double] = [:]
    private var lyricsTask: URLSessionDataTask?
    private var demoStart: CFTimeInterval = 0

    private let demoMode: Bool

    @Published var transparentBackground: Bool
    @Published var isCollapsed = false
    @Published var windowAlpha: Double
    @Published var bottomOverDock: Bool

    init() {
        demoMode = CommandLine.arguments.contains("--demo")
        transparentBackground = UserDefaults.standard.object(forKey: "transparentBackground") as? Bool ?? false
        windowAlpha = UserDefaults.standard.object(forKey: "windowAlpha") as? Double ?? 1.0
        bottomOverDock = UserDefaults.standard.object(forKey: "bottomOverDock") as? Bool ?? false
        if CommandLine.arguments.contains("--transparent") { transparentBackground = true }
        if CommandLine.arguments.contains("--collapsed") { isCollapsed = true }
        if CommandLine.arguments.contains("--over-dock") { bottomOverDock = true }
        if let saved = UserDefaults.standard.dictionary(forKey: "lyricOffsets") as? [String: Double] {
            offsets = saved
        }
    }

    // MARK: - Presentation controls

    func toggleTransparency() {
        transparentBackground.toggle()
        UserDefaults.standard.set(transparentBackground, forKey: "transparentBackground")
    }

    func setAlpha(_ value: Double) {
        windowAlpha = value
        UserDefaults.standard.set(value, forKey: "windowAlpha")
    }

    func toggleCollapsed() {
        isCollapsed.toggle()
    }

    func toggleBottomOverDock() {
        bottomOverDock.toggle()
        UserDefaults.standard.set(bottomOverDock, forKey: "bottomOverDock")
    }

    /// Play/pause, next and previous. Sends the command to Spotify, then re-polls so the
    /// new track and its lyrics show up quickly.
    func transport(_ action: SpotifyBridge.Transport) {
        if isDemo {
            switch action {
            case .playPause: isPlaying.toggle()
            case .next, .previous: demoStart = CACurrentMediaTime()
            }
            return
        }
        // Flip the icon right away; the next poll corrects it if Spotify disagrees.
        if action == .playPause { isPlaying.toggle() }
        pollQueue.async { [weak self] in
            _ = SpotifyBridge.send(action)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { self?.poll() }
        }
    }

    private var trackKey: String {
        "\(artist.lowercased())|\(title.lowercased())"
    }

    // MARK: - Lifecycle

    func start() {
        if demoMode { startDemo(); return }

        let pollTick = Timer(timeInterval: 0.45, repeats: true) { [weak self] _ in self?.poll() }
        RunLoop.main.add(pollTick, forMode: .common)
        pollTimer = pollTick

        let uiTick = Timer(timeInterval: 0.1, repeats: true) { [weak self] _ in self?.tickUI() }
        RunLoop.main.add(uiTick, forMode: .common)
        uiTimer = uiTick

        poll()
    }

    func reloadLyrics() {
        lastTrackKey = ""
        poll()
    }

    func nudgeOffset(_ delta: Double) {
        offset = (offset + delta * 10).rounded() / 10
        offsets[trackKey] = offset
        UserDefaults.standard.set(offsets, forKey: "lyricOffsets")
        recomputeIndex(force: true)
    }

    func resetOffset() {
        offset = 0
        offsets.removeValue(forKey: trackKey)
        UserDefaults.standard.set(offsets, forKey: "lyricOffsets")
        recomputeIndex(force: true)
    }

    // MARK: - Polling

    private func poll() {
        guard !polling else { return }
        polling = true
        pollQueue.async { [weak self] in
            let snap = SpotifyBridge.snapshot()
            DispatchQueue.main.async {
                self?.polling = false
                self?.apply(snap)
            }
        }
    }

    private func apply(_ snap: SpotifySnapshot?) {
        guard let snap else {
            failedPolls += 1
            if failedPolls == 2 {
                statusText = "Spotify não respondeu\nAbra o Spotify e permita o controle em Ajustes › Privacidade › Automação"
            }
            return
        }
        failedPolls = 0
        statusText = ""

        title = snap.title
        artist = snap.artist
        album = snap.album
        isPlaying = snap.playing
        duration = snap.duration
        lastRawPosition = snap.position
        lastPollStamp = CACurrentMediaTime()
        position = snap.position

        let key = trackKey
        if key != lastTrackKey {
            lastTrackKey = key
            offset = offsets[key] ?? 0
            loadLyrics(for: snap)
        }
        recomputeIndex()
    }

    // MARK: - UI tick (position interpolation + line advancing)

    private func tickUI() {
        if isDemo { tickDemo(); return }
        guard isPlaying else { recomputeIndex(); return }
        let elapsed = CACurrentMediaTime() - lastPollStamp
        let projected = min(lastRawPosition + elapsed, duration > 0 ? duration : .greatestFiniteMagnitude)
        if abs(projected - position) > 0.2 { position = projected }
        recomputeIndex()
    }

    private func recomputeIndex(force: Bool = false) {
        guard !lines.isEmpty else {
            if currentIndex != -1 { currentIndex = -1 }
            return
        }
        let t = position + offset
        var idx = -1
        for (i, line) in lines.enumerated() {
            if line.time <= t { idx = i } else { break }
        }
        if force || idx != currentIndex { currentIndex = idx }
    }

    // MARK: - Lyrics loading

    private func loadLyrics(for snap: SpotifySnapshot) {
        lyricsTask?.cancel()
        lines = []
        currentIndex = -1
        isSynced = false
        statusText = "Buscando letra…"

        let key = trackKey
        lyricsTask = LyricsService.search(
            title: snap.title,
            artist: snap.artist,
            album: snap.album,
            duration: snap.duration
        ) { [weak self] result in
            guard let self, self.trackKey == key else { return }
            switch result {
            case .success(let payload):
                self.lines = payload.lines
                self.isSynced = payload.synced
                self.statusText = payload.lines.isEmpty
                    ? "Sem letra sincronizada para esta faixa"
                    : (payload.synced ? "" : "Letra sem sincronia")
                self.recomputeIndex(force: true)
            case .failure:
                self.lines = []
                self.statusText = "Falha ao buscar a letra"
            }
        }
    }

    // MARK: - Demo (used to preview the window before Automation is granted)

    private func startDemo() {
        isDemo = true
        title = "Príncipe da Paz"
        artist = "Flavio Vitor Jr."
        album = "Demo"
        isPlaying = true
        duration = 240
        statusText = ""
        let demoLines = [
            "Toda vez que eu me lembro do teu jeito de olhar",
            "Parece que o tempo volta e eu volto a te encontrar",
            "Mesmo longe, mesmo tarde, mesmo sem querer",
            "Teu nome ainda ecoa em tudo que eu disser",
            "E se um dia o vento traz de volta o teu lugar",
            "Vou deixar a porta aberta pra você entrar",
            "Príncipe da paz, é assim que eu vou ficar"
        ]
        lines = demoLines.enumerated().map { LyricLine(id: $0.offset, time: Double($0.offset) * 3.4 + 1, text: $0.element) }
        isSynced = true
        demoStart = CACurrentMediaTime()
        recomputeIndex(force: true)
    }

    private func tickDemo() {
        let t = CACurrentMediaTime() - demoStart
        position = t.truncatingRemainder(dividingBy: 24)
        recomputeIndex()
    }
}
