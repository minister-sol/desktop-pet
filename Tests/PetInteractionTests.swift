// PetInteractionTests.swift
// Verifies the distance threshold used to distinguish clicks from drags.

import XCTest
import AppKit
@testable import DesktopPet

final class PetInteractionTests: XCTestCase {
    func testAnimationSpeedClampsToSupportedRange() {
        let player = AnimationPlayer()
        player.speed = 0.01
        XCTAssertEqual(player.speed, 0.1, accuracy: 0.001)
        player.speed = 12
        XCTAssertEqual(player.speed, 8, accuracy: 0.001)
        player.speed = 2.5
        XCTAssertEqual(player.speed, 2.5, accuracy: 0.001)
    }

    func testAnimationSpeedConcurrentReadsAndWritesRemainInRange() {
        let player = AnimationPlayer()
        let resultLock = NSLock()
        var invalidReads = 0
        DispatchQueue.concurrentPerform(iterations: 1000) { index in
            player.speed = index.isMultiple(of: 2) ? 0.01 : 12
            let value = player.speed
            if value < 0.1 || value > 8 {
                resultLock.lock()
                invalidReads += 1
                resultLock.unlock()
            }
        }
        XCTAssertEqual(invalidReads, 0)
    }

    @MainActor
    func testSecurityScopeSameURLReplacementBalancesAccess() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("frame.png")
        let png = try XCTUnwrap(Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR4nGP4z8DwHwAFAAH/iZk9HQAAAABJRU5ErkJggg=="))
        try png.write(to: file)
        let invalid = directory.appendingPathComponent("invalid.png")
        let other = directory.appendingPathComponent("other.png")
        try Data("invalid".utf8).write(to: invalid)
        try png.write(to: other)
        _ = NSApplication.shared
        var starts = 0
        var stops: [URL] = []
        var record = PetRecord.default(instanceID: "scope-test", index: 1)
        record.playing = false
        var controller: OverlayWindowController? = OverlayWindowController(settings: AppSettings(record: record),
            resolveBookmark: { data in data == Data([4]) ? invalid : (data == Data([5]) ? other : file) },
            startAccess: { _ in starts += 1; return starts != 3 },
            stopAccess: { stops.append($0) })
        func load(_ data: Data) async -> Bool {
            await withCheckedContinuation { continuation in
                controller?.loadAssetFromBookmark(data) { continuation.resume(returning: $0) }
            }
        }
        let first = await load(Data([1])); XCTAssertTrue(first)
        let second = await load(Data([2])); XCTAssertTrue(second)
        XCTAssertEqual(stops, [file])
        let third = await load(Data([3])); XCTAssertTrue(third)
        let ordinary: Bool = await withCheckedContinuation { continuation in
            controller?.loadAsset(url: file) { continuation.resume(returning: $0) }
        }
        XCTAssertTrue(ordinary)
        let failed = await load(Data([4])); XCTAssertFalse(failed)
        XCTAssertEqual(stops, [file, file, invalid])
        let replacement = await load(Data([5])); XCTAssertTrue(replacement)
        XCTAssertEqual(stops, [file, file, invalid, file])
        controller = nil
        XCTAssertEqual(stops, [file, file, invalid, file, other])
    }

