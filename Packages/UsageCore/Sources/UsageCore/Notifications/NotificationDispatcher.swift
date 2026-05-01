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

    private func loc(_ key: String.LocalizationValue) -> String {
        String(localized: key, bundle: .module)
    }

    private func makeRequest(kind: AlertKind, snapshot s: UsageSnapshot, forecast f: ForecastResult?) -> UNNotificationRequest {
        let content = UNMutableNotificationContent()
        switch kind {
        case .fiveHourForecast:
            content.title = loc("notification.fiveHourForecast.title")
            if let h = f?.projectedHitTime {
                let df = DateFormatter(); df.timeStyle = .short
                let timeStr = df.string(from: h)
                content.body = loc("notification.fiveHourForecast.body \(timeStr)")
            } else {
                content.body = loc("notification.fiveHourForecast.bodyNoTime")
            }
        case .fiveHourHit:
            content.title = loc("notification.fiveHourHit.title")
            content.body  = loc("notification.fiveHourHit.body")
        case .weekNinety:
            content.title = loc("notification.weekNinety.title")
            content.body  = loc("notification.weekNinety.body")
        case .weekHundred:
            content.title = loc("notification.weekHundred.title")
            let resetStr = "\(s.resetTimeWeek)"
            content.body = loc("notification.weekHundred.body \(resetStr)")
        case .authExpired:
            content.title = loc("notification.authExpired.title")
            content.body  = loc("notification.authExpired.body")
        case .scrapeBroken:
            content.title = loc("notification.scrapeBroken.title")
            content.body  = loc("notification.scrapeBroken.body")
        }
        content.sound = .default
        return UNNotificationRequest(identifier: kind.rawValue + "-\(Int(Date().timeIntervalSince1970))",
                                      content: content, trigger: nil)
    }
}
