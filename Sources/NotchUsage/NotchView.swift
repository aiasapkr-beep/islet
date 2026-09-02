import SwiftUI

/// The island itself: collapsed it hugs the notch and shows two small gauges,
/// hovered it drops down to show both windows with reset timers.
struct NotchView: View {
    @EnvironmentObject var store: UsageStore
    let geometry: NotchGeometry

    @State private var hovering = ProcessInfo.processInfo.environment["NOTCHUSAGE_EXPANDED"] == "1"
    @State private var collapseTask: Task<Void, Never>?

    private let sideWidth: CGFloat = 70
    private let expandedWidth: CGFloat = 440
    private var collapsedWidth: CGFloat { geometry.notchWidth + sideWidth * 2 }

    var body: some View {
        VStack(spacing: 0) {
            island
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private var island: some View {
        VStack(spacing: 0) {
            gaugeRow
                .frame(height: geometry.notchHeight)
            if hovering {
                detail
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .frame(width: hovering ? max(expandedWidth, collapsedWidth) : collapsedWidth)
        .background(
            UnevenRoundedRectangle(bottomLeadingRadius: hovering ? 22 : 12,
                                   bottomTrailingRadius: hovering ? 22 : 12)
                .fill(.black)
                .shadow(color: .black.opacity(hovering ? 0.45 : 0), radius: 14, y: 6)
        )
        .contentShape(Rectangle())
        .onHover { over in
            collapseTask?.cancel()
            if over {
                withAnimation(.spring(response: 0.36, dampingFraction: 0.82)) { hovering = true }
            } else {
                collapseTask = Task {
                    try? await Task.sleep(for: .milliseconds(180))
                    guard !Task.isCancelled else { return }
                    withAnimation(.spring(response: 0.32, dampingFraction: 0.86)) { hovering = false }
                }
            }
        }
    }

    // MARK: Collapsed row (also the header when expanded)

    private var gaugeRow: some View {
        HStack(spacing: 0) {
            MiniGauge(label: "5H", window: store.usage?.fiveHour, error: store.errorMessage != nil && store.usage == nil)
                .frame(width: sideWidth)
            Spacer().frame(width: hovering ? max(expandedWidth, collapsedWidth) - sideWidth * 2 : geometry.notchWidth)
            MiniGauge(label: "7D", window: store.usage?.sevenDay, error: store.errorMessage != nil && store.usage == nil)
                .frame(width: sideWidth)
        }
    }

    // MARK: Expanded detail

    private var detail: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let u = store.usage {
                UsageRow(title: "5-hour session", window: u.fiveHour)
                UsageRow(title: "Weekly · all models", window: u.sevenDay)
                if let o = u.sevenDayOpus { UsageRow(title: "Weekly · Opus", window: o) }
                if let s = u.sevenDaySonnet { UsageRow(title: "Weekly · Sonnet", window: s) }
            } else if store.isLoading {
                Text("Loading usage…").font(.system(size: 12)).foregroundStyle(.white.opacity(0.7))
            }
            if let err = store.errorMessage {
                Text(err)
                    .font(.system(size: 11))
                    .foregroundStyle(Color(red: 1, green: 0.62, blue: 0.04))
                    .fixedSize(horizontal: false, vertical: true)
            }
            footer
        }
        .padding(.horizontal, 18)
        .padding(.top, 4)
        .padding(.bottom, 14)
    }

    private var footer: some View {
        HStack(spacing: 8) {
            Text(store.planText)
            if let src = store.sourceName { Text("·").opacity(0.4); Text(src) }
            Spacer()
            if let t = store.lastUpdated {
                TimelineView(.periodic(from: .now, by: 30)) { ctx in
                    Text("Updated \(relativeText(until: ctx.date, from: t)) ago")
                }
            }
            Button {
                store.refresh(force: true)
            } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 11, weight: .semibold))
                    .rotationEffect(.degrees(store.isLoading ? 360 : 0))
                    .animation(store.isLoading ? .linear(duration: 1).repeatForever(autoreverses: false) : .default,
                               value: store.isLoading)
            }
            .buttonStyle(.plain)
        }
        .font(.system(size: 10.5))
        .foregroundStyle(.white.opacity(0.55))
    }
}

// MARK: - Pieces

func usageColor(_ fraction: Double?) -> Color {
    guard let f = fraction else { return .gray }
    if f < 0.5 { return Color(red: 0.20, green: 0.78, blue: 0.35) }   // green
    if f < 0.8 { return Color(red: 1.00, green: 0.62, blue: 0.04) }   // orange
    return Color(red: 1.00, green: 0.27, blue: 0.23)                  // red
}

struct MiniGauge: View {
    let label: String
    let window: UsageWindow?
    let error: Bool

    var body: some View {
        HStack(spacing: 6) {
            Ring(fraction: window?.fraction, color: error ? .red : usageColor(window?.fraction))
                .frame(width: 17, height: 17)
            VStack(alignment: .leading, spacing: -1) {
                Text(label)
                    .font(.system(size: 7.5, weight: .bold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.55))
                Text(window?.percentText ?? (error ? "!" : "–"))
                    .font(.system(size: 11.5, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.white)
            }
        }
        .frame(maxWidth: .infinity)
    }
}

struct Ring: View {
    let fraction: Double?
    let color: Color

    var body: some View {
        ZStack {
            Circle().stroke(Color.white.opacity(0.15), lineWidth: 3)
            Circle()
                .trim(from: 0, to: fraction ?? 0)
                .stroke(color, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.easeOut(duration: 0.6), value: fraction)
        }
    }
}

struct UsageRow: View {
    let title: String
    let window: UsageWindow?

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text(title).font(.system(size: 12, weight: .medium)).foregroundStyle(.white.opacity(0.85))
                Spacer()
                Text(window?.percentText ?? "–")
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(usageColor(window?.fraction))
            }
            GeometryReader { g in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.12))
                    Capsule().fill(usageColor(window?.fraction))
                        .frame(width: g.size.width * (window?.fraction ?? 0))
                        .animation(.easeOut(duration: 0.6), value: window?.fraction)
                }
            }
            .frame(height: 6)
            if let r = window?.resetsAt {
                TimelineView(.periodic(from: .now, by: 30)) { ctx in
                    Text("Resets in \(relativeText(until: r, from: ctx.date)) · \(clockText(r))")
                        .font(.system(size: 10)).foregroundStyle(.white.opacity(0.5))
                }
            }
        }
    }
}
