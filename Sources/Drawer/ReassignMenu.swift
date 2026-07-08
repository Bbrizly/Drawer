import DrawerCore
import SwiftUI

/// The "Reassign" control for a review row. Instead of a flat menu of every open
/// task, it shows a short evidence-ranked shortlist as direct buttons and tucks
/// the rest behind an "All tasks" submenu, so a real backlog stays usable.
/// Inherits font and button style from its surrounding row.
struct ReassignMenu: View {
    let evidence: AttributionEvidence
    let candidates: [TaskCandidate]
    /// (taskID, title) of the task the user picked.
    let onPick: (String, String) -> Void

    var body: some View {
        let split = ReassignShortlist.split(evidence: evidence, candidates: candidates)
        Menu("Reassign") {
            ForEach(split.top, id: \.id) { c in
                Button(c.title) { onPick(c.id, c.title) }
            }
            if !split.rest.isEmpty {
                Divider()
                Menu("All tasks") {
                    ForEach(split.rest, id: \.id) { c in
                        Button(c.title) { onPick(c.id, c.title) }
                    }
                }
            }
        }
    }
}
