import Foundation

/// One rate-limit window as reported by the Claude OAuth usage endpoint.
struct UsageWindow: Equatable {
    /// Percent used, 0...100 (the API may exceed 100 briefly).
    var utilization: Double
    var resetsAt: Date?

    var fraction: Double { min(max(utilization / 100, 0), 1) }
    var percentText: String { "\(Int(utilization.rounded()))%" }
}

/// Snapshot of every window the endpoint returned.
struct Usage: Equatable {
    var fiveHour: UsageWindow?
    var sevenDay: UsageWindow?
    var sevenDayOpus: UsageWindow?
    var sevenDaySonnet: UsageWindow?
    var fetchedAt: Date = Date()

    static func == (a: Usage, b: Usage) -> Bool {
        a.fiveHour == b.fiveHour && a.sevenDay == b.sevenDay
            && a.sevenDayOpus == b.sevenDayOpus && a.sevenDaySonnet == b.sevenDaySonnet
    }
}

enum ISO8601 {
    private static let fractional: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
    private static let plain: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    static func parse(_ s: String) -> Date? {
        fractional.date(from: s) ?? plain.date(from: s)
    }
}

extension Usage {
    /// Lenient decoder: unknown keys are ignored, missing windows become nil.
    init(json data: Data) throws {
        guard let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw UsageAPI.Failure.badResponse
        }
        func window(_ key: String) -> UsageWindow? {
            guard let w = obj[key] as? [String: Any],
                  let u = (w["utilization"] as? NSNumber)?.doubleValue else { return nil }
            let reset = (w["resets_at"] as? String).flatMap(ISO8601.parse)
            return UsageWindow(utilization: u, resetsAt: reset)
        }
        fiveHour = window("five_hour")
        sevenDay = window("seven_day")
        sevenDayOpus = window("seven_day_opus")
        sevenDaySonnet = window("seven_day_sonnet")
        if fiveHour == nil && sevenDay == nil { throw UsageAPI.Failure.badResponse }
    }
}

/// Relative time text such as "2h 13m" or "3d 4h".
func relativeText(until date: Date, from now: Date = Date()) -> String {
    let secs = max(0, Int(date.timeIntervalSince(now)))
    let d = secs / 86400, h = (secs % 86400) / 3600, m = (secs % 3600) / 60
    if d > 0 { return "\(d)d \(h)h" }
    if h > 0 { return "\(h)h \(m)m" }
    return "\(m)m"
}

func clockText(_ date: Date) -> String {
    let f = DateFormatter()
    f.locale = .autoupdatingCurrent
    f.setLocalizedDateFormatFromTemplate(Calendar.current.isDateInToday(date) ? "HH:mm" : "EEE HH:mm")
    return f.string(from: date)
}
