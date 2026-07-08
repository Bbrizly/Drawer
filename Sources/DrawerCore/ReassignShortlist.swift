import Foundation

/// Ranks the open-task list for the "Reassign" control so the review UI shows a
/// short, evidence-led shortlist instead of a flat menu of every open task. Pure
/// and testable; the app builds the menu from the result.
public enum ReassignShortlist {
    /// A priority (in-progress or carried) task is worth this much overlap, so it
    /// surfaces into the shortlist even with no text match. Below 1 so a real
    /// title match still outranks a stale priority task.
    static let priorityBoost = 0.75

    /// Splits candidates into a short, evidence-ranked top list and the rest.
    /// Ranking: text similarity between the candidate title and the block's
    /// window titles/app name, with a boost for priority (in-progress or
    /// carried) tasks. Ties keep input order (already today-first).
    /// `top` is the first `limit` by rank; `rest` is the remainder in ORIGINAL
    /// input order (it is browsed, not ranked). If the whole list barely exceeds
    /// the limit, everything goes in `top` (a two-item submenu is worse than two
    /// more rows).
    public static func split(
        evidence: AttributionEvidence, candidates: [TaskCandidate], limit: Int = 5
    ) -> (top: [TaskCandidate], rest: [TaskCandidate]) {
        guard candidates.count > limit + 2 else { return (candidates, []) }

        // Stable rank: score descending, ties broken by original offset ascending.
        let ranked = candidates.enumerated()
            .sorted { a, b in
                let sa = score(evidence, a.element)
                let sb = score(evidence, b.element)
                return sa != sb ? sa > sb : a.offset < b.offset
            }
            .map(\.element)

        let top = Array(ranked.prefix(limit))
        let topIDs = Set(top.map(\.id))
        // Rest stays in the caller's input order, not rank order.
        let rest = candidates.filter { !topIDs.contains($0.id) }
        return (top, rest)
    }

    /// Best token overlap of the candidate title against any window title or the
    /// app name, plus the priority boost. Mirrors the classifier's scorer.
    private static func score(_ evidence: AttributionEvidence, _ candidate: TaskCandidate) -> Double {
        let evidenceText = evidence.titles + [evidence.appName]
        let overlap = evidenceText.map { TitleSimilarity.score($0, candidate.title) }.max() ?? 0
        return overlap + (candidate.priority ? priorityBoost : 0)
    }
}
