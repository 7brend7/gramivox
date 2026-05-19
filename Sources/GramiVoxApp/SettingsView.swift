import SwiftUI

struct SettingsView: View {
    @ObservedObject var coordinator: AppCoordinator
    @ObservedObject var settings: AppSettings

    var body: some View {
        Form {
            Section("Hotkey") {
                TextField("Key", text: $settings.hotKeyString)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 80)

                Toggle("Control", isOn: $settings.usesControl)
                Toggle("Option", isOn: $settings.usesOption)
                Toggle("Command", isOn: $settings.usesCommand)
                Toggle("Shift", isOn: $settings.usesShift)

                Text("Current: \(settings.hotKeyConfiguration.displayString)")
                    .foregroundStyle(.secondary)
            }

            Section("Prompt") {
                TextField("Prompt template", text: $settings.promptTemplate, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                    .lineLimit(3...6)

                Text("Use `[SELECTED TEXT]` where the captured text should go.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Section("Permissions") {
                HStack {
                    Text(coordinator.accessibilityGranted ? "Accessibility is enabled." : "Accessibility access is still required.")
                    Spacer()
                    Button("Request Access") {
                        coordinator.requestAccessibilityAccess()
                    }
                }
            }
        }
        .formStyle(.grouped)
        .padding(20)
        .frame(width: 420)
    }
}
