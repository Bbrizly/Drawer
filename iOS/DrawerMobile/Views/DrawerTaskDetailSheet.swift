import DrawerCore
import SwiftUI
import UIKit

struct DrawerTaskDetailSheet: View {
    @ObservedObject var model: DrawerMobileModel
    let item: TodoItem

    @Environment(\.dismiss) private var dismiss
    @State private var noteDraft: String
    @FocusState private var noteFocused: Bool

    init(model: DrawerMobileModel, item: TodoItem) {
        self.model = model
        self.item = item
        _noteDraft = State(initialValue: item.note ?? "")
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    taskHeader
                    focusButton
                    noteEditor
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
                    Button("Done") { dismiss() }
                }
            }
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
                if item.minutes != 25 {
                    Label("\(item.minutes)m", systemImage: "timer")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
            }

            Text(item.title)
                .font(.system(size: 27, weight: .bold, design: .rounded))
                .tracking(-0.5)
                .fixedSize(horizontal: false, vertical: true)
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
                .frame(height: 52)
                .foregroundStyle(.white)
                .background(.tint, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(TactileButtonStyle(pressedScale: 0.985))
        .disabled(item.isDone)
        .opacity(item.isDone ? 0.45 : 1)
    }

    private var noteEditor: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack {
                Text("NOTE")
                    .font(.caption.weight(.bold))
                    .tracking(0.7)
                    .foregroundStyle(.secondary)
                Spacer()
                if noteDraft != (item.note ?? "") {
                    Button("Save") {
                        if model.setNote(item, noteDraft) {
                            DrawerHaptics.shared.taskAdded()
                            noteFocused = false
                        }
                    }
                    .font(.subheadline.weight(.semibold))
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
        }
    }

    private var actionGrid: some View {
        VStack(spacing: 10) {
            Button {
                if model.setInProgress(item, !item.isInProgress) {
                    DrawerHaptics.shared.progressChanged()
                    dismiss()
                }
            } label: {
                actionLabel(
                    item.isInProgress ? "Clear In Progress" : "Mark In Progress",
                    systemImage: "circle.lefthalf.filled"
                )
            }
            .buttonStyle(TactileButtonStyle(pressedScale: 0.99))

            Menu {
                moveButton(.today)
                moveButton(.tomorrow)
                moveButton(.backlog)
            } label: {
                actionLabel("Move", systemImage: "arrow.turn.down.right")
            }
            .buttonStyle(TactileButtonStyle(pressedScale: 0.99))
        }
    }

    @ViewBuilder
    private var sourceContext: some View {
        if let link = ObsidianLink.first(in: item),
           let url = link.url(near: model.connectedFileURL) {
            Button {
                UIApplication.shared.open(url)
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "link")
                        .frame(width: 22)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Open in Obsidian")
                            .font(.subheadline.weight(.semibold))
                        Text(link.note)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    Spacer()
                    Image(systemName: "arrow.up.right")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.tertiary)
                }
                .padding(14)
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
                .frame(height: 48)
                .background(Color.red.opacity(0.10), in: RoundedRectangle(cornerRadius: 15, style: .continuous))
        }
        .buttonStyle(TactileButtonStyle(pressedScale: 0.99))
    }

    private func actionLabel(_ title: String, systemImage: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: systemImage)
                .frame(width: 22)
            Text(title)
                .font(.subheadline.weight(.semibold))
            Spacer()
            Image(systemName: "chevron.right")
                .font(.caption2.weight(.bold))
                .foregroundStyle(.tertiary)
        }
        .foregroundStyle(.primary)
        .padding(.horizontal, 14)
        .frame(height: 50)
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

    private func isAlready(in destination: DrawerTaskDestination) -> Bool {
        switch destination {
        case .today:
            item.sectionDate == DrawerDate.todayKey()
        case .tomorrow:
            item.sectionDate == DrawerDate.tomorrowKey()
        case .backlog:
            item.sectionDate == TodoParser.backlogKey
        }
    }
}
