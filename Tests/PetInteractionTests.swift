// PetInteractionTests.swift
// Verifies the distance threshold used to distinguish clicks from drags.

import XCTest
@testable import DesktopPet

final class PetInteractionTests: XCTestCase {
    func testMovementBelowFourPointsIsClick() {
        XCTAssertFalse(PetInteraction.isDrag(deltaX: 3, deltaY: 2))
    }

    func testMovementAtFourPointsIsDrag() {
        XCTAssertTrue(PetInteraction.isDrag(deltaX: 4, deltaY: 0))
    }

    func testDiagonalMovementUsesDistance() {
        XCTAssertTrue(PetInteraction.isDrag(deltaX: 3, deltaY: 3))
        XCTAssertTrue(PetInteraction.isDrag(deltaX: -4, deltaY: 0))
    }
}

final class ReminderTests: XCTestCase {
    func testNextOccurrenceCrossesMidnight() async {
        await MainActor.run {
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = TimeZone(secondsFromGMT: 0)!
            let now = calendar.date(from: DateComponents(year: 2026, month: 1, day: 1, hour: 23, minute: 59))!
            let reminder = Reminder(text: "Midnight", hour: 0, minute: 1)
            let next = ReminderScheduler.next(reminder, after: now, calendar: calendar)!
            XCTAssertEqual(calendar.dateComponents([.day, .hour, .minute], from: next), DateComponents(day: 2, hour: 0, minute: 1))
        }
    }

    func testNextOccurrenceUsesCurrentTimeZone() async {
        await MainActor.run {
            var utc = Calendar(identifier: .gregorian)
            utc.timeZone = TimeZone(secondsFromGMT: 0)!
            var east = utc
            east.timeZone = TimeZone(secondsFromGMT: 8 * 3600)!
            let now = utc.date(from: DateComponents(year: 2026, month: 1, day: 1, hour: 0))!
            let reminder = Reminder(text: "Morning", hour: 9, minute: 0)
            let utcNext = ReminderScheduler.next(reminder, after: now, calendar: utc)!
            let eastNext = ReminderScheduler.next(reminder, after: now, calendar: east)!
            XCTAssertEqual(utcNext.timeIntervalSince(eastNext), 8 * 3600, accuracy: 1)
        }
    }

    func testMultipleRemindersSurviveSaveAndLoad() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = ReminderStore(url: directory.appendingPathComponent("reminders.plist"))
        var data = ReminderData()
        data.reminders = [Reminder(text: "One", hour: 9, minute: 0), Reminder(text: "Two", hour: 9, minute: 0)]
        try store.save(data)
        XCTAssertEqual(try store.load().reminders, data.reminders)
    }

    func testSaveFailurePreservesExistingData() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("reminders.plist")
        let store = ReminderStore(url: file)
        var data = ReminderData()
        data.reminders = [Reminder(text: "Original", hour: 9, minute: 0)]
        try store.save(data)
        data.reminders.append(Reminder(text: " ", hour: 9, minute: 0))
        XCTAssertThrowsError(try store.save(data))
        XCTAssertEqual(try store.load().reminders.map(\.text), ["Original"])
    }

    func testWriteFailureIsReported() throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try Data("existing".utf8).write(to: file)
        defer { try? FileManager.default.removeItem(at: file) }
        let store = ReminderStore(url: file.appendingPathComponent("reminders.plist"))
        XCTAssertThrowsError(try store.save(ReminderData()))
        XCTAssertEqual(try Data(contentsOf: file), Data("existing".utf8))
    }
}

