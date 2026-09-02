import EventKit
import Foundation

/// Apple Reminders via EventKit: incomplete reminders from one list (or all),
/// sorted so the most urgent one can sit next to the notch.
@MainActor
final class RemindersMonitor: ObservableObject {
    static let shared = RemindersMonitor()

    struct Item: Identifiable, Equatable {
        let id: String
        let title: String
        let due: Date?
        let hasTime: Bool
        let priority: Int
        let listName: String
        let created: Date?

        var isOverdue: Bool { due.map { $0 < Date() } ?? false }
        var isToday: Bool { due.map { Calendar.current.isDateInToday($0) } ?? false }

        /// "Overdue", "Today 18:00", "Tomorrow", "Sep 5"
        var dueText: String? {
            guard let d = due else { return nil }
            let cal = Calendar.current
            let time: String = {
                guard hasTime else { return "" }
                let f = DateFormatter(); f.setLocalizedDateFormatFromTemplate("HH:mm"); return " " + f.string(from: d)
            }()
            if d < Date() && !(cal.isDateInToday(d) && !hasTime) { return "Overdue" + (cal.isDateInToday(d) ? time : "") }
            if cal.isDateInToday(d) { return "Today" + time }
            if cal.isDateInTomorrow(d) { return "Tomorrow" + time }
            let f = DateFormatter(); f.setLocalizedDateFormatFromTemplate("MMM d"); return f.string(from: d) + time
        }
    }

    struct List: Identifiable, Equatable { let id: String; let title: String }

    enum Status: Equatable { case unknown, notDetermined, denied, authorized, unavailable }

    @Published private(set) var items: [Item] = []
    @Published private(set) var lists: [List] = []
    @Published private(set) var status: Status = .unknown
    @Published var selectedListID: String? {
        didSet {
            UserDefaults.standard.set(selectedListID, forKey: "remindersListID")
            reload()
        }
    }
    /// Ids the user just ticked; kept briefly so the row can fade before it disappears.
    @Published private(set) var completing: Set<String> = []

    var selectedListName: String {
        guard let id = selectedListID, let l = lists.first(where: { $0.id == id }) else { return "All lists" }
        return l.title
    }

    private let store = EKEventStore()
    private var observer: Any?
    private var enabled = false

    private init() {
        selectedListID = UserDefaults.standard.string(forKey: "remindersListID")
    }

    // MARK: Lifecycle

    func start() {
        enabled = true
        switch EKEventStore.authorizationStatus(for: .reminder) {
        case .fullAccess:
            status = .authorized
            begin()
        case .denied, .restricted, .writeOnly:
            status = .denied
        case .notDetermined:
            status = .notDetermined
            Task {
                do {
                    let ok = try await store.requestFullAccessToReminders()
                    Log.info("reminders access request finished: granted=\(ok), status=\(EKEventStore.authorizationStatus(for: .reminder).rawValue)")
                    status = ok ? .authorized : .denied
                    if ok { begin() }
                } catch {
                    status = .denied
                    Log.error("reminders access: \(error.localizedDescription)")
                }
            }
        @unknown default:
            status = .unavailable
        }
        Log.info("reminders status: \(status)")
    }

    func stop() {
        enabled = false
        if let o = observer { NotificationCenter.default.removeObserver(o) }
        observer = nil
        items = []
    }

    private func begin() {
        guard enabled, observer == nil else { return }
        observer = NotificationCenter.default.addObserver(forName: .EKEventStoreChanged, object: store, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.reload() }
        }
        reload()
    }

    // MARK: Data

    func reload() {
        guard enabled, status == .authorized else { return }
        let calendars = store.calendars(for: .reminder)
        lists = calendars.map { List(id: $0.calendarIdentifier, title: $0.title) }
            .sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
        let scope: [EKCalendar]? = selectedListID.flatMap { id in calendars.first { $0.calendarIdentifier == id } }.map { [$0] }
        if selectedListID != nil && scope == nil { selectedListID = nil; return }

        let predicate = store.predicateForIncompleteReminders(withDueDateStarting: nil, ending: nil, calendars: scope)
        store.fetchReminders(matching: predicate) { [weak self] reminders in
            let cal = Calendar.current
            let mapped: [Item] = (reminders ?? []).compactMap { r in
                guard let title = r.title, !title.isEmpty else { return nil }
                let due = r.dueDateComponents.flatMap { cal.date(from: $0) }
                let hasTime = r.dueDateComponents?.hour != nil
                return Item(id: r.calendarItemIdentifier, title: title, due: due, hasTime: hasTime,
                            priority: r.priority, listName: r.calendar.title, created: r.creationDate)
            }
            let sorted = mapped.sorted { a, b in
                switch (a.due, b.due) {
                case let (x?, y?) where x != y: return x < y
                case (nil, .some): return false
                case (.some, nil): return true
                default: break
                }
                let pa = a.priority == 0 ? 10 : a.priority, pb = b.priority == 0 ? 10 : b.priority
                if pa != pb { return pa < pb }
                return (a.created ?? .distantPast) < (b.created ?? .distantPast)
            }
            Task { @MainActor in
                guard let self else { return }
                self.items = sorted.filter { !self.completing.contains($0.id) }
            }
        }
    }

    func complete(_ item: Item) {
        guard let r = store.calendarItem(withIdentifier: item.id) as? EKReminder else { return }
        completing.insert(item.id)
        r.isCompleted = true
        r.completionDate = Date()
        do {
            try store.save(r, commit: true)
        } catch {
            Log.error("complete reminder: \(error.localizedDescription)")
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in
            Task { @MainActor in
                self?.completing.remove(item.id)
                self?.items.removeAll { $0.id == item.id }
            }
        }
    }

    func add(_ title: String) {
        let t = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty, status == .authorized else { return }
        let r = EKReminder(eventStore: store)
        r.title = t
        r.calendar = selectedListID.flatMap { id in store.calendars(for: .reminder).first { $0.calendarIdentifier == id } }
            ?? store.defaultCalendarForNewReminders()
        do {
            try store.save(r, commit: true)
            reload()
        } catch {
            Log.error("add reminder: \(error.localizedDescription)")
        }
    }

    // MARK: Mock

    func installMock() {
        status = .authorized
        lists = [List(id: "m1", title: "Today")]
        items = [
            Item(id: "a", title: "릴스 컨펌 4편", due: Date().addingTimeInterval(-3600), hasTime: true, priority: 1, listName: "Today", created: Date()),
            Item(id: "b", title: "SQLD 3장 문제 풀기", due: Calendar.current.date(bySettingHour: 18, minute: 0, second: 0, of: Date()), hasTime: true, priority: 0, listName: "Today", created: Date()),
            Item(id: "c", title: "Islet README 스크린샷 교체", due: nil, hasTime: false, priority: 0, listName: "Today", created: Date()),
        ]
    }
}
