import Combine
import Foundation

enum PersonalTaskStage: String, Codable, CaseIterable, Identifiable {
    case inbox
    case doing
    case waiting
    case done

    var id: String { rawValue }

    var title: String {
        switch self {
        case .inbox: return "待处理"
        case .doing: return "进行中"
        case .waiting: return "等待中"
        case .done: return "已完成"
        }
    }

    var systemImage: String {
        switch self {
        case .inbox: return "tray"
        case .doing: return "bolt.fill"
        case .waiting: return "clock.fill"
        case .done: return "checkmark.circle.fill"
        }
    }
}

enum PersonalTaskPriority: String, Codable, CaseIterable, Identifiable {
    case low
    case normal
    case high

    var id: String { rawValue }

    var title: String {
        switch self {
        case .low: return "低"
        case .normal: return "普通"
        case .high: return "高"
        }
    }
}

struct PersonalTask: Codable, Identifiable, Equatable {
    let id: String
    var title: String
    var detail: String
    var stage: PersonalTaskStage
    var priority: PersonalTaskPriority
    var dueDate: Date?
    var reminderID: String?
    let createdAt: Date
    var updatedAt: Date
}

struct PersonalNote: Codable, Identifiable, Equatable {
    let id: String
    var title: String
    var markdown: String
    var isArchived: Bool
    let createdAt: Date
    var updatedAt: Date
}

enum WorkspaceModule: String, Codable, CaseIterable, Identifiable {
    case taskBoard
    case aiSuggestion
    case requirements
    case quickRecording
    case music

    var id: String { rawValue }

    var title: String {
        switch self {
        case .taskBoard: return "四列待办"
        case .aiSuggestion: return "AI 今日建议"
        case .requirements: return "需求进度"
        case .quickRecording: return "快速录音"
        case .music: return "迷你音乐"
        }
    }
}

enum WorkspaceModuleSize: String, Codable, CaseIterable, Identifiable {
    case compact
    case regular
    case large

    var id: String { rawValue }

    var title: String {
        switch self {
        case .compact: return "紧凑"
        case .regular: return "标准"
        case .large: return "宽大"
        }
    }
}

struct WorkspaceModulePreference: Codable, Identifiable, Equatable {
    var id: WorkspaceModule { module }
    var module: WorkspaceModule
    var order: Int
    var size: WorkspaceModuleSize
    var isHidden: Bool
}

private struct PersonalWorkspaceSnapshot: Codable {
    var version: Int
    var tasks: [PersonalTask]
    var notes: [PersonalNote]
    var modulePreferences: [WorkspaceModulePreference]
}

/// “灵动岛”个人工作台的本地数据中心。
///
/// 工作台、随笔与备份保存在桌面“灵动岛”目录，方便用户查看和备份。
/// AI 密钥和私密数据仍保留在原 Bundle ID 的安全运行目录中。
@MainActor
final class DynamicPersonalWorkspaceStore: ObservableObject {
    static let shared = DynamicPersonalWorkspaceStore()

    @Published private(set) var tasks: [PersonalTask] = []
    @Published private(set) var notes: [PersonalNote] = []
    @Published private(set) var modulePreferences: [WorkspaceModulePreference] = []
    @Published private(set) var migrationMessage: String?

    private let migrationVersion = 1
    private let defaults = UserDefaults.standard

    private static var persistenceURL: URL {
        DynamicUserStoragePaths.dataURL.appendingPathComponent("personal-workspace.json")
    }

    private static var legacyPersistenceURL: URL {
        BridgeRuntimePaths.runtimeDirectoryURL.appendingPathComponent("personal-workspace.json")
    }

    private static var backupRootURL: URL {
        DynamicUserStoragePaths.backupsURL
    }

    private init() {
        load()
        ensureDefaultModulePreferences()
        migrateLegacyDataIfNeeded()
    }

    var visibleModulePreferences: [WorkspaceModulePreference] {
        modulePreferences.filter { !$0.isHidden }.sorted { $0.order < $1.order }
    }

    func tasks(in stage: PersonalTaskStage) -> [PersonalTask] {
        tasks
            .filter { $0.stage == stage }
            .sorted {
                switch ($0.dueDate, $1.dueDate) {
                case let (lhs?, rhs?): return lhs < rhs
                case (_?, nil): return true
                case (nil, _?): return false
                case (nil, nil): return $0.updatedAt > $1.updatedAt
                }
            }
    }

    @discardableResult
    func addTask(
        title: String,
        detail: String = "",
        stage: PersonalTaskStage = .inbox,
        priority: PersonalTaskPriority = .normal,
        dueDate: Date? = nil
    ) -> PersonalTask? {
        let cleaned = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { return nil }

        var reminderID: String?
        if let dueDate, dueDate > Date() {
            reminderID = DynamicReminderStore.shared.addReminder(
                title: cleaned,
                fireDate: dueDate
            )
        }

        let now = Date()
        let task = PersonalTask(
            id: UUID().uuidString,
            title: cleaned,
            detail: detail.trimmingCharacters(in: .whitespacesAndNewlines),
            stage: stage,
            priority: priority,
            dueDate: dueDate,
            reminderID: reminderID,
            createdAt: now,
            updatedAt: now
        )
        tasks.append(task)
        persist()
        return task
    }

