import SwiftUI
import UsageCore

struct DataPane: View {
    let ctx: AppContext

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Button("settings.data.exportCSV") { exportCSV() }
            Button("settings.data.deleteAll", role: .destructive) {
                let alert = NSAlert()
                alert.messageText = String(localized: "settings.data.confirmDeleteTitle",
                    defaultValue: "Delete all data?")
                alert.informativeText = String(localized: "settings.data.confirmDeleteBody",
                    defaultValue: "This removes the local SQLite database and signs you out. iCloud-synced rows on this device are also forgotten.")
                alert.alertStyle = .critical
                alert.addButton(withTitle: String(localized: "settings.data.confirmDeleteButton",
                    defaultValue: "Delete"))
                alert.addButton(withTitle: String(localized: "settings.data.cancelButton",
                    defaultValue: "Cancel"))
                if alert.runModal() == .alertFirstButtonReturn {
                    try? FileManager.default.removeItem(at: dbURL())
                    NSApp.terminate(nil)
                }
            }
            Spacer()
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func dbURL() -> URL {
        let dir = (try? FileManager.default
            .url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: false))
            ?? FileManager.default.temporaryDirectory
        return dir.appendingPathComponent("ClaudeWatch").appendingPathComponent("usage.db")
    }

    private func exportCSV() {
        let panel = NSSavePanel()
        // Keep filename in English/Latin — not localized per spec.
        panel.nameFieldStringValue = "claude-watch.csv"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        // used_fable is on the same 0–10000 scale as the other two windows.
        // It is written as an EMPTY field, never 0, when the account has no
        // Fable quota or the row predates the migration that began recording
        // it — a 0 would claim the quota went unused, which is a different
        // fact from "there was no such quota". Spreadsheets and pandas both
        // read an empty CSV field as missing, which is what it is.
        //
        // There is no ceiling_fable column because the ceiling is a fixed
        // 10000 for this window, not a stored per-row value.
        var csv = "timestamp,used_5h,ceiling_5h,used_week,ceiling_week,used_fable,fable_is_active,plan\n"
        if let arr = try? ctx.snapshots.fetchRecent(within: 30 * 86400) {
            for s in arr {
                let fable = s.usedFable.map(String.init) ?? ""
                csv += "\(Int(s.timestamp.timeIntervalSince1970)),\(s.used5h),\(s.ceiling5h),\(s.usedWeek),\(s.ceilingWeek),\(fable),\(s.fableIsActive ? 1 : 0),\(s.plan.displayName)\n"
            }
        }
        try? csv.write(to: url, atomically: true, encoding: .utf8)
    }
}
