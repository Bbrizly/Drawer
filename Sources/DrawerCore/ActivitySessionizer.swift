import Foundation

/// Tunable thresholds for folding samples into blocks. Defaults are the spec's
/// hardcoded values; they live here so tests can drive short synthetic streams.
public struct SessionizerConfig: Sendable {
    /// A gap over this (no samples) ends the block as idle.
    public var idleThreshold: TimeInterval
    /// Blocks shorter than this are dropped (or bridged away).
    public var minBlock: TimeInterval
    /// A same-app stretch interrupted by a short excursion is bridged back only
    /// if the whole detour fits inside this window.
    public var bridgeGap: TimeInterval

    public init(idleThreshold: TimeInterval = 180, minBlock: TimeInterval = 60, bridgeGap: TimeInterval = 900) {
        self.idleThreshold = idleThreshold
        self.minBlock = minBlock
        self.bridgeGap = bridgeGap
    }

    public static let `default` = SessionizerConfig()
}

/// Folds a change-driven sample stream into `ActivityBlock`s. Samples mark state
/// changes (app switch or title change), not heartbeats: a block runs from its
/// opening sample until the next different-state sample, an explicit boundary
/// (idle, sleep, lock), or the stream end. Idle is never inferred from a sample
/// gap — the live sampler's timer emits it as a boundary — because staying on
/// one document for an hour is one active block, not idle. Pure: all timing is
/// sample timestamps and boundaries, so it is fully testable with no AppKit.
///
/// ponytail: the bridge/merge heuristics (short-block drop, flicker bridge) are
/// deliberately simple. The spec keeps attribution off until a week of
/// dogfooding, which is when these thresholds get tuned against real streams.
public enum ActivitySessionizer {
    private struct Builder {
        var bundleID: String
        var appName: String
        var start: Date
        var titles: [String]
        var cluster: Set<String>

        func finished(end: Date, reason: ActivityBlockCloseReason) -> ActivityBlock {
            ActivityBlock(
                start: start, end: end, bundleID: bundleID, appName: appName,
                titles: titles, closeReason: reason)
        }
    }

    public static func sessionize(
        samples: [ActivitySample],
        boundaries: [SessionBoundary] = [],
        streamEnd: Date? = nil,
        config: SessionizerConfig = .default
    ) -> [ActivityBlock] {
        let samples = samples.sorted { $0.ts < $1.ts }
        let bounds = boundaries.sorted { $0.ts < $1.ts }

        var raw: [ActivityBlock] = []
        var current: Builder?
        var boundaryIndex = 0

        func close(at end: Date, reason: ActivityBlockCloseReason) {
            if let c = current { raw.append(c.finished(end: end, reason: reason)); current = nil }
        }
        // A sleep/lock/idle boundary strictly before `ts` closes the open block.
        func applyBoundaries(before ts: Date) {
            while boundaryIndex < bounds.count, bounds[boundaryIndex].ts < ts {
                close(at: bounds[boundaryIndex].ts, reason: bounds[boundaryIndex].reason)
                boundaryIndex += 1
            }
        }

        for sample in samples {
            applyBoundaries(before: sample.ts)

            if var c = current {
                if sample.bundleID == c.bundleID, c.cluster.contains(sample.normalizedTitle) {
                    if let title = sample.windowTitle, !c.titles.contains(title) { c.titles.append(title) }
                    c.cluster.insert(sample.normalizedTitle)
                    current = c
                    continue  // same state: block keeps running, end still open
                }
                close(at: sample.ts, reason: .appSwitch)  // state change ends the block here
            }
            current = Builder(
                bundleID: sample.bundleID, appName: sample.appName, start: sample.ts,
                titles: sample.windowTitle.map { [$0] } ?? [], cluster: [sample.normalizedTitle])
        }

        while boundaryIndex < bounds.count {
            close(at: bounds[boundaryIndex].ts, reason: bounds[boundaryIndex].reason)
            boundaryIndex += 1
        }
        close(at: streamEnd ?? samples.last?.ts ?? current.map(\.start) ?? .distantPast,
              reason: .endOfStream)

        return dropShort(bridge(raw, config: config), config: config)
    }

    /// Merges a same-app stretch split by a short excursion (a 3-second Slack
    /// blip) back into one block, so a brief context switch doesn't fragment
    /// focused work. Only bridges across an appSwitch (never idle/sleep/lock).
    private static func bridge(_ input: [ActivityBlock], config: SessionizerConfig) -> [ActivityBlock] {
        guard input.count >= 3 else { return input }
        var blocks = input
        var changed = true
        while changed {
            changed = false
            var i = 1
            while i + 1 < blocks.count {
                let prev = blocks[i - 1], mid = blocks[i], next = blocks[i + 1]
                let midShort = mid.range.duration < config.minBlock
                let sameStream = prev.bundleID == next.bundleID
                    && !Set(prev.normalizedTitles).isDisjoint(with: next.normalizedTitles)
                let softBreaks = prev.closeReason == .appSwitch && mid.closeReason == .appSwitch
                let withinBridge = next.start.timeIntervalSince(prev.end) < config.bridgeGap
                if midShort, sameStream, softBreaks, withinBridge {
                    let mergedTitles = prev.titles + next.titles.filter { !prev.titles.contains($0) }
                    let merged = ActivityBlock(
                        id: prev.id, start: prev.start, end: next.end, bundleID: prev.bundleID,
                        appName: prev.appName, titles: mergedTitles, closeReason: next.closeReason)
                    blocks.replaceSubrange((i - 1)...(i + 1), with: [merged])
                    changed = true
                    break
                }
                i += 1
            }
        }
        return blocks
    }

    private static func dropShort(_ blocks: [ActivityBlock], config: SessionizerConfig) -> [ActivityBlock] {
        blocks.filter { $0.range.duration >= config.minBlock }
    }
}