    func moveTask(id: String, to stage: PersonalTaskStage) {
        guard let index = tasks.firstIndex(where: { $0.id == id }) else { return }
        tasks[index].stage = stage
        tasks[index].updatedAt = Date()
        if stage == .done, let reminderID = tasks[index].reminderID {
            DynamicReminderStore.shared.removeReminder(id: reminderID)
            tasks[index].reminderID = nil
        }
        persist()
    }

    func deleteTask(id: String) {
        guard let task = tasks.first(where: { $0.id == id }) else { return }
        if let reminderID = task.reminderID {
            DynamicReminderStore.shared.removeReminder(id: reminderID)
        }
        tasks.removeAll { $0.id == id }
        persist()
    }

    @discardableResult
    func addNote(markdown: String) -> PersonalNote? {
        let cleaned = markdown.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { return nil }
        let now = Date()
        let note = PersonalNote(
            id: UUID().uuidString,
            title: Self.smartTitle(from: cleaned),
            markdown: cleaned,
            isArchived: false,
            createdAt: now,
            updatedAt: now
        )
        notes.insert(note, at: 0)
        persist()
        persistNoteFile(note)
        return note
    }

    func updateNote(id: String, title: String, markdown: String) {
        guard let index = notes.firstIndex(where: { $0.id == id }) else { return }
        let cleanedMarkdown = markdown.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        notes[index].title = cleanedTitle.isEmpty ? Self.smartTitle(from: cleanedMarkdown) : cleanedTitle
        notes[index].markdown = cleanedMarkdown
        notes[index].updatedAt = Date()
        let note = notes[index]
        persist()
        persistNoteFile(note)
    }

    func toggleArchiveNote(id: String) {
        guard let index = notes.firstIndex(where: { $0.id == id }) else { return }
        notes[index].isArchived.toggle()
        notes[index].updatedAt = Date()
        let note = notes[index]
        persist()
        persistNoteFile(note)
    }

    func deleteNote(id: String) {
        notes.removeAll { $0.id == id }
        removeNoteFiles(id: id)
        persist()
    }

    func setModuleHidden(_ module: WorkspaceModule, hidden: Bool) {
        guard let index = modulePreferences.firstIndex(where: { $0.module == module }) else { return }
        modulePreferences[index].isHidden = hidden
        persist()
    }

    func setModuleSize(_ module: WorkspaceModule, size: WorkspaceModuleSize) {
        guard let index = modulePreferences.firstIndex(where: { $0.module == module }) else { return }
        modulePreferences[index].size = size
        persist()
    }

    func moveModule(_ source: WorkspaceModule, before destination: WorkspaceModule) {
        var ordered = modulePreferences.sorted { $0.order < $1.order }
        guard let sourceIndex = ordered.firstIndex(where: { $0.module == source }),
              let destinationIndex = ordered.firstIndex(where: { $0.module == destination }) else { return }
        let item = ordered.remove(at: sourceIndex)
        let adjustedDestination = sourceIndex < destinationIndex ? destinationIndex - 1 : destinationIndex
        ordered.insert(item, at: max(0, adjustedDestination))
        for index in ordered.indices { ordered[index].order = index }
        modulePreferences = ordered
        persist()
    }

    func resetModuleLayout() {
        modulePreferences = Self.defaultModulePreferences
        persist()
    }

    func createManualBackup() -> URL? {
        createBackup(reason: "manual")
    }

    var userStorageRootURL: URL {
        DynamicUserStoragePaths.rootURL
    }

    private func load() {
        try? DynamicUserStoragePaths.prepareDirectories()
        let sourceURL = FileManager.default.fileExists(atPath: Self.persistenceURL.path)
            ? Self.persistenceURL
            : Self.legacyPersistenceURL
        guard FileManager.default.fileExists(atPath: sourceURL.path),
              let data = try? Data(contentsOf: sourceURL),
              let snapshot = try? JSONDecoder().decode(PersonalWorkspaceSnapshot.self, from: data) else {
            return
        }
        tasks = snapshot.tasks
        notes = snapshot.notes
        modulePreferences = snapshot.modulePreferences
        if sourceURL == Self.legacyPersistenceURL {
            persist()
        }
        for note in notes {
            persistNoteFile(note)
        }
    }

