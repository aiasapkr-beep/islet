import SwiftUI
import AppKit

@main
struct IsletApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @ObservedObject private var store = UsageStore.shared
    @ObservedObject private var reminders = RemindersMonitor.shared

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
        Toggle("Reminders in Island", isOn: $store.showReminders)
        if store.showReminders && reminders.status == .authorized {
            Picker("Reminders List", selection: $reminders.selectedListID) {
                Text("All Lists").tag(String?.none)
                ForEach(reminders.lists) { l in Text(l.title).tag(String?.some(l.id)) }
            }
        }
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

            let rem = store.$showReminders.removeDuplicates().receive(on: RunLoop.main).sink { on in
                if on { RemindersMonitor.shared.start() } else { RemindersMonitor.shared.stop() }
            }
            observers.append(rem)
        }
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
