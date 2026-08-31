import DrawerCore
import SwiftUI
import UIKit

struct DrawerTaskDetailSheet: View {
    @ObservedObject var model: DrawerMobileModel
    let item: TodoItem

    private enum NoteFeedback: Equatable {
        case saved
        case failed
    }

    @Environment(\.dismiss) private var dismiss
    @State private var noteDraft: String
    @State private var savedNote: String
    @State private var noteFeedback: NoteFeedback?
    @State private var recurrence: TodoRecurrence?
    @State private var showingEditor = false
    @FocusState private var noteFocused: Bool

    init(model: DrawerMobileModel, item: TodoItem) {
        self.model = model
        self.item = item
        let note = item.note ?? ""
        _noteDraft = State(initialValue: note)
        _savedNote = State(initialValue: note)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    taskHeader
                    focusButton
                    noteEditor
                    repeatControls
                    actionGrid
                    sourceContext
                    deleteButton
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)
                .padding(.bottom, 34)
            }
            .navigationTitle("Task")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { saveNoteAndDismiss() }
                }
            }
        }
        .task { recurrence = model.recurrence(for: item) }
        .interactiveDismissDisabled(noteDraft != savedNote)
        .onChange(of: noteDraft) { _, _ in
            if noteDraft != savedNote { noteFeedback = nil }
        }
        .sheet(isPresented: $showingEditor) {
            DrawerTaskEditSheet(
                model: model,
                item: item,
                initialNote: noteDraft
            ) {
                // Editing the title or duration changes TodoItem's raw-line
                // identity. Close this stale detail surface immediately after
                // the single canonical transaction succeeds.
                dismiss()
            }
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
            .presentationCornerRadius(30)
        }
    }

    private var taskHeader: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: item.isDone ? "checkmark.circle.fill" : item.isInProgress ? "circle.lefthalf.filled" : "circle")
                    .foregroundStyle(item.isDone || item.isInProgress ? AnyShapeStyle(.tint) : AnyShapeStyle(.tertiary))
                Text(item.isDone ? "Completed" : item.isInProgress ? "In progress" : "Open")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
                    .tracking(0.6)
                Spacer()
                if let recurrence {
                    Label(recurrence.rule.title, systemImage: "repeat")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                } else if item.minutes != 25 {
                    Label("\(item.minutes)m", systemImage: "timer")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
            }

            HStack(alignment: .top, spacing: 10) {
                Text(item.title)
                    .font(.system(size: 27, weight: .bold, design: .rounded))
                    .tracking(-0.5)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)

                Button {
                    showingEditor = true
                } label: {
                    Image(systemName: "pencil")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(.secondary)
                        .frame(width: 44, height: 44)
                        .background(.quaternary.opacity(0.55), in: Circle())
                }
                .buttonStyle(TactileButtonStyle(pressedScale: 0.92))
                .accessibilityLabel("Edit task")
            }

            if recurrence != nil, item.minutes != 25 {
                Label("\(item.minutes)m", systemImage: "timer")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var focusButton: some View {
        Button {
            model.startFocus(on: item)
            DrawerHaptics.shared.focusStarted()
            dismiss()
        } label: {
            Label("Focus for \(item.minutes) min", systemImage: "timer")
                .font(.headline)
                .frame(maxWidth: .infinity)
                .frame(minHeight: 52)
                .foregroundStyle(.white)
                .background(.tint, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(TactileButtonStyle(pressedScale: 0.985))
        .disabled(item.isDone)
        .opacity(item.isDone ? 0.45 : 1)
    }

    private var noteEditor: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 8) {
                Text("NOTE")
                    .font(.caption.weight(.bold))
                    .tracking(0.7)
                    .foregroundStyle(.secondary)
                Spacer()

                if noteDraft != savedNote {
                    if noteFeedback == .failed {
                        Label("Couldn't save", systemImage: "exclamationmark.circle.fill")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.red)
                    }
                    Button(noteFeedback == .failed ? "Retry" : "Save") { saveNote() }
                        .font(.subheadline.weight(.semibold))
                        .frame(minHeight: 44)
                } else if noteFeedback == .saved {
                    Label("Saved", systemImage: "checkmark.circle.fill")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
            }

            TextEditor(text: $noteDraft)
                .focused($noteFocused)
                .font(.body)
                .scrollContentBackground(.hidden)
                .frame(minHeight: 92)
                .padding(10)
                .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay {
                    if noteDraft.isEmpty && !noteFocused {
                        Text("Add the context you need when you get here.")
                            .font(.subheadline)
                            .foregroundStyle(.tertiary)
                            .padding(16)
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                            .allowsHitTesting(false)
                    }
                }
                .accessibilityLabel("Task note")
        }
    }

    private var repeatControls: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("REPEAT")
                .font(.caption.weight(.bold))
                .tracking(0.7)
                .foregroundStyle(.secondary)

            Menu {
                repeatButton("Never", rule: nil)
                Divider()
                repeatButton("Every Day", rule: .daily)
                repeatButton("Weekdays", rule: .weekdays(Set(1...5)))
                repeatButton("Weekends", rule: .weekdays(Set([6, 7])))
                repeatButton("Every 7 Days", rule: .everyDays(7))
                repeatButton("Monthly", rule: .monthly(currentScheduledDay))
                repeatButton("7 Days After Completion", rule: .afterCompletionDays(7))
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "repeat").frame(width: 22)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Repeat")
                            .font(.subheadline.weight(.semibold))
                        Text(recurrence?.rule.title ?? "Never")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.tertiary)
                }
                .foregroundStyle(.primary)
                .padding(.horizontal, 14)
                .frame(minHeight: 54)
                .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
            .buttonStyle(TactileButtonStyle(pressedScale: 0.99))
            .disabled(item.isDone)

            if recurrence != nil, !item.isDone {
                Button {
                    if model.skipRecurring(item) {
                        DrawerHaptics.shared.skipped()
                        DrawerActionFeedbackCenter.success("Skipped this occurrence", systemImage: "forward.end.circle.fill")
                        dismiss()
                    }
                } label: {
                    actionLabel("Skip This Occurrence", systemImage: "forward.end")
                }
                .buttonStyle(TactileButtonStyle(pressedScale: 0.99))
            }
        }
    }

    private var actionGrid: some View {
        VStack(spacing: 10) {
            Button {
                if model.setInProgress(item, !item.isInProgress) {
                    DrawerHaptics.shared.progressChanged()
                    DrawerActionFeedbackCenter.success(
                        item.isInProgress ? "Cleared in progress" : "Marked in progress",
                        systemImage: item.isInProgress ? "circle" : "circle.lefthalf.filled"
                    )
                    dismiss()
                }
            } label: {
                actionLabel(item.isInProgress ? "Clear In Progress" : "Mark In Progress", systemImage: "circle.lefthalf.filled")
            }
            .buttonStyle(TactileButtonStyle(pressedScale: 0.99))
            .disabled(item.isDone)

            Menu {
                moveButton(.today)
                moveButton(.tomorrow)
                moveButton(.backlog)
            } label: {
                actionLabel("Move", systemImage: "arrow.turn.down.right")
            }
            .buttonStyle(TactileButtonStyle(pressedScale: 0.99))
            .disabled(item.isDone)
        }
    }

    @ViewBuilder
    private var sourceContext: some View {
        if let link = ObsidianLink.first(in: item), let url = link.url(near: model.connectedFileURL) {
            Button { UIApplication.shared.open(url) } label: {
                HStack(spacing: 12) {
                    Image(systemName: "link").frame(width: 22)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Open in Obsidian").font(.subheadline.weight(.semibold))
                        Text(link.note).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    }
                    Spacer()
                    Image(systemName: "arrow.up.right")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.tertiary)
                }
                .padding(14)
                .frame(minHeight: 50)
                .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
            .buttonStyle(TactileButtonStyle(pressedScale: 0.99))
        }

        HStack(spacing: 8) {
            Image(systemName: "doc.text")
            Text("Edits write straight to \(model.sourceName).")
        }
        .font(.caption)
        .foregroundStyle(.tertiary)
    }

    private var deleteButton: some View {
        Button(role: .destructive) {
            if model.delete(item) {
                DrawerHaptics.shared.deleted()
                dismiss()
            }
        } label: {
            Label("Delete Task", systemImage: "trash")
                .font(.subheadline.weight(.semibold))
                .frame(maxWidth: .infinity)
                .frame(minHeight: 50)
                .background(Color.red.opacity(0.10), in: RoundedRectangle(cornerRadius: 15, style: .continuous))
        }
        .buttonStyle(TactileButtonStyle(pressedScale: 0.99))
    }

    private func actionLabel(_ title: String, systemImage: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: systemImage).frame(width: 22)
            Text(title).font(.subheadline.weight(.semibold))
            Spacer()
            Image(systemName: "chevron.right")
                .font(.caption2.weight(.bold))
                .foregroundStyle(.tertiary)
        }
        .foregroundStyle(.primary)
        .padding(.horizontal, 14)
        .frame(minHeight: 50)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func moveButton(_ destination: DrawerTaskDestination) -> some View {
        Button(destination.title) {
            if model.move(item, to: destination) {
                DrawerHaptics.shared.moved()
                dismiss()
            }
        }
        .disabled(isAlready(in: destination))
    }

    private func repeatButton(_ title: String, rule: TodoRecurrenceRule?) -> some View {
        Button(title) {
            if model.setRecurrence(item, rule: rule) {
                recurrence = model.recurrence(for: item)
                DrawerHaptics.shared.recurrenceChanged()
                DrawerActionFeedbackCenter.announce("Repeat set to \(recurrence?.rule.title ?? "Never")")
            }
        }
    }

    @discardableResult
    private func saveNote() -> Bool {
        guard noteDraft != savedNote else { return true }
        if model.setNote(item, noteDraft) {
            savedNote = noteDraft
            noteFeedback = .saved
            DrawerHaptics.shared.saved()
            DrawerActionFeedbackCenter.announce("Note saved")
            noteFocused = false
            return true
        }
        noteFeedback = .failed
        DrawerActionFeedbackCenter.announce("Couldn't save note")
        return false
    }

    private func saveNoteAndDismiss() {
        if saveNote() { dismiss() }
    }

    private var currentScheduledDay: Int {
        let parts = item.sectionDate.split(separator: "-")
        return parts.count == 3 ? min(31, max(1, Int(parts[2]) ?? 1)) : Calendar.current.component(.day, from: Date())
    }

    private func isAlready(in destination: DrawerTaskDestination) -> Bool {
        switch destination {
        case .today: item.sectionDate == DrawerDate.todayKey()
        case .tomorrow: item.sectionDate == DrawerDate.tomorrowKey()
        case .backlog: item.sectionDate == TodoParser.backlogKey
        }
    }
}

