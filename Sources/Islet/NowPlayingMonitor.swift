import AppKit
import Foundation

/// What the system's Now Playing channel currently reports (YouTube Music, Spotify, Safari…).
struct NowPlaying: Equatable {
    var title: String
    var artist: String
    var album: String
    var playing: Bool
    var duration: Double?
    var elapsed: Double?
    var timestamp: Date?
    var rate: Double
    var bundleID: String
    var itemID: String?
    var artwork: NSImage?

    /// Elapsed seconds extrapolated from the last report.
    func elapsedNow(at now: Date = Date()) -> Double? {
        guard let e = elapsed else { return nil }
        guard playing, let ts = timestamp else { return e }
        let v = e + now.timeIntervalSince(ts) * rate
        return duration.map { min(v, $0) } ?? v
    }
}

/// Runs the vendored mediaremote-adapter (`/usr/bin/perl` + helper framework) as a child
/// process and turns its JSON stream into `NowPlaying` values. If the adapter is missing
/// or breaks on a future macOS, `available` flips to false and the UI simply hides music.
@MainActor
final class NowPlayingMonitor: ObservableObject {
    static let shared = NowPlayingMonitor()

    @Published private(set) var current: NowPlaying?
    @Published private(set) var available = true

    enum Command: Int {
        case play = 0, pause = 1, togglePlayPause = 2, stop = 3, nextTrack = 4, previousTrack = 5
    }

    private var process: Process?
    private var pipe: Pipe?
    private var buffer = Data()
    private var payload: [String: Any] = [:]
    private var lastArtworkB64: String?
    private var lastLoggedKey = ""
    private var enabled = false
    private var restarts = 0

    private init() {}

    // MARK: Locating the adapter

    struct AdapterPaths { let script: URL; let framework: URL }

    static var adapterPaths: AdapterPaths? {
        var dirs: [URL] = []
        if let env = ProcessInfo.processInfo.environment["ISLET_ADAPTER_DIR"] {
            dirs.append(URL(fileURLWithPath: env))
        }
        if let res = Bundle.main.resourceURL { dirs.append(res) }
        // Development fallback when running the bare executable from the repo.
        let vendor = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("Vendor/mediaremote-adapter")
        for d in dirs {
            let s = d.appendingPathComponent("mediaremote-adapter.pl")
            let f = d.appendingPathComponent("MediaRemoteAdapter.framework")
            if FileManager.default.fileExists(atPath: s.path), FileManager.default.fileExists(atPath: f.path) {
                return AdapterPaths(script: s, framework: f)
            }
        }
        let s = vendor.appendingPathComponent("bin/mediaremote-adapter.pl")
        let f = vendor.appendingPathComponent("build/MediaRemoteAdapter.framework")
        if FileManager.default.fileExists(atPath: s.path), FileManager.default.fileExists(atPath: f.path) {
            return AdapterPaths(script: s, framework: f)
        }
        return nil
    }

    // MARK: Lifecycle

    func start() {
        enabled = true
        restarts = 0
        launch()
    }

    func stop() {
        enabled = false
        tearDown()
        current = nil
    }

