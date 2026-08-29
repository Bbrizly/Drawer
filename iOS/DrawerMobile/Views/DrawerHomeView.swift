import DrawerCore
import SwiftUI

struct DrawerHomeView: View {
    @ObservedObject var model: DrawerMobileModel
    let changeFile: () -> Void

    @AppStorage("drawer.ios.hideCompleted") private var hideCompleted = false
    @State private var selectedTask: TodoItem?
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
                            .transition(.scale(scale: 0.97).combined(with: .opacity))
                    }

                    if let status = model.statusMessage, !status.isEmpty {
                        statusBanner(status)
                    }

                    if !visibleCarried.isEmpty {
                        taskSection(
                            title: "Carried over",
                            subtitle: "Still open",
                            items: visibleCarried,
                            accent: true
                        )
                    }

                    taskSection(
                        title: "Today",
                        subtitle: visibleToday.isEmpty ? "Clear" : nil,
                        items: visibleToday,
                        accent: false
                    )

                    if !model.upcomingItems.isEmpty {
                        collapsibleSection(
                            title: model.upcomingLabel.isEmpty ? "Next" : model.upcomingLabel,
                            count: visibleUpcoming.count,
                            isExpanded: $showUpcoming,
                            items: visibleUpcoming
                        )
                    }

                    if !model.backlogItems.isEmpty {
                        collapsibleSection(
                            title: "Backlog",
                            count: visibleBacklog.count,
                            isExpanded: $showBacklog,
                            items: visibleBacklog
                        )
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
            .safeAreaInset(edge: .bottom, spacing: 0) {
                QuickCaptureBar(model: model)
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Toggle("Hide completed", isOn: $hideCompleted)
                        Divider()
                        Button("Reload", systemImage: "arrow.clockwise") {
                            model.reload()
                        }
                        Button("Change Drawer.md", systemImage: "doc") {
                            changeFile()
                        }
                        Button("Disconnect", systemImage: "xmark.circle", role: .destructive) {
                            model.disconnect()
                        }
                    } label: {
                        Image(systemName: "ellipsis")
                            .font(.system(size: 17, weight: .semibold))
                            .frame(width: 36, height: 36)
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
            .refreshable { model.reload() }
        }
    }

    private var dayHeader: some View {
        HStack(alignment: .bottom, spacing: 16) {
            VStack(alignment: .leading, spacing: 3) {
                Text(Date.now.formatted(.dateTime.weekday(.wide)))
                    .font(.system(size: 34, weight: .bold, design: .rounded))
                    .tracking(-1.1)
                Text(Date.now.formatted(.dateTime.month(.wide).day()))
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 10)

            VStack(alignment: .trailing, spacing: 2) {
                Text("\(model.remainingCount)")
                    .font(.system(size: 28, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                Text("left")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(model.remainingCount) tasks remaining")
        }
        .padding(.horizontal, 4)
        .padding(.top, 8)
        .padding(.bottom, 2)
    }

    @ViewBuilder
    private func taskSection(
        title: String,
        subtitle: String?,
        items: [TodoItem],
        accent: Bool
    ) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(alignment: .firstTextBaseline) {
                Text(title.uppercased())
                    .font(.caption.weight(.bold))
                    .tracking(0.8)
                    .foregroundStyle(accent ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
                if let subtitle {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                Spacer()
            }
            .padding(.horizontal, 4)

            TaskTray(items: items, model: model) { item in
                selectedTask = item
            }
        }
    }

    @ViewBuilder
    private func collapsibleSection(
        title: String,
        count: Int,
        isExpanded: Binding<Bool>,
        items: [TodoItem]
    ) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            Button {
                withAnimation(.snappy(duration: 0.22)) {
                    isExpanded.wrappedValue.toggle()
                }
            } label: {
                HStack(spacing: 8) {
                    Text(title.uppercased())
                        .font(.caption.weight(.bold))
                        .tracking(0.8)
                    Text("\(count)")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.tertiary)
                    Spacer()
                    Image(systemName: "chevron.down")
                        .font(.caption.weight(.bold))
                        .rotationEffect(.degrees(isExpanded.wrappedValue ? 180 : 0))
                        .foregroundStyle(.tertiary)
                }
                .foregroundStyle(.secondary)
                .contentShape(Rectangle())
                .padding(.horizontal, 4)
                .frame(minHeight: 36)
            }
            .buttonStyle(TactileButtonStyle(pressedScale: 0.99))

            if isExpanded.wrappedValue {
                TaskTray(items: items, model: model) { item in
                    selectedTask = item
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }

    @ViewBuilder
    private func statusBanner(_ status: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            Text(status)
                .font(.footnote)
                .foregroundStyle(.secondary)
            Spacer(minLength: 0)
        }
        .padding(13)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func filtered(_ items: [TodoItem]) -> [TodoItem] {
        hideCompleted ? items.filter { !$0.isDone } : items
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
                    Image(systemName: "checkmark")
                        .font(.footnote.weight(.bold))
                    Text("Nothing here.")
                        .font(.subheadline)
                    Spacer()
                }
                .foregroundStyle(.tertiary)
                .padding(.horizontal, 17)
                .frame(minHeight: 58)
            } else {
                ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                    MobileTaskRow(model: model, item: item) {
                        openTask(item)
                    }
                    if index < items.count - 1 {
                        Divider()
                            .padding(.leading, 58)
                            .opacity(0.62)
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
