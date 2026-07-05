import AppKit
import DrawerCore
import SwiftUI

/// Settings for automatic attribution: the Accessibility permission state and
/// the user matching rules (substring on bundle id or window title -> task).
/// The idle threshold and 7-day trail retention are hardcoded, not knobs.
struct AttributionSettingsView: View {
    @ObservedObject var controller: AttributionController

    @State private var trusted = ActivitySampler.ensureAccessibilityTrust(prompt: false)
    @State private var newField: AttributionRule.Field = .title
    @State private var newSubstring = ""
    @State private var newTaskTitle = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Drawer reads the frontmost app name and window title, plus system idle time. Nothing else, and nothing leaves your Mac. The raw trail is kept 7 days, then deleted.")
                .font(.callout).foregroundStyle(.secondary)

            if !trusted {
                permissionRow
            } else {
                Label("Accessibility granted", systemImage: "checkmark.circle")
                    .foregroundStyle(.green)
            }

            Divider()
            Text("Matching rules").font(.headline)
            Text("Map an app or window title to a task. Substring match.")
                .font(.caption).foregroundStyle(.secondary)

            ForEach(controller.ruleStore.rules) { rule in
                HStack {
                    Text("\(rule.field == .bundleID ? "app" : "title") contains “\(rule.substring)” → \(rule.taskTitle)")
                        .font(.callout)
                    Spacer()
                    Button(role: .destructive) { controller.removeRule(rule.id) } label: {
                        Image(systemName: "trash")
                    }
                    .buttonStyle(.borderless)
                }
            }

            addRuleRow
        }
        .padding(16)
        .frame(width: 460, alignment: .leading)
    }

    private var permissionRow: some View {
        HStack {
            Label("Accessibility permission needed", systemImage: "lock")
                .foregroundStyle(.orange)
            Spacer()
            Button("Grant…") {
                if !ActivitySampler.ensureAccessibilityTrust(prompt: true) {
                    NSWorkspace.shared.open(URL(string:
                        "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
                }
                trusted = ActivitySampler.ensureAccessibilityTrust(prompt: false)
            }
        }
    }

    private var addRuleRow: some View {
        HStack(spacing: 6) {
            Picker("", selection: $newField) {
                Text("App").tag(AttributionRule.Field.bundleID)
                Text("Title").tag(AttributionRule.Field.title)
            }
            .labelsHidden().frame(width: 80)
            TextField("contains…", text: $newSubstring).frame(width: 120)
            Text("→")
            TextField("task title", text: $newTaskTitle)
            Button("Add") {
                let substring = newSubstring.trimmingCharacters(in: .whitespaces)
                let task = newTaskTitle.trimmingCharacters(in: .whitespaces)
                guard !substring.isEmpty, !task.isEmpty else { return }
                controller.addRule(AttributionRule(field: newField, substring: substring, taskTitle: task))
                newSubstring = ""; newTaskTitle = ""
            }
        }
    }
}
