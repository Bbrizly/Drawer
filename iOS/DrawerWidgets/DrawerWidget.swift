import AppIntents
import SwiftUI
import UIKit
import WidgetKit

struct DrawerWidgetEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetSnapshot
    let interactionFeedback: WidgetInteractionFeedback?
}

struct DrawerWidgetProvider: TimelineProvider {
    func placeholder(in context: Context) -> DrawerWidgetEntry {
        DrawerWidgetEntry(date: Date(), snapshot: .preview, interactionFeedback: nil)
    }

    func getSnapshot(in context: Context, completion: @escaping (DrawerWidgetEntry) -> Void) {
        completion(DrawerWidgetEntry(
            date: Date(),
            snapshot: context.isPreview ? .preview : WidgetSnapshotStore.current(),
            interactionFeedback: context.isPreview ? nil : WidgetInteractionFeedbackStore.current()
        ))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<DrawerWidgetEntry>) -> Void) {
        let entry = DrawerWidgetEntry(
            date: Date(),
            snapshot: WidgetSnapshotStore.current(),
            interactionFeedback: WidgetInteractionFeedbackStore.current()
        )
        completion(Timeline(
            entries: [entry],
            policy: .after(Date().addingTimeInterval(15 * 60))
        ))
    }
}

struct DrawerWidget: Widget {
    static let kind = "DrawerTodayWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: Self.kind, provider: DrawerWidgetProvider()) { entry in
            DrawerWidgetView(
                snapshot: entry.snapshot,
                interactionFeedback: entry.interactionFeedback
            )
            .containerBackground(for: .widget) {
                Color(uiColor: .systemBackground)
            }
        }
        .configurationDisplayName("Drawer")
        .description("Your day, straight from Drawer.md.")
        .supportedFamilies([
            .systemMedium,
            .systemLarge,
            .accessoryRectangular,
            .accessoryCircular,
        ])
    }
}

