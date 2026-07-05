import Foundation

/// Renders the full work session history as a readable markdown log, most
/// recent day first. Regenerated whole from the log every time, so edits and
/// deletions are always reflected without a separate reconciliation step.
public func renderWorkLogMarkdown(
    _ summaries: [WorkSummary], daySummaries: [String: String] = [:]
) -> String {
    guard !summaries.isEmpty else { return "# Work Log\n\nNo work logged yet.\n" }
    var lines = ["# Work Log", ""]
    for summary in summaries {
        lines.append("## \(summary.day) — \(WorkClock.formatHM(summary.total))")
        // The AI narrative (spec 02) merges directly under the day heading.
        if let narrative = daySummaries[summary.day], !narrative.isEmpty {
            lines.append(narrative)
        }
        for row in summary.rows {
            lines.append("- \(row.taskTitle) — \(WorkClock.formatHM(row.seconds))")
        }
        lines.append("")
    }
    return lines.joined(separator: "\n")
}
