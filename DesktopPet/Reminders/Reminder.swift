// Reminder.swift
// Validated local daily reminder data.
import Foundation

struct Reminder: Codable, Identifiable, Equatable {
    var id = UUID()
    var text: String
    var hour: Int
    var minute: Int
    var enabled = true

    func validate() throws {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              text.count <= 200, (0...23).contains(hour), (0...59).contains(minute) else {
            throw ReminderError.invalidReminder
        }
    }
}

enum ReminderError: LocalizedError {
    case invalidReminder
    var errorDescription: String? { "Enter text of at most 200 characters and a valid time." }
}