    private func launch() {
        guard enabled, process == nil else { return }
        guard let paths = Self.adapterPaths else {
            available = false
            Log.info("now playing adapter not found; music disabled")
            return
        }
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/perl")
        proc.arguments = [paths.script.path, paths.framework.path, "stream", "--debounce=150"]
        let p = Pipe()
        proc.standardOutput = p
        proc.standardError = FileHandle.nullDevice
        p.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }
            Task { @MainActor in self?.ingest(data) }
        }
        proc.terminationHandler = { [weak self] _ in
            Task { @MainActor in self?.processDied() }
        }
        do {
            try proc.run()
            process = proc
            pipe = p
            available = true
            Log.info("now playing adapter started (pid \(proc.processIdentifier))")
        } catch {
            available = false
            Log.error("now playing adapter failed to start: \(error.localizedDescription)")
        }
    }

    private func tearDown() {
        pipe?.fileHandleForReading.readabilityHandler = nil
        if let p = process, p.isRunning { p.terminate() }
        process = nil
        pipe = nil
        buffer.removeAll()
        payload.removeAll()
        lastArtworkB64 = nil
    }

    private func processDied() {
        let wasRunning = process != nil
        tearDown()
        guard enabled, wasRunning else { return }
        restarts += 1
        if restarts > 5 {
            available = false
            current = nil
            Log.error("now playing adapter keeps dying; giving up")
            return
        }
        Log.info("now playing adapter exited; restarting (\(restarts))")
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
            Task { @MainActor in self?.launch() }
        }
    }

    // MARK: Parsing

    private func ingest(_ data: Data) {
        buffer.append(data)
        while let nl = buffer.firstIndex(of: 0x0A) {
            let line = buffer.subdata(in: buffer.startIndex..<nl)
            buffer.removeSubrange(buffer.startIndex...nl)
            handle(line: line)
        }
    }

    private func handle(line: Data) {
        guard let obj = try? JSONSerialization.jsonObject(with: line) as? [String: Any],
              obj["type"] as? String == "data",
              let p = obj["payload"] as? [String: Any] else { return }
        if obj["diff"] as? Bool == true {
            for (k, v) in p {
                if v is NSNull { payload.removeValue(forKey: k) } else { payload[k] = v }
            }
        } else {
            payload = p
        }
        rebuild()
    }

    private func rebuild() {
        guard let title = payload["title"] as? String, !title.isEmpty,
              let bundle = payload["bundleIdentifier"] as? String else {
            current = nil
            return
        }
        func num(_ k: String) -> Double? { (payload[k] as? NSNumber)?.doubleValue }

        var art = current?.artwork
        let b64 = payload["artworkData"] as? String
        if b64 != lastArtworkB64 {
            lastArtworkB64 = b64
            art = b64.flatMap { Data(base64Encoded: $0) }.flatMap { NSImage(data: $0) }
        }
        let key = "\(payload["contentItemIdentifier"] as? String ?? title)|\(payload["playing"] as? Bool ?? false)"
        if key != lastLoggedKey {
            lastLoggedKey = key
            Log.info("now playing: \(title) — \(payload["artist"] as? String ?? "") playing=\(payload["playing"] as? Bool ?? false) art=\(art != nil)")
        }
        current = NowPlaying(
            title: title,
            artist: payload["artist"] as? String ?? "",
            album: payload["album"] as? String ?? "",
            playing: payload["playing"] as? Bool ?? false,
            duration: num("duration"),
            elapsed: num("elapsedTime"),
            timestamp: (payload["timestamp"] as? String).flatMap(ISO8601.parse),
            rate: num("playbackRate") ?? 1,
            bundleID: bundle,
            itemID: payload["contentItemIdentifier"] as? String,
            artwork: art
        )
    }

    // MARK: Control

    func send(_ command: Command) {
        guard let paths = Self.adapterPaths else { return }
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/perl")
        proc.arguments = [paths.script.path, paths.framework.path, "send", String(command.rawValue)]
        proc.standardOutput = FileHandle.nullDevice
        proc.standardError = FileHandle.nullDevice
        try? proc.run()
        // Optimistic UI for play/pause; the stream corrects it within a moment.
        if command == .togglePlayPause, var c = current {
            c.playing.toggle()
            c.elapsed = c.elapsedNow()
            c.timestamp = Date()
            current = c
        }
    }

    // MARK: Mock

    func installMock() {
        let img = NSImage(size: NSSize(width: 120, height: 120), flipped: false) { rect in
            NSGradient(colors: [NSColor(calibratedRed: 0.95, green: 0.35, blue: 0.30, alpha: 1),
                                NSColor(calibratedRed: 0.35, green: 0.20, blue: 0.60, alpha: 1)])?
                .draw(in: rect, angle: 45)
            return true
        }
        current = NowPlaying(title: "Self Control", artist: "반타01 및 MPT", album: "", playing: true,
                             duration: 233, elapsed: 61, timestamp: Date(), rate: 1,
                             bundleID: "com.google.Chrome.app.youtubemusic", itemID: "mock", artwork: img)
    }
}
