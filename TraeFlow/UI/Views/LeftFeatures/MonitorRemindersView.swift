import SwiftUI

struct MonitorRemindersView: View {
    @ObservedObject private var reminderStore = DynamicReminderStore.shared
    @State private var metrics = SystemMetricsProvider.shared.sample()
    @State private var newReminderTitle = ""
    @State private var newReminderDate = Date().addingTimeInterval(300)
    @State private var timer: Timer?

    var body: some View {
        HStack(spacing: 14) {
            monitorPanel
                .frame(maxWidth: .infinity)
            remindersPanel
                .frame(maxWidth: .infinity)
        }
        .padding(16)
        .background(dynamicBackground)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .onAppear {
            sampleMetrics()
            timer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { _ in
                Task { @MainActor in sampleMetrics() }
            }
        }
        .onDisappear {
            timer?.invalidate()
            timer = nil
        }
    }

    private var monitorPanel: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Label("本机实时监控", systemImage: "waveform.path.ecg")
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                Spacer()
                Circle().fill(Color.green).frame(width: 7, height: 7)
                Text("实时")
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(.secondary)
            }

            metricCard(title: "CPU", value: metrics.cpu, detail: "\(metrics.cores) 核心", color: .cyan)
            metricCard(
                title: "内存",
                value: metrics.memoryPercent,
                detail: "\(formattedBytes(metrics.memoryUsed)) / \(formattedBytes(metrics.memoryTotal))",
                color: .purple
            )

            VStack(alignment: .leading, spacing: 9) {
                Text("系统负载")
                    .font(.system(size: 11, weight: .medium))
                HStack {
                    loadValue("1 分钟", value: metrics.loadOne)
                    loadValue("5 分钟", value: metrics.loadFive)
                    loadValue("15 分钟", value: metrics.loadFifteen)
                }
            }
            .padding(13)
            .background(Color.white.opacity(0.035), in: RoundedRectangle(cornerRadius: 11))

            Spacer()
        }
        .padding(16)
        .background(panelBackground)
        .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
    }

    private var remindersPanel: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Label("提醒", systemImage: "bell.badge.fill")
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                Spacer()
                Button(reminderStore.notificationStatusText) {
                    reminderStore.requestNotificationPermission()
                }
                .buttonStyle(.plain)
                .font(.system(size: 9))
                .foregroundStyle(.cyan)
            }

            VStack(spacing: 10) {
                TextField("提醒内容，例如：检查服务器告警", text: $newReminderTitle)
                DatePicker("提醒时间", selection: $newReminderDate, in: Date()..., displayedComponents: [.date, .hourAndMinute])
                    .datePickerStyle(.compact)
                HStack {
                    Spacer()
                    Button("添加提醒") {
                        reminderStore.addReminder(title: newReminderTitle, fireDate: newReminderDate)
                        newReminderTitle = ""
                        newReminderDate = Date().addingTimeInterval(300)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.cyan)
                    .disabled(newReminderTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .padding(13)
            .background(Color.white.opacity(0.035), in: RoundedRectangle(cornerRadius: 11))

            if reminderStore.reminders.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "bell.slash")
                        .font(.system(size: 28, weight: .light))
                        .foregroundStyle(.cyan.opacity(0.7))
                    Text("暂无提醒")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 7) {
                        ForEach(reminderStore.reminders) { reminder in
                            reminderRow(reminder)
                        }
                    }
                }
            }
        }
        .padding(16)
        .background(panelBackground)
        .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
    }

    private func metricCard(title: String, value: Double, detail: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack {
                Text(title).font(.system(size: 11, weight: .medium))
                Spacer()
                Text(String(format: "%.1f%%", value))
                    .font(.system(size: 18, weight: .semibold, design: .rounded))
                    .foregroundStyle(color)
            }
            ProgressView(value: min(max(value, 0), 100), total: 100)
                .tint(color)
            Text(detail)
                .font(.system(size: 9, design: .monospaced))
                .foregroundStyle(.secondary)
        }
        .padding(13)
        .background(Color.white.opacity(0.035), in: RoundedRectangle(cornerRadius: 11))
    }

    private func loadValue(_ title: String, value: Double) -> some View {
        VStack(spacing: 4) {
            Text(String(format: "%.2f", value))
                .font(.system(size: 14, weight: .semibold, design: .monospaced))
                .foregroundStyle(.cyan)
            Text(title).font(.system(size: 8)).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    private func reminderRow(_ reminder: DynamicReminder) -> some View {
        HStack(spacing: 10) {
            Toggle("", isOn: Binding(
                get: { reminder.isEnabled },
                set: { reminderStore.toggle(reminder, isEnabled: $0) }
            ))
            .labelsHidden()
            VStack(alignment: .leading, spacing: 3) {
                Text(reminder.title)
                    .font(.system(size: 11, weight: .medium))
                    .lineLimit(2)
                Text(reminder.fireDate.formatted(date: .abbreviated, time: .shortened))
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(reminder.fireDate < Date() ? Color.orange : Color.secondary)
            }
            Spacer()
            Button {
                reminderStore.removeReminder(reminder)
            } label: {
                Image(systemName: "trash")
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
        }
        .padding(10)
        .background(Color.white.opacity(0.035), in: RoundedRectangle(cornerRadius: 9))
    }

    private func sampleMetrics() {
        metrics = SystemMetricsProvider.shared.sample()
    }

    private func formattedBytes(_ value: UInt64) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(value), countStyle: .memory)
    }

    private var dynamicBackground: some View {
        LinearGradient(
            colors: [Color(red: 0.02, green: 0.04, blue: 0.08), Color(red: 0.04, green: 0.07, blue: 0.13)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    private var panelBackground: some View {
        Color(red: 0.035, green: 0.065, blue: 0.115).opacity(0.94)
    }
}
