// ReminderView.swift
// Editing and reviewing locally stored daily reminders.
import SwiftUI

struct ReminderView: View {
    @ObservedObject var scheduler: ReminderScheduler
    @State private var text = ""
    @State private var time = Date()
    @State private var editing: UUID?
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Daily reminders").font(.headline)
            if let error = scheduler.error { Text(error).foregroundColor(.red).textSelection(.enabled) }
            HStack {
                TextField("Reminder", text: $text)
                DatePicker("Time", selection: $time, displayedComponents: .hourAndMinute).labelsHidden()
                Button(editing == nil ? "Add" : "Save") { save() }
                if editing != nil { Button("Cancel") { editing = nil; text = "" } }
            }
            List {
                ForEach(scheduler.data.reminders) { reminder in
                    HStack {
                        Toggle("", isOn: Binding(get: { reminder.enabled }, set: { value in
                            var items = scheduler.data.reminders
                            if let index = items.firstIndex(where: { $0.id == reminder.id }) { items[index].enabled = value; scheduler.replace(items) }
                        })).labelsHidden()
                        Text(String(format: "%02d:%02d", reminder.hour, reminder.minute))
                        Text(reminder.text).lineLimit(2)
                        Spacer()
                        Button("Edit") {
                            editing = reminder.id; text = reminder.text
                            time = Calendar.current.date(bySettingHour: reminder.hour, minute: reminder.minute, second: 0, of: Date()) ?? Date()
                        }
                        Button("Delete") { scheduler.replace(scheduler.data.reminders.filter { $0.id != reminder.id }) }
                    }
                }
            }.frame(minHeight: 180)
            if !scheduler.data.pending.isEmpty {
                Text("Pending").font(.headline)
                ForEach(scheduler.data.pending) { pending in
                    HStack { Text(pending.reminder.text); Spacer(); Button("Dismiss") { scheduler.dismiss(pending.id) } }
                }
            }
        }.padding().frame(width: 550, height: 420)
    }
    private func save() {
        let components = Calendar.current.dateComponents([.hour, .minute], from: time)
        var items = scheduler.data.reminders
        let reminder = Reminder(id: editing ?? UUID(), text: text, hour: components.hour ?? 0, minute: components.minute ?? 0,
                                enabled: items.first(where: { $0.id == editing })?.enabled ?? true)
        do { try reminder.validate() } catch { scheduler.error = error.localizedDescription; return }
        if let index = items.firstIndex(where: { $0.id == reminder.id }) { items[index] = reminder } else { items.append(reminder) }
        scheduler.replace(items)
        if scheduler.error == nil { editing = nil; text = "" }
    }
}
