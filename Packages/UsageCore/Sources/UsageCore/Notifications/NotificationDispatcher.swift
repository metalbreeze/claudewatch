import Foundation
import UserNotifications

public struct NotificationDispatcher {
    public init() {}

    public func requestAuthorization() async -> Bool {
        let granted = (try? await UNUserNotificationCenter.current()
            .requestAuthorization(options: [.alert, .sound, .badge])) ?? false
        return granted
    }

    public func deliver(_ kind: AlertKind, snapshot s: UsageSnapshot, forecast f: ForecastResult?) async {
        let center = UNUserNotificationCenter.current()
        let req = makeRequest(kind: kind, snapshot: s, forecast: f)
        try? await center.add(req)
    }

    private func makeRequest(kind: AlertKind, snapshot s: UsageSnapshot, forecast f: ForecastResult?) -> UNNotificationRequest {
        let content = UNMutableNotificationContent()
        switch kind {
        case .fiveHourForecast:
            content.title = "Approaching 5h limit"
            if let h = f?.projectedHitTime {
                let df = DateFormatter(); df.timeStyle = .short
                content.body = "At your current rate you'll hit the limit at \(df.string(from: h))."
            } else { content.body = "Slow down or risk hitting the 5h limit." }
        case .fiveHourHit:
            content.title = "5h limit reached"; content.body = "Your 5h window is exhausted."
        case .weekNinety:
            content.title = "Weekly usage at 90%"; content.body = "You've used 90% of your weekly cap."
        case .weekHundred:
            content.title = "Weekly limit reached"; content.body = "Resets at \(s.resetTimeWeek)."
        case .authExpired:
            content.title = "Claude.ai login expired"; content.body = "Tap to re-login."
        case .scrapeBroken:
            content.title = "Source format changed"; content.body = "Update Claude Usage to restore tracking."
        }
        content.sound = .default
        return UNNotificationRequest(identifier: kind.rawValue + "-\(Int(Date().timeIntervalSince1970))",
                                      content: content, trigger: nil)
    }
}
