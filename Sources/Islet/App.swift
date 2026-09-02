import SwiftUI
import AppKit

@main
struct IsletApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @ObservedObject private var store = UsageStore.shared

    var body: some Scene {
        MenuBarExtra {
            menu
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "gauge.with.dots.needle.33percent")
                if store.showMenuBarText { Text(store.menuBarTitle).monospacedDigit() }
            }
        }
    }

    @ViewBuilder private var menu: some View {
        if let u = store.usage {
            Text("5-hour: \(u.fiveHour?.percentText ?? "–")" + resetSuffix(u.fiveHour))
            Text("Weekly: \(u.sevenDay?.percentText ?? "–")" + resetSuffix(u.sevenDay))
            if let o = u.sevenDayOpus { Text("Weekly Opus: \(o.percentText)" + resetSuffix(o)) }
        } else {
            Text(store.errorMessage ?? "Loading…")
        }
        Text(store.planText + (store.lastUpdated.map { " · updated \(clockText($0))" } ?? ""))
        Divider()
        Button("Refresh Now") { store.refresh(force: true) }
            .keyboardShortcut("r")
        Divider()
        Toggle("Show in Notch", isOn: $store.showNotch)
        Toggle("Show % in Menu Bar", isOn: $store.showMenuBarText)
        Toggle("Now Playing Island", isOn: $store.showNowPlaying)
        Toggle("Auto-refresh Claude Token", isOn: $store.autoRefreshToken)
        Toggle("Launch at Login", isOn: $store.launchAtLogin)
        Divider()
        Link("GitHub", destination: URL(string: "https://github.com/aiasapkr-beep/islet")!)
        Button("Quit Islet") { NSApp.terminate(nil) }
            .keyboardShortcut("q")
    }

    private func resetSuffix(_ w: UsageWindow?) -> String {
        guard let r = w?.resetsAt else { return "" }
        return "  (resets in \(relativeText(until: r)))"
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var panel: NotchPanel?
    private var geometry: NotchGeometry?
    private var observers: [Any] = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        let store = UsageStore.shared
        store.start()
        ActivityMonitor.shared.start()
        rebuildPanel()
        snapshotIfRequested()

        observers.append(NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in self?.rebuildPanel() })

        // Show/hide when the setting flips.
        let cancellable = store.$showNotch.receive(on: RunLoop.main).sink { [weak self] _ in self?.rebuildPanel() }
        observers.append(cancellable)

        if !UsageStore.mock {
            let music = store.$showNowPlaying.removeDuplicates().receive(on: RunLoop.main).sink { on in
                if on { NowPlayingMonitor.shared.start() } else { NowPlayingMonitor.shared.stop() }
            }
            observers.append(music)
        }
    }

    /// ISLET_SNAPSHOT=/path/out.png renders the island to a trimmed PNG and quits (for README shots).
    private func snapshotIfRequested() {
        guard let path = ProcessInfo.processInfo.environment["ISLET_SNAPSHOT"] else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
            defer { NSApp.terminate(nil) }
            guard let view = self?.panel?.contentView,
                  let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }
            view.cacheDisplay(in: view.bounds, to: rep)
            guard let trimmed = Self.trimTransparent(rep, padding: 24),
                  let png = trimmed.representation(using: .png, properties: [:]) else { return }
            try? png.write(to: URL(fileURLWithPath: path))
            Log.info("snapshot written to \(path)")
        }
    }

    private static func trimTransparent(_ rep: NSBitmapImageRep, padding: Int) -> NSBitmapImageRep? {
        let w = rep.pixelsWide, h = rep.pixelsHigh
        var minX = w, minY = h, maxX = -1, maxY = -1
        for y in 0..<h {
            for x in 0..<w where (rep.colorAt(x: x, y: y)?.alphaComponent ?? 0) > 0.02 {
                minX = min(minX, x); maxX = max(maxX, x); minY = min(minY, y); maxY = max(maxY, y)
            }
        }
        guard maxX >= minX else { return nil }
        let x0 = max(0, minX - padding), y0 = max(0, minY - padding)
        let x1 = min(w - 1, maxX + padding), y1 = min(h - 1, maxY + padding)
        let cw = x1 - x0 + 1, ch = y1 - y0 + 1
        guard let out = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: cw, pixelsHigh: ch, bitsPerSample: 8,
                                         samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                         colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) else { return nil }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: out)
        // Bitmap rows are top-down; NSRect drawing is bottom-up, so flip the source rect.
        let src = NSRect(x: x0, y: h - y1 - 1, width: cw, height: ch)
        NSImage(cgImage: rep.cgImage!, size: NSSize(width: w, height: h))
            .draw(in: NSRect(x: 0, y: 0, width: cw, height: ch), from: src, operation: .copy, fraction: 1)
        NSGraphicsContext.restoreGraphicsState()
        return out
    }

    func applicationWillTerminate(_ notification: Notification) {
        NowPlayingMonitor.shared.stop()
    }

    private func rebuildPanel() {
        let store = UsageStore.shared
        let geo = NotchGeometry.detect()
        guard store.showNotch else {
            panel?.orderOut(nil); panel = nil; geometry = nil
            return
        }
        if let p = panel, geometry == geo {
            p.orderFrontRegardless()
            return
        }
        panel?.orderOut(nil)
        let p = NotchPanel(geometry: geo, store: store)
        p.orderFrontRegardless()
        panel = p
        geometry = geo
    }
}
