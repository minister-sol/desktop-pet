// ReminderStore.swift
// Independent atomic persistence for reminders and delivery state.
import Foundation

struct PendingReminder: Codable, Identifiable {
    var id = UUID()
    var reminder: Reminder
}

struct ReminderData: Codable {
    var reminders: [Reminder] = []
    var delivered: [String: String] = [:]
    var pending: [PendingReminder] = []
}

final class ReminderStore {
    let url: URL
    init(url: URL? = nil) {
        self.url = url ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("DesktopPet", isDirectory: true).appendingPathComponent("reminders.plist")
    }
    func load() throws -> ReminderData {
        guard FileManager.default.fileExists(atPath: url.path) else { return ReminderData() }
        let data = try PropertyListDecoder().decode(ReminderData.self, from: Data(contentsOf: url))
        try data.reminders.forEach { try $0.validate() }
        return data
    }
    func save(_ data: ReminderData) throws {
        try data.reminders.forEach { try $0.validate() }
        let encoded = try PropertyListEncoder().encode(data)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try encoded.write(to: url, options: .atomic)
    }
}
