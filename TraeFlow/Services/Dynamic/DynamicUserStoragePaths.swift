import Foundation

/// 用户可直接查看和备份的“灵动岛”文件目录。
///
/// 账号凭据、AI 私密记忆和系统配置仍保留在 Application Support；这里只保存
/// 需求文档、随笔、录音、截图以及不含密钥的工作台索引。
enum DynamicUserStoragePaths {
    nonisolated static var rootURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Desktop", isDirectory: true)
            .appendingPathComponent("灵动岛", isDirectory: true)
    }

    nonisolated static var requirementsURL: URL {
        rootURL.appendingPathComponent("需求管理", isDirectory: true)
    }

    nonisolated static var notesURL: URL {
        rootURL.appendingPathComponent("随笔", isDirectory: true)
    }

    nonisolated static var recordingsURL: URL {
        rootURL.appendingPathComponent("快速录音", isDirectory: true)
    }

    nonisolated static var screenshotsURL: URL {
        rootURL.appendingPathComponent("截图", isDirectory: true)
    }

    nonisolated static var backupsURL: URL {
        rootURL.appendingPathComponent("备份", isDirectory: true)
    }

    nonisolated static var dataURL: URL {
        rootURL.appendingPathComponent("数据", isDirectory: true)
    }

    nonisolated static func prepareDirectories() throws {
        for directory in [
            rootURL,
            requirementsURL,
            notesURL,
            notesURL.appendingPathComponent("归档", isDirectory: true),
            recordingsURL,
            screenshotsURL,
            backupsURL,
            dataURL
        ] {
            try FileManager.default.createDirectory(
                at: directory,
                withIntermediateDirectories: true
            )
        }
    }

    nonisolated static func safeFileComponent(_ value: String, fallback: String) -> String {
        let invalidCharacters = CharacterSet(charactersIn: "/:\\?%*|\"<>")
            .union(.newlines)
            .union(.controlCharacters)
        let cleaned = value
            .components(separatedBy: invalidCharacters)
            .joined(separator: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned.isEmpty ? fallback : String(cleaned.prefix(64))
    }
}
