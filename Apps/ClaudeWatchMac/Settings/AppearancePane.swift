import SwiftUI
import UsageCore

/// Two groups of appearance settings.
///
/// **Theme** overrides the popover's color scheme independently of the
/// system-wide macOS setting. Persisted under SettingsRepository.theme
/// and read back by PopoverController on every popover open, so changes
/// take effect the next time the user clicks the menu bar icon.
///
/// **Menu bar** picks which of the three quota percentages appear in the
/// status item and whether they carry short labels. Each toggle posts
/// `.menuBarDisplayOptionsChanged` so the bar redraws immediately —
/// waiting for the next 90 s poll would make the checkbox look broken.
struct AppearancePane: View {
    let ctx: AppContext
    @State private var theme: String = "auto"
    @State private var show5h = true
    @State private var showWeek = false
    @State private var showFable = true
    @State private var showLabels = true
    /// False when the account has no Fable quota. The checkbox is
    /// disabled rather than hidden: a user on a plan without Fable
    /// should be able to see that the option exists.
    @State private var fableAvailable = false

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

            Divider()

            Text("settings.appearance.menuBarSection")
                .font(.subheadline.weight(.semibold))
            Toggle("settings.appearance.menuBarShow5h", isOn: $show5h)
                .onChange(of: show5h) { v in write(.menuBarShow5h, v) }
            Toggle("settings.appearance.menuBarShowWeek", isOn: $showWeek)
                .onChange(of: showWeek) { v in write(.menuBarShowWeek, v) }
            Toggle("settings.appearance.menuBarShowFable", isOn: $showFable)
                .disabled(!fableAvailable)
                .onChange(of: showFable) { v in write(.menuBarShowFable, v) }
            Toggle("settings.appearance.menuBarShowLabels", isOn: $showLabels)
                .onChange(of: showLabels) { v in write(.menuBarShowLabels, v) }

            Spacer()
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .onAppear { load() }
    }

    private func load() {
        let d = MenuBarDisplayOptions.default
        theme = (try? ctx.settings.get(.theme)).flatMap { $0 } ?? "auto"
        show5h     = (try? ctx.settings.getBool(.menuBarShow5h,     default: d.show5h))     ?? d.show5h
        showWeek   = (try? ctx.settings.getBool(.menuBarShowWeek,   default: d.showWeek))   ?? d.showWeek
        showFable  = (try? ctx.settings.getBool(.menuBarShowFable,  default: d.showFable))  ?? d.showFable
        showLabels = (try? ctx.settings.getBool(.menuBarShowLabels, default: d.showLabels)) ?? d.showLabels
        fableAvailable = ctx.controller?.state.latest?.fractionFable != nil
    }

    private func write(_ key: SettingsRepository.Key, _ value: Bool) {
        try? ctx.settings.setBool(key, value)
        NotificationCenter.default.post(name: .menuBarDisplayOptionsChanged, object: nil)
    }
}
