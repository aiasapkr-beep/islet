import Foundation
import CoreServices
import Darwin

/// Detects whether Claude Code is actively working right now.
/// Signal 1: transcript writes under ~/.claude/projects (FSEvents) — tokens are flowing.
/// Signal 2: number of running `claude` processes (polled) — sessions open.
@MainActor
final class ActivityMonitor: ObservableObject {
    static let shared = ActivityMonitor()

    @Published private(set) var lastActivity: Date?
    @Published private(set) var runningSessions = 0
    @Published private(set) var isActive = false

    /// How long after the last transcript write we still show the pulse.
    var activeWindow: TimeInterval = 20

    private var stream: FSEventStreamRef?
    private let fsQueue = DispatchQueue(label: "kr.asapai.Islet.fsevents", qos: .utility)
    private var timer: Timer?

    private init() {}

    func start() {
        startWatching()
        tick()
        timer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
    }

    private func tick() {
        runningSessions = Self.countClaudeProcesses()
        isActive = lastActivity.map { Date().timeIntervalSince($0) < activeWindow } ?? false
    }

    func touch() {
        lastActivity = Date()
        if !isActive { isActive = true }
    }

    // MARK: FSEvents on the transcript directory

    private static var projectsDir: String {
        let env = ProcessInfo.processInfo.environment
        let base = env["CLAUDE_CONFIG_DIR"] ?? (NSHomeDirectory() + "/.claude")
        return base + "/projects"
    }

    private func startWatching() {
        let path = Self.projectsDir
        guard FileManager.default.fileExists(atPath: path) else {
            Log.info("no transcript dir at \(path); activity pulse disabled")
            return
        }
        var ctx = FSEventStreamContext(version: 0,
                                       info: Unmanaged.passUnretained(self).toOpaque(),
                                       retain: nil, release: nil, copyDescription: nil)
        let callback: FSEventStreamCallback = { _, info, count, paths, _, _ in
            guard let info else { return }
            let monitor = Unmanaged<ActivityMonitor>.fromOpaque(info).takeUnretainedValue()
            // Only transcript files count; ignore directory chatter.
            // With kFSEventStreamCreateFlagUseCFTypes the paths argument is a CFArray of CFString.
            let list = unsafeBitCast(paths, to: CFArray.self) as NSArray
            let hit = (0..<count).contains { (list[$0] as? String)?.hasSuffix(".jsonl") ?? false }
            if hit { Task { @MainActor in monitor.touch() } }
        }
        guard let s = FSEventStreamCreate(nil, callback, &ctx, [path] as CFArray,
                                          FSEventStreamEventId(kFSEventStreamEventIdSinceNow), 1.0,
                                          FSEventStreamCreateFlags(kFSEventStreamCreateFlagFileEvents | kFSEventStreamCreateFlagNoDefer | kFSEventStreamCreateFlagUseCFTypes)) else {
            Log.error("FSEventStreamCreate failed")
            return
        }
        FSEventStreamSetDispatchQueue(s, fsQueue)
        FSEventStreamStart(s)
        stream = s
    }

    // MARK: Process scan

    /// Counts processes whose executable is Claude Code (`claude` CLI or the npm package binary).
    nonisolated static func countClaudeProcesses() -> Int {
        var n = proc_listallpids(nil, 0)
        guard n > 0 else { return 0 }
        var pids = [pid_t](repeating: 0, count: Int(n) + 32)
        n = proc_listallpids(&pids, Int32(pids.count * MemoryLayout<pid_t>.size))
        var count = 0
        var buf = [CChar](repeating: 0, count: Int(4 * MAXPATHLEN))
        let me = getpid()
        for pid in pids.prefix(Int(n)) where pid > 0 && pid != me {
            buf[0] = 0
            guard proc_pidpath(pid, &buf, UInt32(buf.count)) > 0 else { continue }
            let path = String(cString: buf)
            let base = (path as NSString).lastPathComponent
            if base == "claude" || path.contains("@anthropic-ai/claude-code/") || path.contains("/claude-code/bin/") {
                count += 1
            }
        }
        return count
    }
}
