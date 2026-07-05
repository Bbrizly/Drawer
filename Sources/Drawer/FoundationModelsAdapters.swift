import DrawerCore
import Foundation

#if canImport(FoundationModels)
import FoundationModels
#endif

/// Whether Apple Foundation Models is usable right now. Read at each call site
/// (never cached): the model downloads after setup, is reclaimed under storage
/// pressure, and disappears when Apple Intelligence is turned off.
func foundationModelsAvailable() -> Bool {
#if canImport(FoundationModels)
    if #available(macOS 26.0, *) {
        if case .available = SystemLanguageModel.default.availability { return true }
    }
#endif
    return false
}

/// The on-device task matcher, or nil when Foundation Models is unavailable so
/// the classifier stays in rules-only mode. Rebuilt per use so availability is
/// always fresh.
func makeTaskMatcherIfAvailable() -> TaskMatcher? {
#if canImport(FoundationModels)
    if #available(macOS 26.0, *), foundationModelsAvailable() {
        return FoundationModelsTaskMatcher()
    }
#endif
    return nil
}

func makeDaySummarizerIfAvailable() -> DaySummarizer? {
#if canImport(FoundationModels)
    if #available(macOS 26.0, *), foundationModelsAvailable() {
        return FoundationModelsDaySummarizer()
    }
#endif
    return nil
}

#if canImport(FoundationModels)
@available(macOS 26.0, *)
struct FoundationModelsTaskMatcher: TaskMatcher {
    @Generable
    struct Pick {
        @Guide(description: "Index of the best-matching task in the list, or null if none fit")
        var bestTaskIndex: Int?
        @Guide(description: "Confidence from 0 to 1 that the task is correct")
        var confidence: Double
    }

    func match(block: ActivityBlock, candidates: [TaskCandidate]) async throws -> ProposedMatch {
        guard !candidates.isEmpty else {
            return ProposedMatch(taskID: nil, taskTitle: nil, confidence: 0, via: .none)
        }
        let list = candidates.enumerated()
            .map { "\($0.offset): \($0.element.title)" }
            .joined(separator: "\n")
        let evidence = "App: \(block.appName). Windows: \(block.titles.joined(separator: ", "))."
        let session = LanguageModelSession(instructions: """
            You match a stretch of computer activity to the task the user was most \
            likely working on. Only pick a task if the evidence clearly supports it; \
            otherwise return null. Never invent a task.
            """)
        let pick = try await session.respond(
            to: "\(evidence)\n\nCandidate tasks:\n\(list)\n\nWhich task, if any?",
            generating: Pick.self).content

        let confidence = min(max(pick.confidence, 0), 1)
        guard let index = pick.bestTaskIndex, candidates.indices.contains(index) else {
            return ProposedMatch(taskID: nil, taskTitle: nil, confidence: confidence, via: .none)
        }
        let task = candidates[index]
        return ProposedMatch(taskID: task.id, taskTitle: task.title, confidence: confidence, via: .model)
    }
}

@available(macOS 26.0, *)
struct FoundationModelsDaySummarizer: DaySummarizer {
    @Generable
    struct Summary {
        @Guide(description: "An honest 3-sentence summary of the day's work")
        var summary: String
    }

    func summarize(day: String, sessions: [WorkSession], deltas: [EstimateDelta]) async throws -> String {
        let total = sessions.reduce(0.0) { $0 + $1.seconds }
        let byTask = Dictionary(grouping: sessions, by: \.taskTitle)
            .map { "\($0.key): \(Int($0.value.reduce(0) { $0 + $1.seconds } / 60))m" }
            .joined(separator: ", ")
        let misses = deltas
            .filter { abs($0.actualMinutes - $0.estimatedMinutes) >= 15 }
            .map { "\($0.taskTitle) est \($0.estimatedMinutes)m actual \($0.actualMinutes)m" }
            .joined(separator: "; ")
        let session = LanguageModelSession(instructions: """
            You write a short, honest end-of-day work summary. At most 3 sentences. \
            State the total focused time, the biggest item, and any estimate misses. \
            No praise, no filler.
            """)
        let prompt = """
            Day \(day). Total \(Int(total / 60)) minutes. Per task: \(byTask). \
            Estimate misses: \(misses.isEmpty ? "none" : misses).
            """
        return try await session.respond(to: prompt, generating: Summary.self).content.summary
    }
}
#endif