    @MainActor
    func testSupersededDecodeDoesNotReplaceNewerAssetAndReleasesScope() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let slow = directory.appendingPathComponent("slow.png")
        let fast = directory.appendingPathComponent("fast.png")
        let png = try XCTUnwrap(Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR4nGP4z8DwHwAFAAH/iZk9HQAAAABJRU5ErkJggg=="))
        try png.write(to: slow); try png.write(to: fast)
        let started = expectation(description: "background decode started")
        let oldDone = expectation(description: "old request finished")
        let newDone = expectation(description: "new request finished")
        let gate = DispatchSemaphore(value: 0)
        var stopped: [URL] = []
        let settings = AppSettings(record: .default(instanceID: "async-test", index: 1))
        let controller = OverlayWindowController(settings: settings,
            resolveBookmark: { $0 == Data([1]) ? slow : fast },
            startAccess: { _ in true }, stopAccess: { stopped.append($0) },
            decodeFrames: { url in
                if url == slow { XCTAssertFalse(Thread.isMainThread); started.fulfill(); gate.wait() }
                return APNGDecoder.decode(url: url)
            })
        controller.loadAssetFromBookmark(Data([1])) { success in XCTAssertFalse(success); oldDone.fulfill() }
        await fulfillment(of: [started], timeout: 5)
        controller.loadAssetFromBookmark(Data([2])) { success in XCTAssertTrue(success); newDone.fulfill() }
        await fulfillment(of: [newDone], timeout: 5)
        gate.signal()
        await fulfillment(of: [oldDone], timeout: 5)
        XCTAssertEqual(settings.assetBookmark, Data([2]))
        XCTAssertEqual(stopped, [slow])
        withExtendedLifetime(controller) {}
    }

    @MainActor
    func testDestroyedControllerReleasesInFlightScope() async {
        let started = expectation(description: "decode started")
        let finished = expectation(description: "decode finished")
        let gate = DispatchSemaphore(value: 0)
        let url = URL(fileURLWithPath: "/tmp/desktop-pet-inflight.png")
        var stopped: [URL] = []
        var controller: OverlayWindowController? = OverlayWindowController(
            settings: AppSettings(record: .default(instanceID: "destroy-test", index: 1)),
            resolveBookmark: { _ in url }, startAccess: { _ in true }, stopAccess: { stopped.append($0) },
            decodeFrames: { _ in started.fulfill(); gate.wait(); return nil })
        controller?.loadAssetFromBookmark(Data([1])) { success in XCTAssertFalse(success); finished.fulfill() }
        await fulfillment(of: [started], timeout: 5)
        weak var weakController = controller
        controller = nil
        XCTAssertNil(weakController)
        gate.signal()
        await fulfillment(of: [finished], timeout: 5)
        XCTAssertEqual(stopped, [url])
    }

