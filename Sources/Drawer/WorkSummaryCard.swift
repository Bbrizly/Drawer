import DrawerCore
import SwiftUI

/// The end-of-day card shown inline at the top of the list when Work Mode ends.
/// Inline rather than a sheet, because the drawer is a non-activating panel and
/// a sheet would fight it for key status. Tap Edit to correct the logged minutes
/// per task (set a task to 0 to remove it).
struct WorkSummaryCard: View {
    let summary: WorkSummary
    var requestKeyboard: () -> Void = {}
    var onEdit: (_ title: String, _ seconds: TimeInterval, _ day: String) -> Void
    var onDone: () -> Void

    @Environment(\.drawerTheme) private var theme
    @State private var isEditing = false
    @State private var drafts: [String: String] = [:]   // title -> minutes text

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 1) {
                    Text("WORK SUMMARY")
                        .font(.system(size: 9, weight: .bold))
                        .tracking(0.8)
                        .foregroundStyle(.tertiary)
                    Text(summary.day)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text(WorkClock.formatHM(summary.total))
                    .font(.system(size: 22, weight: .semibold, design: .rounded)
                        .monospacedDigit())
            }

            if summary.rows.isEmpty {
                Text("No time tracked today.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else {
                VStack(spacing: 6) {
                    ForEach(summary.rows, id: \.taskTitle) { row in
                        HStack(spacing: 10) {
                            Text(row.taskTitle)
                                .lineLimit(1)
                                .truncationMode(.tail)
                            Spacer(minLength: 8)
                            if isEditing {
                                TextField("0", text: minutesBinding(row))
                                    .textFieldStyle(.roundedBorder)
                                    .frame(width: 46)
                                    .multilineTextAlignment(.trailing)
                                    .onSubmit(save)
                                Text("min")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            } else {
                                Text(WorkClock.formatHM(row.seconds))
                                    .font(.system(.callout, design: .rounded).monospacedDigit())
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                if isEditing {
                    Text("Set a task to 0 to remove it.")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }

            HStack(spacing: 8) {
                if !summary.rows.isEmpty {
                    Button(isEditing ? "Save" : "Edit") {
                        if isEditing {
                            save()
                        } else {
                            drafts = [:]
                            requestKeyboard() // panel must be key for the fields to type
                            isEditing = true
                        }
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
                Spacer(minLength: 0)
                Button("Done", action: onDone)
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(theme.accent.opacity(0.10), in: RoundedRectangle(cornerRadius: 11))
    }

    private static func minutesText(_ seconds: TimeInterval) -> String {
        String(Int((seconds / 60).rounded()))
    }

    private func minutesBinding(_ row: WorkSummary.Row) -> Binding<String> {
        Binding(
            get: { drafts[row.taskTitle] ?? Self.minutesText(row.seconds) },
            set: { drafts[row.taskTitle] = String($0.filter(\.isNumber).prefix(4)) }
        )
    }

    /// Commit every changed row, then leave edit mode. The parent refreshes the
    /// summary from the log, which re-renders this card.
    private func save() {
        for row in summary.rows {
            let original = Int((row.seconds / 60).rounded())
            let edited = Int(drafts[row.taskTitle] ?? "") ?? original
            if edited != original {
                onEdit(row.taskTitle, TimeInterval(edited * 60), summary.day)
            }
        }
        drafts = [:]
        isEditing = false
    }
}
