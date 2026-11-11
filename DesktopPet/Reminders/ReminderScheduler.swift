// ReminderScheduler.swift
// Schedules future local daily occurrences and preserves pending deliveries.
import AppKit
import Combine

@MainActor final class ReminderScheduler: ObservableObject {
    @Published private(set) var data = ReminderData()
    @Published var error: String?
    @Published private(set) var loadError: String?
    var onDelivery: ((PendingReminder) -> Void)?
    private let store: ReminderStore
    private let now: () -> Date
    private let calendar: () -> Calendar
    private var timer: Timer?
    private var observers: [NSObjectProtocol] = []
    private(set) var ready = false

    init(store: ReminderStore = ReminderStore(), now: @escaping () -> Date = Date.init,
         calendar: @escaping () -> Calendar = { Calendar.current }) {
        self.store = store; self.now = now; self.calendar = calendar
        do { data = try store.load(); ready = true } catch { self.loadError = error.localizedDescription }
        let center = NotificationCenter.default
        for name in [NSNotification.Name.NSSystemClockDidChange, NSNotification.Name.NSSystemTimeZoneDidChange] {
            observers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in self?.schedule() }
            })
        }
        observers.append(NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.schedule() }
        })
        schedule()
    }
    deinit {
        timer?.invalidate()
        for observer in observers { NotificationCenter.default.removeObserver(observer); NSWorkspace.shared.notificationCenter.removeObserver(observer) }
    }
    static func next(_ reminder: Reminder, after date: Date, calendar: Calendar) -> Date? {
        guard reminder.enabled else { return nil }
        var components = DateComponents(); components.hour = reminder.hour; components.minute = reminder.minute; components.second = 0
        return calendar.nextDate(after: date, matching: components, matchingPolicy: .nextTime, repeatedTimePolicy: .first, direction: .forward)
    }
    private func day(_ date: Date) -> String {
        let c = calendar().dateComponents([.era, .year, .month, .day], from: date)
        return "\(c.era ?? 0)-\(c.year ?? 0)-\(c.month ?? 0)-\(c.day ?? 0)"
    }
    func replace(_ reminders: [Reminder]) {
        var copy = data; copy.reminders = reminders
        let ids = Set(reminders.map { $0.id.uuidString })
        copy.delivered = copy.delivered.filter { ids.contains($0.key) }
        persist(copy); schedule()
    }
    @discardableResult func dismiss(_ id: UUID) -> Bool {
        var copy = data; copy.pending.removeAll { $0.id == id }; return persist(copy)
    }
    @discardableResult private func persist(_ copy: ReminderData) -> Bool {
        guard ready else { return false }
        do { try store.save(copy); data = copy; error = nil; return true } catch { self.error = error.localizedDescription; return false }
    }
    func schedule() {
        timer?.invalidate(); timer = nil
        guard ready else { return }
        let current = now(), cal = calendar()
        guard let fire = data.reminders.compactMap({ Self.next($0, after: current, calendar: cal) }).min() else { return }
        timer = Timer(fire: fire, interval: 0, repeats: false) { [weak self] _ in
            Task { @MainActor in self?.fire(expected: fire) }
        }
        if let timer { RunLoop.main.add(timer, forMode: .common) }
    }
    #if DEBUG
    var scheduledFireDateForTesting: Date? { timer?.fireDate }

    func fireForTesting(expected: Date) {
        fire(expected: expected)
    }
    #endif

    private func fire(expected: Date) {
        let current = now()
        // Reject early callbacks and callbacks at least 60 seconds late.
        guard current.timeIntervalSince(expected) >= 0, current.timeIntervalSince(expected) < 60 else { schedule(); return }
        var copy = data
        let today = day(current)
        copy.delivered = copy.delivered.filter { $0.value == today }
        let due = copy.reminders.filter { reminder in
            guard reminder.enabled, copy.delivered[reminder.id.uuidString] != today,
                  let occurrence = Self.next(reminder, after: expected.addingTimeInterval(-1), calendar: calendar()) else { return false }
            return abs(occurrence.timeIntervalSince(expected)) < 1
        }
        let deliveries = due.map { PendingReminder(reminder: $0) }
        for delivery in deliveries { copy.delivered[delivery.reminder.id.uuidString] = today; copy.pending.append(delivery) }
        persist(copy)
        if error == nil { deliveries.forEach { onDelivery?($0) } }
        schedule()
    }
}