    @MainActor
    func testDirectReloadKeepsIndependentScopeUntilDecodeCompletes() async throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".png")
        let png = try XCTUnwrap(Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR4nGP4z8DwHwAFAAH/iZk9HQAAAABJRU5ErkJggg=="))
        try png.write(to: file)
        defer { try? FileManager.default.removeItem(at: file) }
        let started = expectation(description: "reload started")
        let finished = expectation(description: "reload finished")
        let gate2 = DispatchSemaphore(value: 0)
        var starts = 0
        var stops = 0
        var controller: OverlayWindowController?
        var decodeCount = 0
        let lock = NSLock()
        controller = OverlayWindowController(settings: AppSettings(record: .default(instanceID: "reload2", index: 2)),
            resolveBookmark: { _ in file }, startAccess: { _ in starts += 1; return true }, stopAccess: { _ in stops += 1 },
            decodeFrames: { url in
                lock.lock(); decodeCount += 1; let count = decodeCount; lock.unlock()
                if count == 2 { started.fulfill(); gate2.wait() }
                return APNGDecoder.decode(url: url)
            })
        let loaded: Bool = await withCheckedContinuation { continuation in
            controller?.loadAssetFromBookmark(Data([1])) { continuation.resume(returning: $0) }
        }
        XCTAssertTrue(loaded)
        controller?.loadAsset(url: file) { success in XCTAssertFalse(success); finished.fulfill() }
        await fulfillment(of: [started], timeout: 5)
        controller = nil
        XCTAssertEqual(starts, 2)
        XCTAssertEqual(stops, 1)
        gate2.signal()
        await fulfillment(of: [finished], timeout: 5)
        XCTAssertEqual(stops, 2)
    }

    @MainActor
    func testDirectReloadRejectsFailedIndependentScope() async throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".png")
        let png = try XCTUnwrap(Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR4nGP4z8DwHwAFAAH/iZk9HQAAAABJRU5ErkJggg=="))
        try png.write(to: file)
        defer { try? FileManager.default.removeItem(at: file) }
        var starts = 0
        let controller = OverlayWindowController(settings: AppSettings(record: .default(instanceID: "scope-failure", index: 1)),
            resolveBookmark: { _ in file }, startAccess: { _ in starts += 1; return starts == 1 }, stopAccess: { _ in })
        let initial: Bool = await withCheckedContinuation { continuation in
            controller.loadAssetFromBookmark(Data([1])) { continuation.resume(returning: $0) }
        }
        XCTAssertTrue(initial)
        let reload: Bool = await withCheckedContinuation { continuation in
            controller.loadAsset(url: file) { continuation.resume(returning: $0) }
        }
        XCTAssertFalse(reload)
        XCTAssertEqual(starts, 2)
    }

    @MainActor
    func testRestoredPetsRetainSavedOrderWhenLoadsFinishOutOfOrder() {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let store = PetsStore(storeURL: directory.appendingPathComponent("pets.plist"))
        let scheduler = ReminderScheduler(store: ReminderStore(url: directory.appendingPathComponent("reminders.plist")))
        let delegate = AppDelegate(petsStore: store, scheduler: scheduler, pets: [])
        delegate.setRestorationOrderForTesting(["a", "b", "c"])
        for id in ["c", "a", "b"] {
            delegate.insertRestoredPetForTesting(OverlayWindowController(settings: AppSettings(record: .default(instanceID: id, index: 1))))
        }
        XCTAssertEqual(delegate.restoredPetIDsForTesting, ["a", "b", "c"])
        try? FileManager.default.removeItem(at: directory)
    }

    #if DEBUG
    func testHostedTestsUseIsolatedStartup() async {
        await MainActor.run {
            XCTAssertEqual(ProcessInfo.processInfo.environment["DESKTOP_PET_TEST_HOST"], "1")
            XCTAssertTrue(NSApplication.shared.delegate is IsolatedTestHostDelegate,
                          "The isolated test host delegate must be installed")
        }
    }
    #endif

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
    #if DEBUG
    func testStaleCallbackAfterDisablingOrDeletingReminderDoesNotDeliver() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = ReminderStore(url: directory.appendingPathComponent("reminders.plist"))
        var reminder = Reminder(text: "Due", hour: 9, minute: 0)
        var initial = ReminderData()
        initial.reminders = [reminder]
        try store.save(initial)

        try await MainActor.run {
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = try XCTUnwrap(TimeZone(secondsFromGMT: 0))
            let due = try XCTUnwrap(calendar.date(from: DateComponents(year: 2099, month: 1, day: 1, hour: 9)))
            let scheduler = ReminderScheduler(store: store, now: { due }, calendar: { calendar })
            var deliveries: [UUID] = []
            scheduler.onDelivery = { deliveries.append($0.reminder.id) }

            reminder.enabled = false
            scheduler.replace([reminder])
            XCTAssertNil(scheduler.error)
            scheduler.fireForTesting(expected: due)
            XCTAssertTrue(deliveries.isEmpty)
            XCTAssertTrue(scheduler.data.pending.isEmpty)
            scheduler.replace([])
            XCTAssertNil(scheduler.error)
            scheduler.fireForTesting(expected: due)
            XCTAssertTrue(deliveries.isEmpty)
            XCTAssertTrue(scheduler.data.pending.isEmpty)
        }
    }

    func testReplacingEnabledReminderUpdatesScheduledTime() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = ReminderStore(url: directory.appendingPathComponent("reminders.plist"))
        var reminder = Reminder(text: "Daily", hour: 9, minute: 0)
        var initial = ReminderData()
        initial.reminders = [reminder]
        try store.save(initial)

        try await MainActor.run {
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = try XCTUnwrap(TimeZone(secondsFromGMT: 0))
            let current = try XCTUnwrap(calendar.date(from: DateComponents(year: 2099, month: 1, day: 1, hour: 8)))
            let due = try XCTUnwrap(calendar.date(from: DateComponents(year: 2099, month: 1, day: 1, hour: 9)))
            let scheduler = ReminderScheduler(store: store, now: { current }, calendar: { calendar })
            XCTAssertEqual(scheduler.scheduledFireDateForTesting, due)
            reminder.enabled = false
            scheduler.replace([reminder])
            XCTAssertNil(scheduler.error)
            XCTAssertNil(scheduler.scheduledFireDateForTesting)
            reminder.enabled = true
            scheduler.replace([reminder])
            XCTAssertNil(scheduler.error)
            XCTAssertEqual(scheduler.scheduledFireDateForTesting, due)
            scheduler.replace([])
            XCTAssertNil(scheduler.error)
            XCTAssertNil(scheduler.scheduledFireDateForTesting)
        }
        XCTAssertTrue(try store.load().reminders.isEmpty)
    }

    func testEarlyAndLateCallbacksRespectSixtySecondBoundary() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = ReminderStore(url: directory.appendingPathComponent("reminders.plist"))
        let reminder = Reminder(text: "Due", hour: 9, minute: 0)
        var initial = ReminderData()
        initial.reminders = [reminder]
        try store.save(initial)

        try await MainActor.run {
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = try XCTUnwrap(TimeZone(secondsFromGMT: 0))
            let due = try XCTUnwrap(calendar.date(from: DateComponents(year: 2099, month: 1, day: 1, hour: 9)))
            var current = due.addingTimeInterval(-0.1)
            let scheduler = ReminderScheduler(store: store, now: { current }, calendar: { calendar })
            var deliveries: [UUID] = []
            scheduler.onDelivery = { deliveries.append($0.reminder.id) }
            scheduler.fireForTesting(expected: due)
            XCTAssertTrue(deliveries.isEmpty)
            XCTAssertTrue(scheduler.data.pending.isEmpty)

            current = due.addingTimeInterval(60)
            scheduler.fireForTesting(expected: due)
            XCTAssertTrue(deliveries.isEmpty)
            XCTAssertTrue(scheduler.data.pending.isEmpty)
            XCTAssertTrue(scheduler.data.delivered.isEmpty)

            current = due.addingTimeInterval(59.9)
            scheduler.fireForTesting(expected: due)
            XCTAssertEqual(deliveries, [reminder.id])
            XCTAssertEqual(scheduler.data.pending.map(\.reminder.id), [reminder.id])
        }
    }

    func testReschedulingAfterMissedOccurrenceSelectsNextDay() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = ReminderStore(url: directory.appendingPathComponent("reminders.plist"))
        var initial = ReminderData()
        initial.reminders = [Reminder(text: "Due", hour: 9, minute: 0)]
        try store.save(initial)

        try await MainActor.run {
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = try XCTUnwrap(TimeZone(secondsFromGMT: 0))
            let due = try XCTUnwrap(calendar.date(from: DateComponents(year: 2099, month: 1, day: 1, hour: 9)))
            var current = due.addingTimeInterval(-60)
            let scheduler = ReminderScheduler(store: store, now: { current }, calendar: { calendar })
            XCTAssertEqual(scheduler.scheduledFireDateForTesting, due)
            current = due.addingTimeInterval(120)
            scheduler.schedule()
            XCTAssertEqual(scheduler.scheduledFireDateForTesting, calendar.date(byAdding: .day, value: 1, to: due))
            XCTAssertTrue(scheduler.data.pending.isEmpty)
        }
    }

    func testDueCallbacksDeliverTogetherDeduplicateAndResetNextDay() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = ReminderStore(url: directory.appendingPathComponent("reminders.plist"))
        let first = Reminder(text: "First", hour: 9, minute: 0)
        let second = Reminder(text: "Second", hour: 9, minute: 0)
        var initial = ReminderData()
        initial.reminders = [first, second]
        let staleID = UUID().uuidString
        initial.delivered[staleID] = "1-2098-12-31"
        try store.save(initial)

        try await MainActor.run {
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = try XCTUnwrap(TimeZone(secondsFromGMT: 0))
            var current = try XCTUnwrap(calendar.date(from: DateComponents(year: 2099, month: 1, day: 1, hour: 9)))
            let scheduler = ReminderScheduler(store: store, now: { current }, calendar: { calendar })
            var deliveries: [UUID] = []
            scheduler.onDelivery = { deliveries.append($0.reminder.id) }

            scheduler.fireForTesting(expected: current)
            XCTAssertEqual(deliveries, [first.id, second.id])
            XCTAssertNil(scheduler.data.delivered[staleID])
            XCTAssertEqual(scheduler.data.pending.map(\.reminder.id), [first.id, second.id])
            XCTAssertEqual(try store.load().pending.map(\.reminder.id), [first.id, second.id])
            scheduler.fireForTesting(expected: current)
            XCTAssertEqual(deliveries, [first.id, second.id])
            XCTAssertEqual(scheduler.data.pending.count, 2)

            current = try XCTUnwrap(calendar.date(byAdding: .day, value: 1, to: current))
            scheduler.fireForTesting(expected: current)
            XCTAssertEqual(deliveries, [first.id, second.id, first.id, second.id])
            XCTAssertEqual(scheduler.data.pending.count, 4)
            XCTAssertEqual(Set(scheduler.data.delivered.values), ["1-2099-1-2"])
        }
    }

    func testDueCallbackDoesNotDeliverWhenPersistenceFails() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = ReminderStore(url: directory.appendingPathComponent("reminders.plist"))
        var initial = ReminderData()
        initial.reminders = [Reminder(text: "Due", hour: 9, minute: 0)]
        try store.save(initial)

        try await MainActor.run {
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = try XCTUnwrap(TimeZone(secondsFromGMT: 0))
            let current = try XCTUnwrap(calendar.date(from: DateComponents(year: 2099, month: 1, day: 1, hour: 9)))
            let scheduler = ReminderScheduler(store: store, now: { current }, calendar: { calendar })
            var deliveries: [UUID] = []
            scheduler.onDelivery = { deliveries.append($0.reminder.id) }
            try FileManager.default.removeItem(at: directory)
            try Data("blocking file".utf8).write(to: directory)
            scheduler.fireForTesting(expected: current)
            XCTAssertTrue(deliveries.isEmpty)
            XCTAssertTrue(scheduler.data.pending.isEmpty)
            XCTAssertTrue(scheduler.data.delivered.isEmpty)
            XCTAssertNotNil(scheduler.error)
        }
    }
    #endif

    func testDeletingReminderRemovesOnlyItsDeliveredMarker() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = ReminderStore(url: directory.appendingPathComponent("reminders.plist"))
        let first = Reminder(text: "First", hour: 9, minute: 0)
        let second = Reminder(text: "Second", hour: 10, minute: 0)
        var initial = ReminderData()
        initial.reminders = [first, second]
        initial.delivered = [first.id.uuidString: "1-2026-1-1", second.id.uuidString: "1-2026-1-1"]
        try store.save(initial)

        await MainActor.run {
            let scheduler = ReminderScheduler(store: store)
            scheduler.replace([second])
            XCTAssertNil(scheduler.error)
            XCTAssertNil(scheduler.data.delivered[first.id.uuidString])
            XCTAssertEqual(scheduler.data.delivered[second.id.uuidString], "1-2026-1-1")
        }
        let saved = try store.load()
        XCTAssertNil(saved.delivered[first.id.uuidString])
        XCTAssertEqual(saved.delivered[second.id.uuidString], "1-2026-1-1")
    }

    func testReminderAcceptsTextAtCharacterLimit() {
        let reminder = Reminder(text: String(repeating: "字", count: 200), hour: 23, minute: 59)
        XCTAssertNoThrow(try reminder.validate())
    }

    func testReminderRejectsTextOverCharacterLimit() {
        let reminder = Reminder(text: String(repeating: "字", count: 201), hour: 0, minute: 0)
        XCTAssertThrowsError(try reminder.validate())
    }

    func testReminderRejectsInvalidHoursAndMinutes() {
        for (hour, minute) in [(-1, 0), (24, 0), (0, -1), (0, 60)] {
            let reminder = Reminder(text: "Invalid", hour: hour, minute: minute)
            XCTAssertThrowsError(try reminder.validate(), "Expected \(hour):\(minute) to be rejected")
        }
    }

    #if DEBUG
    func testAppDelegateRedistributesPendingWhenPetsHideShowAndAreRemoved() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let suiteName = "DesktopPetTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer {
            defaults.removePersistentDomain(forName: suiteName)
            try? FileManager.default.removeItem(at: directory)
        }
        let store = ReminderStore(url: directory.appendingPathComponent("reminders.plist"))
        let first = PendingReminder(reminder: Reminder(text: "First", hour: 9, minute: 0))
        let second = PendingReminder(reminder: Reminder(text: "Second", hour: 9, minute: 0))
        var data = ReminderData()
        data.pending = [first, second]
        try store.save(data)

        await MainActor.run {
            _ = NSApplication.shared
            let scheduler = ReminderScheduler(store: store)
            let petsStore = PetsStore(defaults: defaults, storeURL: directory.appendingPathComponent("pets.plist"))
            let petA = OverlayWindowController(settings: AppSettings(record: .default(instanceID: "a", index: 1)))
            let petB = OverlayWindowController(settings: AppSettings(record: .default(instanceID: "b", index: 2)))
            let delegate = AppDelegate(petsStore: petsStore, scheduler: scheduler, pets: [petA, petB])
            defer { petA.window?.close(); petB.window?.close(); withExtendedLifetime(delegate) {} }

            func displayedText(_ pet: OverlayWindowController) -> String? {
                pet.window?.contentView?.subviews.first?.subviews.last?.subviews
                    .compactMap { $0 as? NSTextField }.first?.stringValue
            }

            petA.setVisible(true)
            petB.setVisible(true)
            XCTAssertEqual(displayedText(petA), "First")
            XCTAssertNil(displayedText(petB))
            petA.setVisible(false)
            XCTAssertNil(displayedText(petA))
            XCTAssertEqual(displayedText(petB), "First")
            petA.setVisible(true)
            XCTAssertEqual(displayedText(petA), "First")
            XCTAssertNil(displayedText(petB))
            delegate.removePet(id: "a")
            XCTAssertEqual(displayedText(petB), "First")
            XCTAssertTrue(scheduler.dismiss(first.id))
            XCTAssertEqual(displayedText(petB), "Second")
            petB.setVisible(false)
            XCTAssertNil(displayedText(petB))
            XCTAssertEqual(scheduler.data.pending.map(\.id), [second.id])
            petB.setVisible(true)
            XCTAssertEqual(displayedText(petB), "Second")
        }
    }
    #endif

    func testDismissingOnePendingReminderPersistsRemainingQueue() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = ReminderStore(url: directory.appendingPathComponent("reminders.plist"))
        let first = PendingReminder(reminder: Reminder(text: "First", hour: 9, minute: 0))
        let second = PendingReminder(reminder: Reminder(text: "Second", hour: 9, minute: 0))
        var initial = ReminderData()
        initial.pending = [first, second]
        try store.save(initial)

        await MainActor.run {
            let scheduler = ReminderScheduler(store: store)
            XCTAssertTrue(scheduler.dismiss(first.id))
            XCTAssertEqual(scheduler.data.pending.map(\.id), [second.id])
            XCTAssertNil(scheduler.error)
        }
        XCTAssertEqual(try store.load().pending.map(\.id), [second.id])
    }

    func testFailedPendingDismissalKeepsOriginalQueue() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("reminders.plist")
        let store = ReminderStore(url: file)
        let pending = PendingReminder(reminder: Reminder(text: "Pending", hour: 9, minute: 0))
        var initial = ReminderData()
        initial.pending = [pending]
        try store.save(initial)

        try await MainActor.run {
            let scheduler = ReminderScheduler(store: store)
            // Replace the temporary parent directory with a regular file to force a write failure.
            try FileManager.default.removeItem(at: directory)
            try Data("blocking file".utf8).write(to: directory)
            XCTAssertFalse(scheduler.dismiss(pending.id))
            XCTAssertEqual(scheduler.data.pending.map(\.id), [pending.id])
            XCTAssertNotNil(scheduler.error)
        }
    }

    func testDisabledReminderHasNoNextOccurrence() async {
        await MainActor.run {
            let reminder = Reminder(text: "Disabled", hour: 9, minute: 0, enabled: false)
            XCTAssertNil(ReminderScheduler.next(reminder, after: Date(), calendar: Calendar(identifier: .gregorian)))
        }
    }

    func testNextOccurrenceAfterExactTimeIsFollowingDay() async throws {
        try await MainActor.run {
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = try XCTUnwrap(TimeZone(secondsFromGMT: 0))
            let date = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 1, day: 1, hour: 9)))
            let reminder = Reminder(text: "Daily", hour: 9, minute: 0)
            let next = try XCTUnwrap(ReminderScheduler.next(reminder, after: date, calendar: calendar))
            XCTAssertEqual(calendar.dateComponents([.year, .month, .day, .hour, .minute], from: next),
                           DateComponents(year: 2026, month: 1, day: 2, hour: 9, minute: 0))
        }
    }

    func testRepeatedDaylightSavingTimeUsesFirstOccurrence() async throws {
        try await MainActor.run {
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "America/New_York"))
            let start = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 11, day: 1, hour: 0)))
            let reminder = Reminder(text: "Repeated hour", hour: 1, minute: 30)
            let next = try XCTUnwrap(ReminderScheduler.next(reminder, after: start, calendar: calendar))
            XCTAssertEqual(next.timeIntervalSince1970, 1_793_511_000, accuracy: 1)
        }
    }

    func testCorruptStoreCannotBeOverwrittenByReplacement() async throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let original = Data("not a property list".utf8)
        try original.write(to: file)
        defer { try? FileManager.default.removeItem(at: file) }
        let store = ReminderStore(url: file)

        await MainActor.run {
            let scheduler = ReminderScheduler(store: store)
            XCTAssertFalse(scheduler.ready)
            XCTAssertNotNil(scheduler.loadError)
            scheduler.replace([Reminder(text: "New", hour: 9, minute: 0)])
            XCTAssertNotNil(scheduler.loadError)
            XCTAssertTrue(scheduler.data.reminders.isEmpty)
        }
        XCTAssertEqual(try Data(contentsOf: file), original)
    }

    func testReplacingRemindersPersistsDeletion() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = ReminderStore(url: directory.appendingPathComponent("reminders.plist"))
        let first = Reminder(text: "First", hour: 9, minute: 0)
        let second = Reminder(text: "Second", hour: 10, minute: 0)
        var initial = ReminderData()
        initial.reminders = [first, second]
        try store.save(initial)

        await MainActor.run {
            let scheduler = ReminderScheduler(store: store)
            scheduler.replace([second])
            XCTAssertNil(scheduler.error)
            XCTAssertEqual(scheduler.data.reminders, [second])
        }
        XCTAssertEqual(try store.load().reminders, [second])
    }

    func testFailedReplacementPreservesSchedulerData() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = ReminderStore(url: directory.appendingPathComponent("reminders.plist"))
        let original = Reminder(text: "Original", hour: 9, minute: 0)
        var initial = ReminderData()
        initial.reminders = [original]
        try store.save(initial)

        await MainActor.run {
            let scheduler = ReminderScheduler(store: store)
            scheduler.replace([Reminder(text: " ", hour: 9, minute: 0)])
            XCTAssertNotNil(scheduler.error)
            XCTAssertEqual(scheduler.data.reminders, [original])
        }
        XCTAssertEqual(try store.load().reminders, [original])
    }

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
