import AppKit
import SwiftUI

/// The reminder list in System Settings: add as many as you like, each with its own
/// wording, icon, colour and interval.
struct RemindersSection: View {
    @ObservedObject var settings: Settings
    @State private var editing: Reminder?

    var body: some View {
        Section {
            ForEach(settings.reminders) { reminder in
                RemindersRow(reminder: reminder,
                             isOn: binding(for: reminder),
                             edit: { editing = reminder })
            }
            .onDelete { offsets in
                var list = settings.reminders
                list.remove(atOffsets: offsets)
                settings.reminders = list
            }

            Button {
                editing = Reminder(text: "", symbol: "bell.fill", minutes: 30, isOn: true)
            } label: {
                Label("Add Reminder", systemImage: "plus.circle.fill")
            }

            Toggle("Quiet hours", isOn: $settings.quietHoursOn)
            if settings.quietHoursOn {
                HStack {
                    Text("From")
                    TimeOfDayPicker(minutes: $settings.quietFrom)
                    Text("to")
                    TimeOfDayPicker(minutes: $settings.quietTo)
                    Spacer()
                }
            }
        } header: {
            Text("Reminders")
        } footer: {
            Text(settings.quietHoursOn
                 ? "Recurring nudges in the island, counted in screen time — reading and watching count too, and a real break away from the Mac starts the count again. Between \(QuietHours.describe(settings.quietFrom)) and \(QuietHours.describe(settings.quietTo)) the counts stand still, so nothing is saved up to land the moment the quiet ends."
                 : "Recurring nudges in the island, counted in screen time — reading and watching count too, and a real break away from the Mac starts the count again. The first two are the 20-20-20 rule and a glass of water; change them, or add your own.")
        }
        .sheet(item: $editing) { reminder in
            ReminderEditor(reminder: reminder,
                           isNew: !settings.reminders.contains { $0.id == reminder.id },
                           save: { save($0) },
                           delete: { delete(reminder) })
        }
    }

    private func binding(for reminder: Reminder) -> Binding<Bool> {
        Binding(
            get: { settings.reminders.first { $0.id == reminder.id }?.isOn ?? false },
            set: { isOn in
                var list = settings.reminders
                guard let index = list.firstIndex(where: { $0.id == reminder.id }) else { return }
                list[index].isOn = isOn
                settings.reminders = list
            }
        )
    }

    private func save(_ reminder: Reminder) {
        var list = settings.reminders
        if let index = list.firstIndex(where: { $0.id == reminder.id }) {
            list[index] = reminder
        } else {
            list.append(reminder)
        }
        settings.reminders = list
        editing = nil
    }

    private func delete(_ reminder: Reminder) {
        settings.reminders = settings.reminders.filter { $0.id != reminder.id }
        editing = nil
    }
}

private struct RemindersRow: View {
    let reminder: Reminder
    @Binding var isOn: Bool
    let edit: () -> Void

    var body: some View {
        Toggle(isOn: $isOn) {
            HStack(spacing: 10) {
                Image(systemName: reminder.symbol)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 22, height: 22)
                    .background(RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(reminder.tint.color.gradient))
                VStack(alignment: .leading, spacing: 1) {
                    // Wording the user typed, so it can be any length. Held to one
                    // line: System Settings gives a pane a fixed width and clips
                    // whatever will not fit, so a long reminder must truncate here
                    // rather than push the switches off the right-hand edge.
                    Text(reminder.text)
                        .lineLimit(1)
                        .truncationMode(.tail)
                    Text(reminder.seconds > Reminder.defaultSeconds
                         ? "\(Reminder.intervalDescription(reminder.minutes)) · holds \(reminder.seconds)s"
                         : Reminder.intervalDescription(reminder.minutes))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Spacer(minLength: 8)
                Button("Edit", action: edit)
                    .buttonStyle(.link)
            }
        }
    }
}

/// One reminder's wording, icon, colour and interval.
private struct ReminderEditor: View {
    @State var reminder: Reminder
    let isNew: Bool
    let save: (Reminder) -> Void
    let delete: () -> Void
    @Environment(\.dismiss) private var dismiss

