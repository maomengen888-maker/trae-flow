import Combine
import Foundation
import UserNotifications

struct DynamicReminder: Codable, Identifiable, Equatable {
    let id: String
    var title: String
    var fireDate: Date
    var isEnabled: Bool
    let createdAt: Date
}

@MainActor
final class DynamicReminderStore: ObservableObject {
    static let shared = DynamicReminderStore()

    @Published private(set) var reminders: [DynamicReminder] = []
    @Published private(set) var notificationStatusText = "提醒权限尚未开启"

    private let defaults = UserDefaults.standard
    private let storageKey = "dynamicSavedReminders"

    private init() {
        load()
        refreshAuthorizationStatus()
    }

    func addReminder(title: String, fireDate: Date) {
        let reminder = DynamicReminder(
            id: UUID().uuidString,
            title: title,
            fireDate: fireDate,
            isEnabled: true,
            createdAt: Date()
        )
        reminders.append(reminder)
        reminders.sort { $0.fireDate < $1.fireDate }
        persist()
        requestPermissionAndSchedule(reminder)
    }

    func removeReminder(_ reminder: DynamicReminder) {
        reminders.removeAll { $0.id == reminder.id }
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [reminder.id])
        persist()
    }

    func toggle(_ reminder: DynamicReminder, isEnabled: Bool) {
        guard let index = reminders.firstIndex(where: { $0.id == reminder.id }) else { return }
        reminders[index].isEnabled = isEnabled
        let updated = reminders[index]
        persist()
        if isEnabled {
            requestPermissionAndSchedule(updated)
        } else {
            UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [updated.id])
        }
    }

    func requestNotificationPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { [weak self] granted, _ in
            Task { @MainActor in
                self?.notificationStatusText = granted ? "系统提醒已开启" : "未获得系统提醒权限"
                if granted {
                    self?.rescheduleEnabledReminders()
                }
            }
        }
    }

    private func requestPermissionAndSchedule(_ reminder: DynamicReminder) {
        UNUserNotificationCenter.current().getNotificationSettings { [weak self] settings in
            guard settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional else {
                Task { @MainActor in self?.requestNotificationPermission() }
                return
            }
            self?.schedule(reminder)
        }
    }

    private nonisolated func schedule(_ reminder: DynamicReminder) {
        guard reminder.isEnabled, reminder.fireDate > Date() else { return }
        let content = UNMutableNotificationContent()
        content.title = "摸鱼岛监控提醒"
        content.body = reminder.title
        content.sound = .default
        let interval = max(1, reminder.fireDate.timeIntervalSinceNow)
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: interval, repeats: false)
        let request = UNNotificationRequest(identifier: reminder.id, content: content, trigger: trigger)
        UNUserNotificationCenter.current().add(request)
    }

    private func rescheduleEnabledReminders() {
        reminders.filter(\.isEnabled).forEach { schedule($0) }
    }

    private func refreshAuthorizationStatus() {
        UNUserNotificationCenter.current().getNotificationSettings { [weak self] settings in
            Task { @MainActor in
                switch settings.authorizationStatus {
                case .authorized, .provisional:
                    self?.notificationStatusText = "系统提醒已开启"
                case .denied:
                    self?.notificationStatusText = "系统提醒权限已关闭"
                default:
                    self?.notificationStatusText = "提醒权限尚未开启"
                }
            }
        }
    }

    private func load() {
        guard let data = defaults.data(forKey: storageKey),
              let saved = try? JSONDecoder().decode([DynamicReminder].self, from: data) else { return }
        reminders = saved.sorted { $0.fireDate < $1.fireDate }
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(reminders) else { return }
        defaults.set(data, forKey: storageKey)
    }
}
