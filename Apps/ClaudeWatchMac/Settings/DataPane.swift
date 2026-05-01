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
        var csv = "timestamp,used_5h,ceiling_5h,used_week,ceiling_week,plan\n"
        if let arr = try? ctx.snapshots.fetchRecent(within: 30 * 86400) {
            for s in arr {
                csv += "\(Int(s.timestamp.timeIntervalSince1970)),\(s.used5h),\(s.ceiling5h),\(s.usedWeek),\(s.ceilingWeek),\(s.plan.displayName)\n"
            }
        }
        try? csv.write(to: url, atomically: true, encoding: .utf8)
    }
}
