import DrawerCore
import SwiftUI

struct DrawerView: View {
    @ObservedObject var store: TodoStore
    @ObservedObject var timer: FocusTimer
    var onToggleSize: () -> Void = {}
    var onNeedsKeyboard: () -> Void = {}

    @State private var showingAdd = false
    @State private var newTaskTitle = ""
    @FocusState private var addFieldFocused: Bool
    @AppStorage("hideCompleted") private var hideCompleted = false
    @AppStorage("uncheckedFirst") private var uncheckedFirst = false
    @AppStorage("showTomorrow") private var showTomorrow = true
    @AppStorage("backlogExpanded") private var backlogExpanded = false
    @AppStorage("archiveExpanded") private var archiveExpanded = false
    @AppStorage("drawerTheme") private var themeRaw = DrawerTheme.default.rawValue
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @StateObject private var celebration = CelebrationCenter()
    @StateObject private var swipe = SwipeCoordinator()
    @StateObject private var scrollMonitor = ScrollSwipeMonitor()

    private var theme: DrawerTheme { DrawerTheme(rawValue: themeRaw) ?? .default }

    var body: some View {
        ZStack {
            PanelBackground(theme: theme)
                // Pin the background to its active appearance so the glass /
                // material does not brighten when the panel becomes key on click
                // and dim when it resigns. controlActiveState drives that styling.
                .environment(\.controlActiveState, .active)

            VStack(alignment: .leading, spacing: 13) {
                HStack(alignment: .center, spacing: 10) {
                    TimerHeaderView(timer: timer)
                    Spacer(minLength: 8)
                    HStack(spacing: 2) {
                        DrawerIconButton(
                            systemName: "plus",
                            accessibilityLabel: "Add task",
                            helpText: "Show a field for adding a task.",
                            isSelected: showingAdd
                        ) {
                            showingAdd.toggle()
                            if showingAdd {
                                onNeedsKeyboard() // panel must be key or typing leaks elsewhere
                                addFieldFocused = true
                            }
                        }
                        Menu {
                            Toggle("Hide completed", isOn: $hideCompleted)
                            Toggle("Unchecked first", isOn: $uncheckedFirst)
                        } label: {
                            Image(systemName: "line.3.horizontal.decrease")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(
                                    hideCompleted || uncheckedFirst
                                        ? Color.accentColor
                                        : Color.secondary
                                )
                                .frame(width: 30, height: 30)
                                .background(
                                    hideCompleted || uncheckedFirst
                                        ? Color.accentColor.opacity(0.14)
                                        : Color.clear,
                                    in: RoundedRectangle(cornerRadius: 9, style: .continuous)
                                )
                                .contentShape(
                                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                                )
                        }
                        .menuStyle(.button)
                        .buttonStyle(.plain)
                        .menuIndicator(.hidden)
                        .fixedSize()
                        .frame(width: 30, height: 30)
                        .accessibilityLabel("Filter tasks")
                        .accessibilityHint("Show task filtering and sorting options.")
                        .help("Filter and sort")
                        DrawerIconButton(
                            systemName: "arrow.up.left.and.arrow.down.right",
                            accessibilityLabel: "Expand or collapse drawer",
                            helpText: "Expand the drawer to full height or collapse it."
                        ) {
                            onToggleSize()
                        }
                    }
                    .padding(3)
                    .background(.quaternary.opacity(0.45), in: RoundedRectangle(cornerRadius: 12))
                }

                if showingAdd {
                    HStack(spacing: 8) {
                        Image(systemName: "plus.circle.fill")
                            .foregroundStyle(.tint)
                        TextField("Add a task for today", text: $newTaskTitle)
                            .textFieldStyle(.plain)
                            .focused($addFieldFocused)
                            .onSubmit {
                                store.add(newTaskTitle)
                                newTaskTitle = ""
                                showingAdd = false
                            }
                    }
                    .padding(.horizontal, 11)
                    .padding(.vertical, 9)
                    .background(.quaternary.opacity(0.65), in: RoundedRectangle(cornerRadius: 11))
                    .transition(.move(edge: .top).combined(with: .opacity))
                }

                ScrollView {
                    VStack(alignment: .leading, spacing: 5) {
                        if let msg = store.statusMessage {
                            statusView(msg)
                        }
                        let today = arranged(store.todayItems)
                        let carried = arranged(store.carriedItems)
                        if !today.isEmpty {
                            sectionHeader("Today", count: today.count, isPrimary: true)
                            ForEach(today) { item in
                                taskRow(item)
                            }
                        }
                        if !carried.isEmpty {
                            sectionHeader("Carried over", count: carried.count)
                                .padding(.top, 8)
                            ForEach(carried) { item in
                                taskRow(item)
                            }
                        }
                        let upcoming = showTomorrow ? arranged(store.upcomingItems) : []
                        if !upcoming.isEmpty {
                            sectionHeader(store.upcomingLabel, count: upcoming.count)
                                .padding(.top, 8)
                            ForEach(upcoming) { item in
                                taskRow(item)
                            }
                        }
                        collapsibleSection(
                            title: "BACKLOG",
                            items: store.backlogItems,
                            isExpanded: $backlogExpanded,
                            helpText: "Tasks under \"## Backlog\" in the file"
                        )
                        collapsibleSection(
                            title: "ARCHIVE",
                            items: store.archiveItems,
                            isExpanded: $archiveExpanded,
                            helpText: "Tasks under \"## Archive\" in the file"
                        )
                        if today.isEmpty && carried.isEmpty && upcoming.isEmpty
                            && store.statusMessage == nil {
                            emptyState
                        }
                    }
                }
                .scrollIndicators(.hidden)
            }
            .padding(14)

            // Confetti renders here, above the scroll view, so pieces are never
            // clipped by the list. Rows report checkbox points in "panel" space.
            ConfettiLayer(center: celebration)
        }
        .coordinateSpace(.named("panel"))
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .fontDesign(theme.fontDesign)
        .environment(\.drawerTheme, theme)
        .environmentObject(celebration)
        .environmentObject(swipe)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.18), value: showingAdd)
        .onAppear {
            scrollMonitor.start(swipe)
            // A right swipe on a row reports its id here. Flip its file marker.
            swipe.onProgress = { [weak store] id in
                guard let store, let item = store.item(withID: id) else { return }
                store.setInProgress(item, !item.isInProgress)
            }
        }
        .onDisappear { scrollMonitor.stop() }
    }

    /// One run of consecutive tasks sharing a "### " subheading (or none).
    private struct TaskGroup: Identifiable {
        let id: Int
        let title: String?
        var items: [TodoItem]
    }

    /// Splits items into consecutive subsection runs (file order), then
    /// applies the user's filter/sort prefs within each run so groups stay
    /// intact under "Unchecked first".
    private func grouped(_ items: [TodoItem]) -> [TaskGroup] {
        var groups: [TaskGroup] = []
        for item in items {
            if let last = groups.indices.last, groups[last].title == item.subsection {
                groups[last].items.append(item)
            } else {
                groups.append(TaskGroup(id: groups.count, title: item.subsection, items: [item]))
            }
        }
        return groups
            .map { TaskGroup(id: $0.id, title: $0.title, items: arranged($0.items)) }
            .filter { !$0.items.isEmpty }
    }

    /// Collapsible task group (Backlog, Archive): chevron header with a
    /// count, rows shown only while expanded, grouped under their "### "
    /// subheadings. Renders nothing when empty.
    @ViewBuilder
    private func collapsibleSection(
        title: String,
        items: [TodoItem],
        isExpanded: Binding<Bool>,
        helpText: String
    ) -> some View {
        let groups = grouped(items)
        let count = groups.reduce(0) { $0 + $1.items.count }
        if count > 0 {
            Button {
                if reduceMotion {
                    isExpanded.wrappedValue.toggle()
                } else {
                    withAnimation(.easeOut(duration: 0.16)) {
                        isExpanded.wrappedValue.toggle()
                    }
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: isExpanded.wrappedValue
                          ? "chevron.down" : "chevron.right")
                        .font(.system(size: 9, weight: .bold))
                    Text(title)
                        .font(.system(size: 10, weight: .bold))
                        .tracking(0.7)
                    Text("\(count)")
                        .font(.system(size: 10, weight: .semibold, design: .rounded))
                        .foregroundStyle(.tertiary)
                }
                .foregroundStyle(.secondary)
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
            }
            .buttonStyle(.plain)
            .padding(.top, 8)
            .help(helpText)
            if isExpanded.wrappedValue {
                ForEach(groups) { group in
                    if let subtitle = group.title {
                        Text(subtitle.uppercased())
                            .font(.system(size: 9, weight: .semibold))
                            .tracking(0.6)
                            .foregroundStyle(.tertiary)
                            .padding(.horizontal, 8)
                            .padding(.top, 6)
                            .padding(.bottom, 2)
                    }
                    ForEach(group.items) { item in
                        taskRow(item)
                    }
                }
            }
        }
    }

    /// One task row, wired so its note editor can ask the panel for the
    /// keyboard (the panel is non-activating, so a focused field is not
    /// enough on its own).
    private func taskRow(_ item: TodoItem) -> some View {
        TaskRowView(item: item, store: store, requestKeyboard: onNeedsKeyboard)
    }

    private func sectionHeader(
        _ title: String,
        count: Int,
        isPrimary: Bool = false
    ) -> some View {
        let headerStyle = theme.sectionHeaderStyle
        let titleColor: AnyShapeStyle = headerStyle
            ?? (theme.sectionHeaderTinted
                ? AnyShapeStyle(.tint)
                : AnyShapeStyle(isPrimary ? AnyShapeStyle(.primary) : AnyShapeStyle(.secondary)))
        return HStack(spacing: 7) {
            if isPrimary && !theme.sectionHeaderTinted && headerStyle == nil {
                Circle()
                    .fill(theme.accent)
                    .frame(width: 5, height: 5)
            }
            Text(theme.sectionHeaderUppercased ? title.uppercased() : title)
                .font(theme.sectionHeaderFont)
                .tracking(theme.sectionHeaderUppercased ? 0.8 : 0)
                .foregroundStyle(titleColor)
            Spacer()
            Text("\(count)")
                .font(.system(size: 10, weight: .semibold, design: .rounded))
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
    }

    private func statusView(_ message: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "doc.badge.ellipsis")
            Text(message)
        }
        .font(.callout)
        .foregroundStyle(.secondary)
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.55), in: RoundedRectangle(cornerRadius: 11))
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "checkmark.circle")
                .font(.system(size: 26, weight: .light))
                .foregroundStyle(.tertiary)
            Text(hideCompleted && !(store.todayItems.isEmpty && store.carriedItems.isEmpty)
                 ? "All done for today"
                 : "Nothing planned for today")
                .font(.headline)
            Text("Add a task or enjoy the clear list.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 36)
    }

    /// Applies the user's filter/sort prefs. Sort is stable (keeps file order
    /// within each group).
    private func arranged(_ items: [TodoItem]) -> [TodoItem] {
        var out = items
        if hideCompleted {
            out = out.filter { !$0.isDone }
        }
        if uncheckedFirst {
            out = out.enumerated()
                .sorted { a, b in
                    if a.element.isDone != b.element.isDone { return !a.element.isDone }
                    return a.offset < b.offset
                }
                .map(\.element)
        }
        // In-progress tasks always float to the very top of their section, so
        // what you are actively working on stays in view. Stable otherwise.
        out = out.enumerated()
            .sorted { a, b in
                if a.element.isInProgress != b.element.isInProgress {
                    return a.element.isInProgress
                }
                return a.offset < b.offset
            }
            .map(\.element)
        return out
    }
}
