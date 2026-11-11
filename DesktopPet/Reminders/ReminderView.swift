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
            if let loadError = scheduler.loadError {
                Text("Could not load reminders. The original file has been preserved. Restart after resolving the problem: \(loadError)")
                    .foregroundColor(.red).textSelection(.enabled)
            }
            if let error = scheduler.error { Text(error).foregroundColor(.red).textSelection(.enabled) }
            HStack {
                TextField("Reminder", text: $text)
                DatePicker("Time", selection: $time, displayedComponents: .hourAndMinute).labelsHidden()
                Button(editing == nil ? "Add" : "Save") { save() }
                if editing != nil { Button("Cancel") { editing = nil; text = "" } }
            }.disabled(!scheduler.ready)
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
                        Button("Delete") {
                            scheduler.replace(scheduler.data.reminders.filter { $0.id != reminder.id })
                            if scheduler.error == nil, editing == reminder.id {
                                editing = nil
                                text = ""
                            }
                        }
                    }
                }
            }.frame(minHeight: 120).disabled(!scheduler.ready)
            if !scheduler.data.pending.isEmpty {
                Text("Pending").font(.headline)
                ScrollView {
                    LazyVStack(alignment: .leading) {
                        ForEach(scheduler.data.pending) { pending in
                            HStack(alignment: .top) {
                                Text(pending.reminder.text).fixedSize(horizontal: false, vertical: true)
                                Spacer()
                                Button("Dismiss") { scheduler.dismiss(pending.id) }
                            }
                        }
                    }.frame(maxWidth: .infinity, alignment: .leading)
                }.frame(minHeight: 80, maxHeight: .infinity)
            }
        }.padding().frame(width: 550, height: 420)
    }
    private func save() {
        let components = Calendar.current.dateComponents([.hour, .minute], from: time)
        var items = scheduler.data.reminders
        let reminder = Reminder(id: editing ?? UUID(), text: text, hour: components.hour ?? 0, minute: components.minute ?? 0,
                                enabled: items.first(where: { $0.id == editing })?.enabled ?? true)
        do { try reminder.validate() } catch { scheduler.error = error.localizedDescription; return }
        if let index = items.firstIndex(where: { $0.id == reminder.id }) {
            items[index] = reminder
        } else if editing == nil {
            items.append(reminder)
        } else {
            scheduler.error = "This reminder no longer exists. Cancel editing and try again."
            return
        }
        scheduler.replace(items)
        if scheduler.error == nil { editing = nil; text = "" }
    }
}