private struct DrawerTaskEditSheet: View {
    @ObservedObject var model: DrawerMobileModel
    let item: TodoItem
    let onSaved: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var title: String
    @State private var minutes: Int
    @State private var note: String
    @FocusState private var titleFocused: Bool

    private let durationChoices = [15, 25, 30, 45, 60, 90, 120]

    init(
        model: DrawerMobileModel,
        item: TodoItem,
        initialNote: String,
        onSaved: @escaping () -> Void
    ) {
        self.model = model
        self.item = item
        self.onSaved = onSaved
        _title = State(initialValue: item.title)
        _minutes = State(initialValue: item.minutes)
        _note = State(initialValue: initialNote)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    editSection("TITLE") {
                        TextField("Task title", text: $title, axis: .vertical)
                            .focused($titleFocused)
                            .font(.title3.weight(.semibold))
                            .textInputAutocapitalization(.sentences)
                            .submitLabel(.done)
                            .padding(14)
                            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                            .accessibilityLabel("Task title")
                    }

                    editSection("FOCUS LENGTH") {
                        Menu {
                            ForEach(durationChoices, id: \.self) { choice in
                                Button {
                                    minutes = choice
                                    DrawerHaptics.shared.progressChanged()
                                } label: {
                                    if minutes == choice {
                                        Label("\(choice) minutes", systemImage: "checkmark")
                                    } else {
                                        Text("\(choice) minutes")
                                    }
                                }
                            }
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: "timer")
                                    .frame(width: 22)
                                Text("\(minutes) min")
                                    .font(.headline)
                                    .monospacedDigit()
                                Spacer()
                                Image(systemName: "chevron.up.chevron.down")
                                    .font(.caption2.weight(.bold))
                                    .foregroundStyle(.tertiary)
                            }
                            .foregroundStyle(.primary)
                            .padding(.horizontal, 14)
                            .frame(minHeight: 54)
                            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                        }
                        .buttonStyle(TactileButtonStyle(pressedScale: 0.99))
                        .accessibilityLabel("Focus length, \(minutes) minutes")