    private var symbolIsKnown: Bool {
        Reminder.symbolExists(reminder.symbol.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(isNew ? "New Reminder" : "Edit Reminder")
                .font(.headline)
                .padding(.bottom, 12)

            Form {
                Section {
                    TextField("What it should say", text: $reminder.text, prompt: Text("Stand up and stretch"))
                    HStack {
                        Text("Every")
                        TextField("", value: $reminder.minutes, format: .number)
                            .frame(width: 60)
                            .multilineTextAlignment(.trailing)
                        Stepper("", value: $reminder.minutes,
                                in: Reminder.minimumMinutes...Reminder.maximumMinutes)
                            .labelsHidden()
                        Text("minutes of screen time")
                            .foregroundStyle(.secondary)
                    }
                    HStack {
                        Text("Stay on screen for")
                        TextField("", value: $reminder.seconds, format: .number)
                            .frame(width: 60)
                            .multilineTextAlignment(.trailing)
                        Stepper("", value: $reminder.seconds,
                                in: Reminder.minimumSeconds...Reminder.maximumSeconds)
                            .labelsHidden()
                        Text("seconds")
                            .foregroundStyle(.secondary)
                    }
                } footer: {
                    Text("Turn the hold up for anything you are meant to do while it is showing — twenty seconds of looking into the distance, say, so the island is the timer.")
                }

                Section("Icon") {
                    LazyVGrid(columns: Array(repeating: GridItem(.fixed(30), spacing: 6), count: 8), spacing: 6) {
                        ForEach(Reminder.symbols, id: \.self) { symbol in
                            Button {
                                reminder.symbol = symbol
                            } label: {
                                Image(systemName: symbol)
                                    .font(.system(size: 13))
                                    .frame(width: 28, height: 28)
                                    .background(RoundedRectangle(cornerRadius: 6)
                                        .fill(reminder.symbol == symbol ? reminder.tint.color.opacity(0.25) : Color.secondary.opacity(0.1)))
                                    .overlay(RoundedRectangle(cornerRadius: 6)
                                        .stroke(reminder.symbol == symbol ? reminder.tint.color : .clear, lineWidth: 1.5))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.vertical, 2)

                    TextField("Or any SF Symbol name", text: $reminder.symbol)
                    if !symbolIsKnown {
                        Label("No symbol by that name — it'll fall back to a bell.",
                              systemImage: "exclamationmark.triangle.fill")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                }

                Section("Colour") {
                    HStack(spacing: 8) {
                        ForEach(Reminder.Tint.allCases) { tint in
                            Button {
                                reminder.tint = tint
                            } label: {
                                Circle()
                                    .fill(tint.color.gradient)
                                    .frame(width: 22, height: 22)
                                    .overlay(Circle().stroke(.primary, lineWidth: reminder.tint == tint ? 2 : 0))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            .formStyle(.grouped)

            HStack {
                if !isNew {
                    Button("Delete", role: .destructive) { delete() }
                }
                Spacer()
                Button("Cancel") { dismiss() }
                Button("Save") { save(reminder.sanitised()) }
                    .keyboardShortcut(.defaultAction)
            }
            .padding(.top, 12)
        }
        .padding(20)
        .frame(width: 440)
    }
}

/// An hour-and-minute picker that stores plain minutes past midnight, shown in
/// whatever clock format the Mac is set to.
private struct TimeOfDayPicker: View {
    @Binding var minutes: Int

    var body: some View {
        DatePicker("", selection: Binding(
            get: { Self.date(from: minutes) },
            set: { minutes = Self.minutes(from: $0) }
        ), displayedComponents: .hourAndMinute)
            .labelsHidden()
            .datePickerStyle(.field)
            .frame(width: 90)
    }

    private static func date(from minutes: Int) -> Date {
        var parts = DateComponents()
        parts.hour = minutes / 60
        parts.minute = minutes % 60
        return Calendar.current.date(from: parts) ?? Date()
    }

    private static func minutes(from date: Date) -> Int {
        let parts = Calendar.current.dateComponents([.hour, .minute], from: date)
        return (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
    }
}
