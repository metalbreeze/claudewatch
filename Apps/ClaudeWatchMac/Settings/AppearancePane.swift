import SwiftUI
import UsageCore

/// Lets the user override the popover's color scheme, separate from the
/// system-wide macOS appearance.
///   • Automatic — follow system Light/Dark setting (default)
///   • Light     — force light mode regardless of system
///   • Dark      — force dark mode regardless of system
///
/// The choice is persisted under SettingsRepository.theme and read back
/// by PopoverController on every popover open, so changes take effect
/// the next time the user clicks the menu bar icon (no app restart).
struct AppearancePane: View {
    let ctx: AppContext
    @State private var theme: String = "auto"

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("settings.appearance.theme")
                .font(.subheadline.weight(.semibold))
            Picker("", selection: $theme) {
                Text("settings.appearance.themeAuto").tag("auto")
                Text("settings.appearance.themeLight").tag("light")
                Text("settings.appearance.themeDark").tag("dark")
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .onChange(of: theme) { newValue in
                try? ctx.settings.set(.theme, newValue)
            }
            Text("settings.appearance.themeNote")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            Spacer()
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .onAppear {
            theme = (try? ctx.settings.get(.theme)).flatMap { $0 } ?? "auto"
        }
    }
}
