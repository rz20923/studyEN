import Foundation
import UserNotifications

/// 当天没达标时的提醒：晚上 8 点鼓励一次，10 点最后催一次。达标后取消当天的提醒。
enum Reminder {
    private static let slots: [(id: String, hour: Int, title: String, body: String)] = [
        ("checkin-20", 20, "今天还没达标", "每天的训练要练到达标才能打卡。现在花点时间，把今天拿下！"),
        ("checkin-22", 22, "今天的打卡还在等你", "离今天结束只剩两小时。错题复习完就能重考，练到达标再睡。"),
    ]

    static func refresh(checkedInToday: Bool) {
        let center = UNUserNotificationCenter.current()
        center.requestAuthorization(options: [.alert, .sound, .badge]) { granted, _ in
            guard granted else { return }
            center.removePendingNotificationRequests(withIdentifiers: slots.map(\.id))

            let cal = Calendar.current
            let now = Date.now
            for slot in slots {
                guard var date = cal.date(bySettingHour: slot.hour, minute: 0, second: 0, of: now) else { continue }
                // 今天已达标或时间已过，就提醒明天
                if checkedInToday || date <= now {
                    date = cal.date(byAdding: .day, value: 1, to: date) ?? date
                }
                let content = UNMutableNotificationContent()
                content.title = slot.title
                content.body = slot.body
                content.sound = .default
                let trigger = UNCalendarNotificationTrigger(
                    dateMatching: cal.dateComponents([.year, .month, .day, .hour, .minute], from: date),
                    repeats: false
                )
                center.add(UNNotificationRequest(identifier: slot.id, content: content, trigger: trigger))
            }
        }
    }
}