    private func persist() {
        let snapshot = PersonalWorkspaceSnapshot(
            version: migrationVersion,
            tasks: tasks,
            notes: notes,
            modulePreferences: modulePreferences
        )
        do {
            try DynamicUserStoragePaths.prepareDirectories()
            try FileManager.default.createDirectory(
                at: Self.persistenceURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let data = try JSONEncoder().encode(snapshot)
            try data.write(to: Self.persistenceURL, options: [.atomic])
        } catch {
            NSLog("[DynamicPersonalWorkspaceStore] 保存失败: \(error.localizedDescription)")
        }
    }

    private func ensureDefaultModulePreferences() {
        let known = Set(modulePreferences.map(\.module))
        var changed = false
        for preference in Self.defaultModulePreferences where !known.contains(preference.module) {
            modulePreferences.append(preference)
            changed = true
        }
        if changed || modulePreferences.isEmpty {
            modulePreferences.sort { $0.order < $1.order }
            persist()
        }
    }

    private func migrateLegacyDataIfNeeded() {
        let key = "personalWorkspaceMigrationVersion"
        guard defaults.integer(forKey: key) < migrationVersion else { return }

        let backupURL = createBackup(reason: "before-v\(migrationVersion)-migration")
        if tasks.isEmpty {
            tasks = DynamicReminderStore.shared.reminders.map { reminder in
                PersonalTask(
                    id: UUID().uuidString,
                    title: reminder.title,
                    detail: "从原监控提醒迁移",
                    stage: .inbox,
                    priority: .normal,
                    dueDate: reminder.fireDate,
                    reminderID: reminder.id,
                    createdAt: reminder.createdAt,
                    updatedAt: reminder.createdAt
                )
            }
        }
        defaults.set(migrationVersion, forKey: key)
        migrationMessage = backupURL.map { "已保留旧数据备份：\($0.lastPathComponent)" }
        persist()
    }

    private func createBackup(reason: String) -> URL? {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        let folder = Self.backupRootURL.appendingPathComponent(
            "\(formatter.string(from: Date()))-\(reason)",
            isDirectory: true
        )

        do {
            try DynamicUserStoragePaths.prepareDirectories()
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let publicFiles = [
                Self.persistenceURL,
                DynamicUserStoragePaths.dataURL.appendingPathComponent("dynamic-requirements.json")
            ]
            for source in publicFiles where FileManager.default.fileExists(atPath: source.path) {
                let destination = folder.appendingPathComponent(source.lastPathComponent)
                try? FileManager.default.copyItem(at: source, to: destination)
            }

            if let reminderData = defaults.data(forKey: "dynamicSavedReminders") {
                try reminderData.write(
                    to: folder.appendingPathComponent("dynamic-reminders.json"),
                    options: [.atomic]
                )
            }
            return folder
        } catch {
            NSLog("[DynamicPersonalWorkspaceStore] 备份失败: \(error.localizedDescription)")
            return nil
        }
    }

    private func persistNoteFile(_ note: PersonalNote) {
        do {
            try DynamicUserStoragePaths.prepareDirectories()
            removeNoteFiles(id: note.id)
            let directory = note.isArchived
                ? DynamicUserStoragePaths.notesURL.appendingPathComponent("归档", isDirectory: true)
                : DynamicUserStoragePaths.notesURL
            let safeTitle = DynamicUserStoragePaths.safeFileComponent(note.title, fallback: "未命名随笔")
            let url = directory.appendingPathComponent("\(safeTitle)-\(note.id.prefix(8)).md")
            try note.markdown.write(to: url, atomically: true, encoding: .utf8)
        } catch {
            NSLog("[DynamicPersonalWorkspaceStore] 随笔文件保存失败: \(error.localizedDescription)")
        }
    }

    private func removeNoteFiles(id: String) {
        let suffix = "-\(id.prefix(8)).md"
        let directories = [
            DynamicUserStoragePaths.notesURL,
            DynamicUserStoragePaths.notesURL.appendingPathComponent("归档", isDirectory: true)
        ]
        for directory in directories {
            guard let urls = try? FileManager.default.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: nil
            ) else { continue }
            for url in urls where url.lastPathComponent.hasSuffix(suffix) {
                try? FileManager.default.removeItem(at: url)
            }
        }
    }

    private static func smartTitle(from markdown: String) -> String {
        let firstMeaningfulLine = markdown
            .split(whereSeparator: \Character.isNewline)
            .map(String.init)
            .map { line in
                line.trimmingCharacters(in: CharacterSet(charactersIn: "#*- `\t"))
            }
            .first(where: { !$0.isEmpty }) ?? "未命名随笔"
        return String(firstMeaningfulLine.prefix(28))
    }

    private static let defaultModulePreferences: [WorkspaceModulePreference] = [
        WorkspaceModulePreference(module: .taskBoard, order: 0, size: .large, isHidden: false),
        WorkspaceModulePreference(module: .aiSuggestion, order: 1, size: .regular, isHidden: false),
        WorkspaceModulePreference(module: .requirements, order: 2, size: .regular, isHidden: false),
        WorkspaceModulePreference(module: .quickRecording, order: 3, size: .compact, isHidden: false),
        WorkspaceModulePreference(module: .music, order: 4, size: .compact, isHidden: false)
    ]
}
