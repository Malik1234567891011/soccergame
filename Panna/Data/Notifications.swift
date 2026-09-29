import UserNotifications

/// Gentle, useful reminders only (free pack ready, new daily Moments). Asked after the first win, never on launch.
enum Reminders {
    static func requestIfNeeded() {
        let c = UNUserNotificationCenter.current()
        c.getNotificationSettings { s in
            guard s.authorizationStatus == .notDetermined else { return }
            c.requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in }
        }
    }

    static func schedule(freePackIn seconds: TimeInterval) {
        let c = UNUserNotificationCenter.current()
        c.removePendingNotificationRequests(withIdentifiers: ["freepack", "moments"])
        if seconds > 60 {
            let n = UNMutableNotificationContent()
            n.title = "Your free Scout Pack is ready"
            n.body = "A new Prospect could be waiting. Open it before your next match."
            n.sound = .default
            c.add(UNNotificationRequest(identifier: "freepack", content: n, trigger: UNTimeIntervalNotificationTrigger(timeInterval: seconds, repeats: false)))
        }
        // Tomorrow 6pm: new Moments.
        var comps = Calendar.current.dateComponents([.year, .month, .day], from: Date().addingTimeInterval(86400))
        comps.hour = 18
        let m = UNMutableNotificationContent()
        m.title = "New Daily Moments"
        m.body = "Three fresh scenarios. Last-minute winners don't score themselves."
        m.sound = .default
        c.add(UNNotificationRequest(identifier: "moments", content: m, trigger: UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)))
    }
}