private struct DrawerWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let snapshot: WidgetSnapshot
    let interactionFeedback: WidgetInteractionFeedback?

    var body: some View {
        switch family {
        case .accessoryCircular:
            accessoryCircular
        case .accessoryRectangular:
            accessoryRectangular
        case .systemLarge:
            homeWidget(maxTasks: 8, large: true)
        default:
            homeWidget(maxTasks: 4, large: false)
        }
    }

    private func homeWidget(maxTasks: Int, large: Bool) -> some View {
        VStack(alignment: .leading, spacing: large ? 9 : 7) {
            header

            if let interactionFeedback {
                failureNotice(interactionFeedback)
            }

            if snapshot.todayKey.isEmpty {
                Spacer(minLength: 2)
                Label("Open Drawer to connect Drawer.md", systemImage: "doc.badge.plus")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                Spacer(minLength: 2)
            } else {
                let taskLimit = interactionFeedback == nil ? maxTasks : max(1, maxTasks - 1)
                let tasks = Array(snapshot.actionableTasks.prefix(taskLimit))
                if tasks.isEmpty {
                    Spacer(minLength: 1)
                    HStack(spacing: 8) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.tint)
                        Text("You're clear.")
                            .font(.subheadline.weight(.semibold))
                    }
                    Spacer(minLength: 1)
                } else {
                    VStack(spacing: large ? 6 : 4) {
                        ForEach(tasks) { task in
                            WidgetTaskRow(task: task)
                        }
                    }
                    Spacer(minLength: 0)
                }
            }
        }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            VStack(alignment: .leading, spacing: 0) {
                Text("TODAY")
                    .font(.caption2.weight(.heavy))
                    .tracking(0.8)
                    .foregroundStyle(.secondary)
                if !snapshot.todayKey.isEmpty {
                    Text(snapshot.generatedAt, format: .dateTime.weekday(.abbreviated).month(.abbreviated).day())
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.tertiary)
                }
            }

            Spacer(minLength: 4)

            if !snapshot.todayKey.isEmpty {
                Text("\(snapshot.remaining) left")
                    .font(.caption.weight(.bold))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .invalidatableContent()
            }

            Link(destination: URL(string: "drawer://capture")!) {
                Image(systemName: "plus")
                    .font(.system(size: 12, weight: .heavy))
                    .frame(width: 28, height: 28)
                    .background(.quaternary, in: Circle())
            }
            .accessibilityLabel("Add Drawer task")
        }
    }

    private func failureNotice(_ feedback: WidgetInteractionFeedback) -> some View {
        Link(destination: URL(string: "drawer://today")!) {
            HStack(spacing: 6) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.caption2.weight(.bold))
                Text(feedback.message)
                    .font(.caption2.weight(.semibold))
                    .lineLimit(1)
                Spacer(minLength: 0)
                Image(systemName: "arrow.up.right")
                    .font(.system(size: 8, weight: .bold))
            }
            .foregroundStyle(.orange)
        }
        .accessibilityLabel("Drawer update failed. Open Drawer to recover.")
    }

    private var accessoryRectangular: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 5) {
                Text("Drawer")
                    .font(.caption.weight(.bold))
                Spacer(minLength: 2)
                if interactionFeedback != nil {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.caption2.weight(.bold))
                }
                Text("\(snapshot.remaining)")
                    .font(.caption.weight(.bold))
                    .monospacedDigit()
                    .invalidatableContent()
            }
            if let next = snapshot.actionableTasks.first {
                Text(next.title)
                    .font(.caption2)
                    .lineLimit(2)
                    .privacySensitive()
                    .invalidatableContent()
            } else {
                Text(snapshot.todayKey.isEmpty ? "Open Drawer to connect" : "You're clear")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
        .widgetURL(URL(string: "drawer://today"))
    }

    private var accessoryCircular: some View {
        ZStack {
            AccessoryWidgetBackground()
            VStack(spacing: -1) {
                if interactionFeedback != nil {
                    Image(systemName: "exclamationmark")
                        .font(.system(size: 8, weight: .bold))
                }
                Text("\(snapshot.remaining)")
                    .font(.system(size: 17, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .invalidatableContent()
                Text("left")
                    .font(.system(size: 8, weight: .bold))
                    .textCase(.uppercase)
            }
        }
        .widgetURL(URL(string: "drawer://today"))
        .accessibilityLabel(
            interactionFeedback == nil
                ? "\(snapshot.remaining) Drawer tasks remaining"
                : "Drawer update failed. \(snapshot.remaining) tasks shown from the last good update"
        )
    }
}

private struct WidgetTaskRow: View {
    let task: WidgetTask

    var body: some View {
        HStack(spacing: 7) {
            Button(intent: ToggleDrawerTaskIntent(task: task)) {
                Image(systemName: task.isInProgress ? "circle.lefthalf.filled" : "circle")
                    .font(.system(size: 15, weight: .semibold))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(task.isInProgress ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
                    .frame(width: 24, height: 24)
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Complete \(task.title)")

            Text(task.title)
                .font(.caption.weight(task.isInProgress ? .semibold : .regular))
                .lineLimit(1)
                .privacySensitive()
                .invalidatableContent()

            Spacer(minLength: 2)

            if task.minutes != 25 {
                Text("\(task.minutes)m")
                    .font(.system(size: 9, weight: .bold, design: .rounded))
                    .foregroundStyle(.tertiary)
                    .monospacedDigit()
            }
        }
        .frame(minHeight: 24)
    }
}

private extension WidgetSnapshot {
    static let preview: WidgetSnapshot = {
        let data = """
        ## 2026-08-27
        - [ ] Carry this forward

        ## 2026-08-28
        - [/] Polish the iPhone interaction (45m)
        - [ ] Send the build
        - [ ] Gym
        - [ ] Read release notes (15m)
        """.data(using: .utf8)!
        return .make(from: data, todayKey: "2026-08-28")
    }()
}
