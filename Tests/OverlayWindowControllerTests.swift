import AppKit
import Foundation

@main
struct OverlayWindowControllerTests {
    static func main() throws {
        _ = NSApplication.shared

        var record = PetRecord.default(instanceID: "pet-1", index: 1)
        record.assetBookmark = Data([0xAA, 0xBB, 0xCC])
        let settings = AppSettings(record: record)
        let controller = OverlayWindowController(settings: settings)

        let originalBookmark = settings.assetBookmark
        guard originalBookmark != nil else {
            throw TestFailure("Expected fixture bookmark to exist before invalid load")
        }

        let invalidURL = FileManager.default.temporaryDirectory.appendingPathComponent("desktop-pet-invalid.txt")
        try "not an animation".write(to: invalidURL, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: invalidURL) }

        if controller.loadAsset(url: invalidURL) {
            throw TestFailure("Expected invalid asset load to fail")
        }

        if settings.assetBookmark != originalBookmark {
            throw TestFailure("Failed load should not overwrite the existing bookmark")
        }

        let first = PendingReminder(reminder: Reminder(text: "First", hour: 9, minute: 0))
        let second = PendingReminder(reminder: Reminder(text: "Second", hour: 9, minute: 0))
        var dismissed: [UUID] = []
        controller.showReminder(first) { dismissed.append($0); return true }
        controller.showReminder(second) { dismissed.append($0); return true }
        guard let petView = controller.window?.contentView?.subviews.first,
              let container = petView.subviews.last,
              let label = container.subviews.compactMap({ $0 as? NSTextField }).first,
              let button = container.subviews.compactMap({ $0 as? NSButton }).first else {
            throw TestFailure("Expected a reminder and its dismissal button")
        }
        if label.stringValue != "First" { throw TestFailure("First reminder must remain visible") }
        button.performClick(nil)
        if dismissed != [first.id] { throw TestFailure("Dismissal must identify the first reminder") }
        controller.retainReminders(ids: [second.id])
        guard let nextContainer = petView.subviews.last,
              let nextLabel = nextContainer.subviews.compactMap({ $0 as? NSTextField }).first,
              nextLabel.stringValue == "Second" else {
            throw TestFailure("Second reminder must appear after the first is dismissed")
        }
        controller.retainReminders(ids: [])
        if petView.subviews.contains(where: { $0.subviews.contains(where: { ($0 as? NSTextField)?.stringValue == "Second" }) }) {
            throw TestFailure("Removing a pending reminder must remove its overlay")
        }

        controller.showReminder(first) { _ in false }
        guard let failureContainer = petView.subviews.last,
              let failureButton = failureContainer.subviews.compactMap({ $0 as? NSButton }).first,
              let failureLabel = failureContainer.subviews.compactMap({ $0 as? NSTextField }).first else {
            throw TestFailure("Expected retryable reminder")
        }
        failureButton.performClick(nil)
        if !failureLabel.stringValue.contains("Could not dismiss") {
            throw TestFailure("Failed dismissal must show retry guidance")
        }

        // Exercise queue handoff between two controllers using the same pending IDs.
        let other = OverlayWindowController(settings: AppSettings(record: .default(instanceID: "pet-2", index: 2)))
        controller.retainReminders(ids: [])
        other.showReminder(first) { _ in true }
        other.showReminder(second) { _ in true }
        other.showReminder(first) { _ in true }
        guard let otherView = other.window?.contentView?.subviews.first,
              let otherContainer = otherView.subviews.last,
              let otherLabel = otherContainer.subviews.compactMap({ $0 as? NSTextField }).first,
              otherLabel.stringValue == "First" else {
            throw TestFailure("Transferred queue must begin with the first pending reminder")
        }
        other.retainReminders(ids: [second.id])
        guard let transferredContainer = otherView.subviews.last,
              let transferredLabel = transferredContainer.subviews.compactMap({ $0 as? NSTextField }).first,
              transferredLabel.stringValue == "Second" else {
            throw TestFailure("Transferred queue must advance to the second reminder")
        }
        other.retainReminders(ids: [])
        if !otherView.subviews.isEmpty { throw TestFailure("Clearing the transferred queue must remove its overlay") }

        print("OverlayWindowControllerTests: PASS")
    }
}

private struct TestFailure: Error, CustomStringConvertible {
    let description: String

    init(_ description: String) {
        self.description = description
    }
}
