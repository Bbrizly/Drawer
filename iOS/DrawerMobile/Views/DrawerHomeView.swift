import DrawerCore
import SwiftUI

struct DrawerHomeView: View {
    @ObservedObject var model: DrawerMobileModel
    let changeFile: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage("drawer.ios.hideCompleted") private var hideCompleted = false
    @State private var selectedTask: TodoItem?
    @State private var activeRoutine: DrawerRoutine?
    @State private var showUpcoming = false
    @State private var showBacklog = false

    private var visibleToday: [TodoItem] { filtered(model.todayItems) }
    private var visibleCarried: [TodoItem] { filtered(model.carriedItems) }
    private var visibleUpcoming: [TodoItem] { filtered(model.upcomingItems) }
    private var visibleBacklog: [TodoItem] { filtered(model.backlogItems) }

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 20) {
                    dayHeader

                    if model.focusTimer.phase != .idle {
                        FocusStrip(model: model)
                            .transition(reduceMotion ? .opacity : .scale(scale: 0.97).combined(with: .opacity))
                    }

                    if let status = model.statusMessage, !status.isEmpty {
                        statusBanner(status, tone: model.statusTone)
                    }

                    if !visibleCarried.isEmpty {
                        taskSection(title: "Carried over", subtitle: "Still open", items: visibleCarried, accent: true)
                    }

                    todaySection

                    if !visibleUpcoming.isEmpty {
                        collapsibleSection(
                            title: model.upcomingLabel.isEmpty ? "Next" : model.upcomingLabel,
                            count: visibleUpcoming.count,
                            isExpanded: $showUpcoming,
                            items: visibleUpcoming
                        )
                    }

                    if !visibleBacklog.isEmpty {
                        collapsibleSection(title: "Backlog", count: visibleBacklog.count, isExpanded: $showBacklog, items: visibleBacklog)
                    }

                    Color.clear.frame(height: 8)
                }
                .padding(.horizontal, 16)
                .padding(.top, 10)
                .padding(.bottom, 20)
                .frame(maxWidth: 680)
                .frame(maxWidth: .infinity)
            }
            .scrollIndicators(.hidden)
            .safeAreaInset(edge: .bottom, spacing: 0) { QuickCaptureBar(model: model) }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Toggle("Hide completed", isOn: $hideCompleted)
                        Divider()
                        Button("Reload", systemImage: "arrow.clockwise") { model.reload() }
                        Button("Change Drawer.md", systemImage: "doc") { changeFile() }
                        Button("Disconnect", systemImage: "xmark.circle", role: .destructive) { model.disconnect() }
                    } label: {
                        Image(systemName: "ellipsis")
                            .font(.system(size: 17, weight: .semibold))
                            .frame(width: 44, height: 44)
                    }
                    .accessibilityLabel("Drawer options")
                }
            }
            .toolbarBackground(.hidden, for: .navigationBar)
            .sheet(item: $selectedTask) { item in
                DrawerTaskDetailSheet(model: model, item: item)
                    .presentationDetents([.medium, .large])
                    .presentationDragIndicator(.visible)
                    .presentationCornerRadius(30)
            }
            .fullScreenCover(item: $activeRoutine) { routine in
                DrawerRoutineSession(model: model, title: routine.title)
            }
            .refreshable { model.reload() }
        }
    }

    private var dayHeader: some View {
        HStack(alignment: .bottom, spacing: 16) {
            VStack(alignment: .leading, spacing: 3) {
                Text(Date.now.formatted(.dateTime.weekday(.wide)))
                    .font(.system(size: 34, weight: .bold, design: .rounded))
                    .tracking(-1.1)
                    .minimumScaleFactor(0.82)
                Text(Date.now.formatted(.dateTime.month(.wide).day()))
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 10)
            VStack(alignment: .trailing, spacing: 2) {
                Text("\(model.remainingCount)")
                    .font(.system(size: 28, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                Text("left").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(model.remainingCount) tasks remaining")
        }
        .padding(.horizontal, 4)
        .padding(.top, 8)
        .padding(.bottom, 2)
    }

    private var todaySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text("TODAY")
                    .font(.caption.weight(.bold))
                    .tracking(0.8)
                    .foregroundStyle(.secondary)
                if visibleToday.isEmpty {
                    Text("Clear").font(.caption).foregroundStyle(.tertiary)
                }
                Spacer()
            }
            .padding(.horizontal, 4)

            let ungrouped = visibleToday.filter { $0.subsection == nil }
            if !ungrouped.isEmpty || visibleToday.isEmpty {
                TaskTray(items: ungrouped, model: model) { selectedTask = $0 }
            }

            ForEach(todayRoutines) { routine in
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text(routine.title)
                            .font(.subheadline.weight(.semibold))
                        Spacer()
                        if routine.items.contains(where: { !$0.isDone }) {
                            Button {
                                activeRoutine = routine
                            } label: {
                                Label("Start", systemImage: "play.fill")
                                    .font(.caption.weight(.bold))
                                    .frame(minHeight: 44)
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.borderless)
                            .accessibilityLabel("Start \(routine.title) routine")
                        }
                    }
                    .padding(.horizontal, 4)

                    TaskTray(items: routine.items, model: model) { selectedTask = $0 }
                }
            }
        }
    }

    private var todayRoutines: [DrawerRoutine] {
        var order: [String] = []
        var buckets: [String: [TodoItem]] = [:]
        for item in visibleToday {
            guard let title = item.subsection, !title.isEmpty else { continue }
            if buckets[title] == nil { order.append(title) }
            buckets[title, default: []].append(item)
        }
        return order.map { DrawerRoutine(title: $0, items: buckets[$0] ?? []) }
    }

    @ViewBuilder
    private func taskSection(title: String, subtitle: String?, items: [TodoItem], accent: Bool) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(alignment: .firstTextBaseline) {
                Text(title.uppercased())
                    .font(.caption.weight(.bold))
                    .tracking(0.8)
                    .foregroundStyle(accent ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
                if let subtitle { Text(subtitle).font(.caption).foregroundStyle(.tertiary) }
                Spacer()
            }
            .padding(.horizontal, 4)
            TaskTray(items: items, model: model) { selectedTask = $0 }
        }
    }

    @ViewBuilder
    private func collapsibleSection(title: String, count: Int, isExpanded: Binding<Bool>, items: [TodoItem]) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            Button {
                if reduceMotion {
                    isExpanded.wrappedValue.toggle()
                } else {
                    withAnimation(.snappy(duration: 0.22)) { isExpanded.wrappedValue.toggle() }
                }
            } label: {
                HStack(spacing: 8) {
                    Text(title.uppercased()).font(.caption.weight(.bold)).tracking(0.8)
                    Text("\(count)").font(.caption2.weight(.bold)).foregroundStyle(.tertiary)
                    Spacer()
                    Image(systemName: "chevron.down")
                        .font(.caption.weight(.bold))
                        .rotationEffect(.degrees(isExpanded.wrappedValue ? 180 : 0))
                        .foregroundStyle(.tertiary)
                }
                .foregroundStyle(.secondary)
                .contentShape(Rectangle())
                .padding(.horizontal, 4)
                .frame(minHeight: 44)
            }
            .buttonStyle(TactileButtonStyle(pressedScale: 0.99))
            .accessibilityValue(isExpanded.wrappedValue ? "Expanded" : "Collapsed")

            if isExpanded.wrappedValue {
                TaskTray(items: items, model: model) { selectedTask = $0 }
                    .transition(reduceMotion ? .opacity : .opacity.combined(with: .move(edge: .top)))
            }
        }
    }

    private func statusBanner(_ status: String, tone: DrawerMobileModel.StatusTone) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: statusIcon(tone))
                .foregroundStyle(statusStyle(tone))
                .symbolEffect(.pulse, options: tone == .info ? .repeating.speed(0.25) : .nonRepeating)
            Text(status)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(13)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(statusStyle(tone).opacity(0.15), lineWidth: 0.75)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(statusAccessibilityPrefix(tone) + status)
    }

    private func statusIcon(_ tone: DrawerMobileModel.StatusTone) -> String {
        switch tone {
        case .info: "arrow.triangle.2.circlepath"
        case .warning: "exclamationmark.triangle.fill"
        case .error: "xmark.octagon.fill"
        }
    }

    private func statusStyle(_ tone: DrawerMobileModel.StatusTone) -> Color {
        switch tone {
        case .info: .accentColor
        case .warning: .orange
        case .error: .red
        }
    }

    private func statusAccessibilityPrefix(_ tone: DrawerMobileModel.StatusTone) -> String {
        switch tone {
        case .info: "Status. "
        case .warning: "Attention. "
        case .error: "Error. "
        }
    }

    private func filtered(_ items: [TodoItem]) -> [TodoItem] {
        hideCompleted ? items.filter { !$0.isDone } : items
    }
}

