// ReminderScheduler.swift
// Schedules future local daily occurrences and preserves pending deliveries.
import AppKit
import Combine

@MainActor final class ReminderScheduler: ObservableObject {
    @Published private(set) var data = ReminderData()
    @Published var error: String?
    var onDelivery: ((Reminder) -> Void)?
    private let store: ReminderStore
    private let now: () -> Date
    private let calendar: () -> Calendar
    private var timer: Timer?
    private var observers: [NSObjectProtocol] = []
    private var ready = false

    init(store: ReminderStore = ReminderStore(), now: @escaping () -> Date = Date.init,
         calendar: @escaping () -> Calendar = { Calendar.current }) {
        self.store = store; self.now = now; self.calendar = calendar
        do { data = try store.load(); ready = true } catch { self.error = error.localizedDescription }
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
    func dismiss(_ id: UUID) {
        var copy = data; copy.pending.removeAll { $0.id == id }; persist(copy)
    }
    private func persist(_ copy: ReminderData) {
        guard ready else { return }
        do { try store.save(copy); data = copy; error = nil } catch { self.error = error.localizedDescription }
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
    private func fire(expected: Date) {
        let current = now()
        // A late callback after sleep or a clock jump is skipped.
        guard current.timeIntervalSince(expected) >= 0, current.timeIntervalSince(expected) < 60 else { schedule(); return }
        var copy = data
        let today = day(current)
        copy.delivered = copy.delivered.filter { $0.value == today }
        let due = copy.reminders.filter { reminder in
            guard reminder.enabled, copy.delivered[reminder.id.uuidString] != today,
                  let occurrence = Self.next(reminder, after: expected.addingTimeInterval(-1), calendar: calendar()) else { return false }
            return abs(occurrence.timeIntervalSince(expected)) < 1
        }
        for reminder in due { copy.delivered[reminder.id.uuidString] = today; copy.pending.append(PendingReminder(reminder: reminder)) }
        persist(copy)
        if error == nil { due.forEach { onDelivery?($0) } }
        schedule()
    }
}