                        if !durationChoices.contains(minutes) {
                            Text("Keeping the custom \(minutes)-minute length from Drawer.md. Choose a preset to change it.")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }

                    editSection("NOTE") {
                        TextEditor(text: $note)
                            .font(.body)
                            .scrollContentBackground(.hidden)
                            .frame(minHeight: 150)
                            .padding(10)
                            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                            .accessibilityLabel("Task note")
                    }

                    HStack(spacing: 8) {
                        Image(systemName: "doc.text")
                        Text("Save writes this edit directly to \(model.sourceName) in one transaction.")
                    }
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                }
                .padding(.horizontal, 20)
                .padding(.top, 12)
                .padding(.bottom, 36)
            }
            .navigationTitle("Edit Task")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .fontWeight(.semibold)
                        .disabled(!canSave)
                }
            }
        }
        .interactiveDismissDisabled(hasChanges)
    }

    private var cleanTitle: String {
        title.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var cleanNote: String {
        note.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var hasChanges: Bool {
        cleanTitle != item.title ||
            minutes != item.minutes ||
            cleanNote != (item.note ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var canSave: Bool {
        !cleanTitle.isEmpty && (1...480).contains(minutes) && hasChanges
    }

    @ViewBuilder
    private func editSection<Content: View>(
        _ title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            Text(title)
                .font(.caption.weight(.bold))
                .tracking(0.7)
                .foregroundStyle(.secondary)
            content()
        }
    }

    private func save() {
        guard canSave else { return }
        if model.updateTask(item, title: cleanTitle, minutes: minutes, note: note) {
            DrawerHaptics.shared.saved()
            DrawerActionFeedbackCenter.success("Task updated", systemImage: "checkmark.circle.fill")
            dismiss()
            DispatchQueue.main.async(execute: onSaved)
        }
    }
}
