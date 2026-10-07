import SwiftUI

struct RemindersExpandedView: View {
    let module: RemindersModule
    @State private var newTitle = ""
    @State private var hasDueDate = false
    @State private var dueDate = Calendar.current.date(byAdding: .hour, value: 1, to: .now) ?? .now
    private var service: EventKitService { .shared }

    var body: some View {
        if !service.hasReminderAccess {
            EventKitPermissionView(reminders: true) { module.reload() }
        } else {
            VStack(alignment: .leading, spacing: 8) {
                addRow
                if let error = module.lastError {
                    Text(error).font(.caption).foregroundStyle(.orange)
                }
                if module.items.isEmpty {
                    Text("All done 🎉").foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 4) {
                            ForEach(module.items) { item in
                                ReminderRow(module: module, item: item)
                            }
                        }
                    }
                }
            }
        }
    }

    private var addRow: some View {
        HStack(spacing: 6) {
            TextField("New reminder", text: $newTitle)
                .textFieldStyle(.roundedBorder)
                .onSubmit(add)
            Toggle(isOn: $hasDueDate) {
                Image(systemName: "calendar.badge.clock")
            }
            .toggleStyle(.button)
            .tooltip(hasDueDate ? "Remove due date" : "Add a due date")
            if hasDueDate {
                DatePicker("Due", selection: $dueDate, displayedComponents: [.date, .hourAndMinute])
                    .labelsHidden()
                    .datePickerStyle(.compact)
            }
            Button(action: add) { Image(systemName: "plus") }
                .buttonStyle(PillButtonStyle(prominent: true))
                .disabled(newTitle.trimmingCharacters(in: .whitespaces).isEmpty)
                .tooltip("Add reminder")
        }
    }

    private func add() {
        module.add(title: newTitle, dueDate: hasDueDate ? dueDate : nil)
        newTitle = ""
        hasDueDate = false
    }
}

private struct ReminderRow: View {
    let module: RemindersModule
    let item: ReminderItem

    var body: some View {
        HStack(spacing: 8) {
            Button {
                withAnimation(.easeOut(duration: 0.15)) { module.toggle(item) }
            } label: {
                Image(systemName: item.isCompleted ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 15))
                    .foregroundStyle(item.isCompleted ? AnyShapeStyle(.tint) : AnyShapeStyle(Color(nsColor: item.color)))
            }
            .buttonStyle(.plain)
            .tooltip(item.isCompleted ? "Mark as not done" : "Mark as done")
            .accessibilityLabel(item.isCompleted ? "Mark \(item.title) as not done" : "Mark \(item.title) as done")
            VStack(alignment: .leading, spacing: 1) {
                Text(item.title)
                    .strikethrough(item.isCompleted)
                    .foregroundStyle(item.isCompleted ? .secondary : .primary)
                    .lineLimit(2)
                HStack(spacing: 6) {
                    if let due = item.dueDate {
                        Text(due, format: .dateTime.weekday(.abbreviated).hour().minute())
                            .foregroundStyle(item.isOverdue ? Color.red : Color.secondary)
                    }
                    Text(item.listTitle).foregroundStyle(.secondary)
                }
                .font(.caption2)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 8)
        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.white.opacity(0.04)))
    }
}

struct RemindersCompactView: View {
    let module: RemindersModule
    private var service: EventKitService { .shared }

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            ModuleTileHeader(icon: "checklist", title: "Reminders")
            if !service.hasReminderAccess {
                Text("Allow access in the Reminders tab").font(.caption).foregroundStyle(.secondary)
            } else {
                let open = module.items.filter { !$0.isCompleted }
                if open.isEmpty {
                    Text("All done").font(.caption).foregroundStyle(.secondary)
                }
                ForEach(open.prefix(4)) { item in
                    Button {
                        module.toggle(item)
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: "circle").foregroundStyle(Color(nsColor: item.color))
                            Text(item.title).lineLimit(1)
                                .foregroundStyle(item.isOverdue ? Color.red : Color.primary)
                        }
                        .font(.system(size: 11))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}

struct RemindersSettingsView: View {
    let module: RemindersModule
    @AppStorage(Prefs.remindersHiddenLists) private var hidden
    @AppStorage(Prefs.remindersHideCompleted) private var hideCompleted
    @AppStorage(Prefs.remindersAddList) private var addList
    private var service: EventKitService { .shared }

    var body: some View {
        if service.hasReminderAccess {
            ForEach(module.allLists, id: \.calendarIdentifier) { list in
                Toggle(isOn: Binding(
                    get: { !hidden.idList.contains(list.calendarIdentifier) },
                    set: { show in
                        var ids = hidden.idList.filter { $0 != list.calendarIdentifier }
                        if !show { ids.append(list.calendarIdentifier) }
                        hidden = ids.joinedIDs
                        module.reload()
                    }
                )) {
                    HStack(spacing: 6) {
                        Circle().fill(Color(nsColor: list.color ?? .systemOrange)).frame(width: 9, height: 9)
                        Text(list.title)
                    }
                }
            }
            Picker("Add new reminders to", selection: $addList) {
                Text("Default list").tag("")
                ForEach(module.allLists, id: \.calendarIdentifier) { Text($0.title).tag($0.calendarIdentifier) }
            }
        } else {
            LabeledContent("Reminders access") {
                Button(service.remindersDenied ? "Open Privacy Settings" : "Allow Access") {
                    if service.remindersDenied {
                        service.openPrivacySettings(reminders: true)
                    } else {
                        Task { if await service.requestReminderAccess() { module.reload() } }
                    }
                }
            }
        }
        Toggle("Hide completed reminders", isOn: $hideCompleted)
            .onChange(of: hideCompleted) { module.reload() }
        Button("Open Reminders") { module.openRemindersApp() }
    }
}