private struct DrawerRoutine: Identifiable {
    let title: String
    let items: [TodoItem]
    var id: String { title }
}

private struct DrawerRoutineSession: View {
    @ObservedObject var model: DrawerMobileModel
    let title: String

    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var allItems: [TodoItem] {
        model.todayItems.filter { $0.subsection == title }
    }

    private var remaining: [TodoItem] { allItems.filter { !$0.isDone } }
    private var completedCount: Int { allItems.count - remaining.count }
    private var current: TodoItem? { remaining.first }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Spacer(minLength: 28)

                VStack(spacing: 7) {
                    Text(title)
                        .font(.system(size: 30, weight: .bold, design: .rounded))
                        .tracking(-0.8)
                        .multilineTextAlignment(.center)
                    Text("\(completedCount) of \(allItems.count)")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }

                Spacer()

                if let current {
                    VStack(spacing: 18) {
                        Image(systemName: current.isInProgress ? "circle.lefthalf.filled" : "circle")
                            .font(.system(size: 30, weight: .medium))
                            .foregroundStyle(.tint)

                        Text(current.title)
                            .font(.system(size: 30, weight: .bold, design: .rounded))
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)

                        if current.minutes != 25 {
                            Text("\(current.minutes) min")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                        }

                        HStack(spacing: 12) {
                            Button {
                                model.startFocus(on: current)
                                DrawerHaptics.shared.focusStarted()
                            } label: {
                                Label("Focus", systemImage: "timer")
                                    .font(.headline)
                                    .frame(maxWidth: .infinity)
                                    .frame(minHeight: 52)
                            }
                            .buttonStyle(.bordered)
                            .buttonBorderShape(.roundedRectangle(radius: 16))

                            Button {
                                if model.toggle(current) {
                                    DrawerHaptics.shared.taskCompleted()
                                    DrawerActionFeedbackCenter.success(
                                        "Completed \(current.title)",
                                        systemImage: "checkmark.circle.fill"
                                    )
                                    if remaining.count == 1 {
                                        DrawerHaptics.shared.groupFinished()
                                        DispatchQueue.main.asyncAfter(deadline: .now() + (reduceMotion ? 0.12 : 0.35)) {
                                            dismiss()
                                        }
                                    }
                                }
                            } label: {
                                Label("Done", systemImage: "checkmark")
                                    .font(.headline)
                                    .frame(maxWidth: .infinity)
                                    .frame(minHeight: 52)
                            }
                            .buttonStyle(.borderedProminent)
                            .buttonBorderShape(.roundedRectangle(radius: 16))
                        }
                    }
                    .padding(.horizontal, 28)
                    .id(current.id)
                    .transition(reduceMotion ? .opacity : .opacity.combined(with: .scale(scale: 0.97)))
                } else {
                    VStack(spacing: 12) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 42))
                            .foregroundStyle(.tint)
                        Text("Done")
                            .font(.title2.bold())
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("Routine complete")
                }

                Spacer()

                if let current, let note = current.note, !note.isEmpty {
                    Text(note)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .lineLimit(4)
                        .padding(.horizontal, 32)
                        .padding(.bottom, 18)
                }
            }
            .animation(reduceMotion ? nil : .snappy(duration: 0.28), value: current?.id)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
        }
    }
}

private struct TaskTray: View {
    let items: [TodoItem]
    @ObservedObject var model: DrawerMobileModel
    let openTask: (TodoItem) -> Void

    var body: some View {
        VStack(spacing: 0) {
            if items.isEmpty {
                HStack(spacing: 9) {
                    Image(systemName: "checkmark").font(.footnote.weight(.bold))
                    Text("Nothing here.").font(.subheadline)
                    Spacer()
                }
                .foregroundStyle(.tertiary)
                .padding(.horizontal, 17)
                .frame(minHeight: 58)
                .accessibilityElement(children: .combine)
            } else {
                ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                    MobileTaskRow(model: model, item: item) { openTask(item) }
                    if index < items.count - 1 {
                        Divider().padding(.leading, 58).opacity(0.62)
                    }
                }
            }
        }
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(.primary.opacity(0.055), lineWidth: 0.75)
        }
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .shadow(color: .black.opacity(0.035), radius: 12, y: 5)
    }
}
