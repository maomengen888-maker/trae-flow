import AppKit
import Combine
import CryptoKit
import Foundation
import LocalAuthentication
import PDFKit
import Security

enum DynamicAIChatMode: String, Codable, CaseIterable, Identifiable {
    case companion
    case review
    case advice
    case knowledge

    var id: String { rawValue }

    var title: String {
        switch self {
        case .companion: return "陪伴"
        case .review: return "复盘"
        case .advice: return "建议"
        case .knowledge: return "知识问答"
        }
    }

    var systemPrompt: String {
        switch self {
        case .companion:
            return "你是温暖、克制的陪伴助手。先回应感受并澄清需求，不制造依赖，不假装真人。"
        case .review:
            return "你是复盘助手。区分事实、解释、感受、经验和下一步，不急于归因。"
        case .advice:
            return "你是行动建议助手。先确认目标与限制，再提供少量可执行选项、风险和下一步。"
        case .knowledge:
            return "你是知识库问答助手。优先依据提供的资料回答，标注文档名；证据不足时明确说明。"
        }
    }
}

enum DynamicAIMemoryStatus: String, Codable {
    case candidate
    case confirmed
    case conflicted
}

struct DynamicAIMemorySource: Codable, Equatable {
    var kind: String
    var title: String
    var referenceID: String
    var createdAt: Date
}

struct DynamicAIMemory: Codable, Identifiable, Equatable {
    var id: String
    var content: String
    var category: String
    var confidence: Double
    var status: DynamicAIMemoryStatus
    var source: DynamicAIMemorySource
    var createdAt: Date
    var updatedAt: Date
}

struct DynamicAIMemoryCandidate: Equatable {
    var content: String
    var category: String
    var confidence: Double
}

enum DynamicAIMemoryExtractor {
    private static let stableSignals: [(String, String, Double)] = [
        ("我叫", "身份", 0.96),
        ("请叫我", "称呼", 0.96),
        ("我是一名", "职业身份", 0.96),
        ("我是一个", "职业身份", 0.96),
        ("我的职业是", "职业身份", 0.96),
        ("我从事", "职业身份", 0.94),
        ("我喜欢", "偏好", 0.90),
        ("我不喜欢", "偏好", 0.90),
        ("我的目标", "目标", 0.90),
        ("我计划", "计划", 0.82),
        ("我的生日", "重要日期", 0.95),
        ("记住", "用户指定", 0.98)
    ]

    static func candidates(from rawText: String) -> [DynamicAIMemoryCandidate] {
        let text = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard text.count >= 4 else { return [] }
        return stableSignals.compactMap { signal, category, confidence in
            guard text.localizedCaseInsensitiveContains(signal) else { return nil }
            return DynamicAIMemoryCandidate(
                content: String(text.prefix(240)),
                category: category,
                confidence: confidence
            )
        }
    }
}

enum DynamicAITextRanking {
    static func score(query: String, text: String) -> Int {
        let queryTokens = tokens(in: query)
        let textTokens = tokens(in: text)
        return queryTokens.reduce(0) { $0 + (textTokens.contains($1) ? 1 : 0) }
    }

    private static func tokens(in raw: String) -> Set<String> {
        let normalized = raw.lowercased()
        var result = Set(
            normalized
                .components(separatedBy: CharacterSet.alphanumerics.inverted)
                .filter { $0.count >= 2 }
        )
        let characters = Array(normalized.filter { !$0.isWhitespace && !$0.isPunctuation })
        guard characters.count >= 2 else { return result }
        for index in 0..<(characters.count - 1) {
            result.insert(String(characters[index...index + 1]))
        }
        return result
    }
}

@MainActor
final class DynamicAIMemoryStore: ObservableObject {
    static let shared = DynamicAIMemoryStore()

    @Published private(set) var memories: [DynamicAIMemory] = []
    @Published private(set) var blockedRules: [String] = []

    private let rootURL: URL

    private init(rootURL: URL = BridgeRuntimePaths.runtimeDirectoryURL.appendingPathComponent("companion", isDirectory: true)) {
        self.rootURL = rootURL
        load()
    }

    var pendingCount: Int { memories.filter { $0.status != .confirmed }.count }

    func propose(from text: String, sourceMessageID: String) {
        guard !isBlocked(text) else { return }
        for candidate in DynamicAIMemoryExtractor.candidates(from: text) {
            guard !memories.contains(where: { $0.content == candidate.content }) else { continue }
            let conflict = memories.contains {
                $0.category == candidate.category && $0.status == .confirmed && $0.content != candidate.content
            }
            let now = Date()
            memories.insert(
                DynamicAIMemory(
                    id: UUID().uuidString,
                    content: candidate.content,
                    category: candidate.category,
                    confidence: candidate.confidence,
                    status: conflict ? .conflicted : (candidate.confidence >= 0.94 ? .confirmed : .candidate),
                    source: DynamicAIMemorySource(
                        kind: "conversation",
                        title: "用户消息",
                        referenceID: sourceMessageID,
                        createdAt: now
                    ),
                    createdAt: now,
                    updatedAt: now
                ),
                at: 0
            )
        }
        persist()
    }

    func confirm(_ id: String) {
        update(id) { $0.status = .confirmed }
    }

    func updateContent(_ id: String, content: String) {
        update(id) {
            $0.content = String(content.trimmingCharacters(in: .whitespacesAndNewlines).prefix(500))
            $0.status = .confirmed
        }
    }

    func delete(_ id: String) {
        memories.removeAll { $0.id == id }
        persist()
    }

    func addBlockedRule(_ raw: String) {
        let rule = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !rule.isEmpty, !blockedRules.contains(rule) else { return }
        blockedRules.append(rule)
        persist()
    }

    func deleteBlockedRule(_ rule: String) {
        blockedRules.removeAll { $0 == rule }
        persist()
    }

    func context(for query: String, limit: Int = 5) -> [DynamicAIMemory] {
        memories
            .filter { $0.status == .confirmed && !isBlocked($0.content) }
            .map { ($0, DynamicAITextRanking.score(query: query, text: $0.content)) }
            .sorted { lhs, rhs in
                if lhs.1 == rhs.1 { return lhs.0.updatedAt > rhs.0.updatedAt }
                return lhs.1 > rhs.1
            }
            .prefix(limit)
            .map(\.0)
    }

    private func update(_ id: String, mutation: (inout DynamicAIMemory) -> Void) {
        guard let index = memories.firstIndex(where: { $0.id == id }) else { return }
        mutation(&memories[index])
        memories[index].updatedAt = Date()
        persist()
    }

    private func isBlocked(_ text: String) -> Bool {
        blockedRules.contains { text.localizedCaseInsensitiveContains($0) }
    }

    private func load() {
        memories = Self.decode([DynamicAIMemory].self, from: rootURL.appendingPathComponent("memories.json")) ?? []
        blockedRules = Self.decode([String].self, from: rootURL.appendingPathComponent("blocked-memory-rules.json")) ?? []
    }

    private func persist() {
        Self.write(memories, to: rootURL.appendingPathComponent("memories.json"))
        Self.write(blockedRules, to: rootURL.appendingPathComponent("blocked-memory-rules.json"))
    }

    private static func decode<Value: Decodable>(_ type: Value.Type, from url: URL) -> Value? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }

    fileprivate static func write<Value: Encodable>(_ value: Value, to url: URL) {
        do {
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o700]
            )
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(value).write(to: url, options: .atomic)
        } catch {
            NSLog("[DynamicAI] 本地数据写入失败: \(error.localizedDescription)")
        }
    }
}

enum DynamicAIKnowledgeStatus: String, Codable {
    case ready
    case metadataOnly
    case failed
}

struct DynamicAIKnowledgeDocument: Codable, Identifiable, Equatable {
    var id: String
    var name: String
    var localPath: String
    var fileSize: Int64
    var importedAt: Date
    var status: DynamicAIKnowledgeStatus
    var content: String
    var errorMessage: String?
}

struct DynamicAIKnowledgeMatch: Identifiable {
    var id: String { document.id }
    var document: DynamicAIKnowledgeDocument
    var snippet: String
    var score: Int
}

@MainActor
final class DynamicAIKnowledgeStore: ObservableObject {
    static let shared = DynamicAIKnowledgeStore()

    @Published private(set) var documents: [DynamicAIKnowledgeDocument] = []
    @Published private(set) var isImporting = false
    @Published private(set) var errorMessage: String?

    private let rootURL = BridgeRuntimePaths.runtimeDirectoryURL
        .appendingPathComponent("companion/knowledge", isDirectory: true)

    private init() { load() }

    func importFiles(_ urls: [URL]) async {
        guard !urls.isEmpty else { return }
        isImporting = true
        errorMessage = nil
        defer { isImporting = false }

        for sourceURL in urls {
            let granted = sourceURL.startAccessingSecurityScopedResource()
            defer { if granted { sourceURL.stopAccessingSecurityScopedResource() } }
            do {
                let values = try sourceURL.resourceValues(forKeys: [.fileSizeKey, .nameKey])
                guard (values.fileSize ?? 0) <= 50 * 1024 * 1024 else {
                    throw KnowledgeError.fileTooLarge
                }
                let id = UUID().uuidString
                let directory = rootURL.appendingPathComponent(id, isDirectory: true)
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                let destination = directory.appendingPathComponent(sourceURL.lastPathComponent)
                try FileManager.default.copyItem(at: sourceURL, to: destination)

                let extraction = Self.extractText(from: destination)
                documents.insert(
                    DynamicAIKnowledgeDocument(
                        id: id,
                        name: values.name ?? sourceURL.lastPathComponent,
                        localPath: destination.path,
                        fileSize: Int64(values.fileSize ?? 0),
                        importedAt: Date(),
                        status: extraction.text.isEmpty ? .metadataOnly : .ready,
                        content: String(extraction.text.prefix(300_000)),
                        errorMessage: extraction.error
                    ),
                    at: 0
                )
            } catch {
                errorMessage = "导入失败：\(error.localizedDescription)"
            }
        }
        persist()
    }

    func delete(_ id: String) {
        guard let document = documents.first(where: { $0.id == id }) else { return }
        let directory = URL(fileURLWithPath: document.localPath).deletingLastPathComponent()
        try? FileManager.default.removeItem(at: directory)
        documents.removeAll { $0.id == id }
        persist()
    }

    func matches(for query: String, limit: Int = 3) -> [DynamicAIKnowledgeMatch] {
        documents
            .filter { $0.status == .ready && !$0.content.isEmpty }
            .map { document in
                let score = DynamicAITextRanking.score(query: query, text: document.name + " " + document.content)
                return DynamicAIKnowledgeMatch(
                    document: document,
                    snippet: Self.snippet(in: document.content, query: query),
                    score: score
                )
            }
            .filter { $0.score > 0 || documents.count <= limit }
            .sorted { $0.score > $1.score }
            .prefix(limit)
            .map { $0 }
    }

    private func load() {
        let indexURL = rootURL.appendingPathComponent("index.json")
        guard let data = try? Data(contentsOf: indexURL),
              let decoded = try? JSONDecoder().decode([DynamicAIKnowledgeDocument].self, from: data) else { return }
        documents = decoded.filter { FileManager.default.fileExists(atPath: $0.localPath) }
    }

    private func persist() {
        DynamicAIMemoryStore.write(documents, to: rootURL.appendingPathComponent("index.json"))
    }

    private static func extractText(from url: URL) -> (text: String, error: String?) {
        if url.pathExtension.lowercased() == "pdf", let pdf = PDFDocument(url: url) {
            let text = (0..<pdf.pageCount).compactMap { pdf.page(at: $0)?.string }.joined(separator: "\n")
            return (text, text.isEmpty ? "PDF 没有可提取文本，可能是扫描件" : nil)
        }
        if let text = try? String(contentsOf: url, encoding: .utf8) { return (text, nil) }
        if let richText = try? NSAttributedString(url: url, options: [:], documentAttributes: nil) {
            return (richText.string, nil)
        }
        return ("", "当前文件只能保存名称和原文件，暂时不能建立文本索引")
    }

    private static func snippet(in content: String, query: String) -> String {
        let normalized = content.replacingOccurrences(of: "\n", with: " ")
        if let range = normalized.range(of: query, options: .caseInsensitive) {
            let start = normalized.index(range.lowerBound, offsetBy: -80, limitedBy: normalized.startIndex) ?? normalized.startIndex
            let end = normalized.index(range.upperBound, offsetBy: 180, limitedBy: normalized.endIndex) ?? normalized.endIndex
            return String(normalized[start..<end])
        }
        return String(normalized.prefix(280))
    }

    private enum KnowledgeError: LocalizedError {
        case fileTooLarge
        var errorDescription: String? { "单个文件不能超过 50MB" }
    }
}

struct DynamicAICallAudit: Codable, Identifiable, Equatable {
    var id: String
    var conversationID: String?
    var provider: String
    var model: String
    var startedAt: Date
    var duration: Double
    var outcome: String
    var estimatedInputCharacters: Int
}

@MainActor
final class DynamicAIAuditStore: ObservableObject {
    static let shared = DynamicAIAuditStore()
    @Published private(set) var records: [DynamicAICallAudit] = []

    private let url = BridgeRuntimePaths.runtimeDirectoryURL
        .appendingPathComponent("companion/model-call-audit.json")

    private init() {
        guard let data = try? Data(contentsOf: url),
              let decoded = try? JSONDecoder().decode([DynamicAICallAudit].self, from: data) else { return }
        records = decoded
    }

    func record(
        conversationID: String?,
        provider: String,
        model: String,
        startedAt: Date,
        outcome: String,
        inputCharacters: Int
    ) {
        records.insert(
            DynamicAICallAudit(
                id: UUID().uuidString,
                conversationID: conversationID,
                provider: provider,
                model: model,
                startedAt: startedAt,
                duration: Date().timeIntervalSince(startedAt),
                outcome: outcome,
                estimatedInputCharacters: inputCharacters
            ),
            at: 0
        )
        if records.count > 500 { records = Array(records.prefix(500)) }
        DynamicAIMemoryStore.write(records, to: url)
    }
}

enum DynamicAISafetyRouter {
    private static let highRiskTerms = [
        "我想自杀", "不想活了", "结束生命", "伤害自己", "杀了自己", "杀了他", "杀了她",
        "正在被虐待", "被家暴", "严重服药过量", "无法呼吸"
    ]

    static func response(for text: String) -> String? {
        guard highRiskTerms.contains(where: { text.localizedCaseInsensitiveContains($0) }) else { return nil }
        return "我很在意你现在的安全。请先离开可能伤害你的物品或环境，并尽快联系身边可信任的人。如果你或他人正面临立即危险，请拨打 110 或 120。你愿意告诉我：你现在是否处在立即危险中、身边有没有可以联系的人？"
    }
}

struct DynamicAIPrivateItem: Codable, Identifiable, Equatable {
    var id: String
    var title: String
    var content: String
    var createdAt: Date
    var updatedAt: Date
}

@MainActor
final class DynamicAIPrivateVaultStore: ObservableObject {
    static let shared = DynamicAIPrivateVaultStore()

    @Published private(set) var isUnlocked = false
    @Published private(set) var items: [DynamicAIPrivateItem] = []
    @Published private(set) var errorMessage: String?

    private let encryptedURL = BridgeRuntimePaths.runtimeDirectoryURL
        .appendingPathComponent("companion/private-vault.sealed")
    private let keychainService = "ai.dynamic.app.private-vault"
    private let keychainAccount = "vault-encryption-key"

    private init() {}

    var biometryLabel: String {
        let context = LAContext()
        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error) else {
            return "Touch ID 不可用"
        }
        return context.biometryType == .touchID ? "使用 Touch ID 解锁" : "使用生物识别解锁"
    }

    func unlock() async {
        errorMessage = nil
        let context = LAContext()
        context.localizedCancelTitle = "取消"
        var policyError: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &policyError) else {
            errorMessage = policyError?.localizedDescription ?? "当前设备没有可用的 Touch ID"
            return
        }
        do {
            let allowed = try await context.evaluatePolicy(
                .deviceOwnerAuthenticationWithBiometrics,
                localizedReason: "解锁灵动岛隐私空间"
            )
            guard allowed else { return }
            items = try loadItems()
            isUnlocked = true
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func lock() {
        items = []
        isUnlocked = false
    }

    func add(title: String, content: String) {
        guard isUnlocked else { return }
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedContent = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTitle.isEmpty || !trimmedContent.isEmpty else { return }
        let now = Date()
        items.insert(
            DynamicAIPrivateItem(
                id: UUID().uuidString,
                title: trimmedTitle.isEmpty ? "私密记录" : trimmedTitle,
                content: trimmedContent,
                createdAt: now,
                updatedAt: now
            ),
            at: 0
        )
        persist()
    }

    func delete(_ id: String) {
        guard isUnlocked else { return }
        items.removeAll { $0.id == id }
        persist()
    }

    private func loadItems() throws -> [DynamicAIPrivateItem] {
        guard FileManager.default.fileExists(atPath: encryptedURL.path) else { return [] }
        let sealedData = try Data(contentsOf: encryptedURL)
        let box = try AES.GCM.SealedBox(combined: sealedData)
        let plaintext = try AES.GCM.open(box, using: try encryptionKey())
        return try JSONDecoder().decode([DynamicAIPrivateItem].self, from: plaintext)
    }

    private func persist() {
        do {
            let data = try JSONEncoder().encode(items)
            let sealed = try AES.GCM.seal(data, using: try encryptionKey())
            guard let combined = sealed.combined else { throw VaultError.encryptionFailed }
            try FileManager.default.createDirectory(
                at: encryptedURL.deletingLastPathComponent(),
                withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o700]
            )
            try combined.write(to: encryptedURL, options: .atomic)
        } catch {
            errorMessage = "隐私空间保存失败：\(error.localizedDescription)"
        }
    }

    private func encryptionKey() throws -> SymmetricKey {
        if let existing = readKeychainValue() { return SymmetricKey(data: existing) }
        var bytes = [UInt8](repeating: 0, count: 32)
        guard SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) == errSecSuccess else {
            throw VaultError.keyGenerationFailed
        }
        let data = Data(bytes)
        let status = SecItemAdd([
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: keychainAccount,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
            kSecValueData as String: data
        ] as CFDictionary, nil)
        guard status == errSecSuccess || status == errSecDuplicateItem else {
            throw VaultError.keychain(status)
        }
        return SymmetricKey(data: readKeychainValue() ?? data)
    }

    private func readKeychainValue() -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: keychainAccount,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
            kSecUseAuthenticationUI as String: kSecUseAuthenticationUIFail
        ]
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess else { return nil }
        return result as? Data
    }

    private enum VaultError: LocalizedError {
        case encryptionFailed
        case keyGenerationFailed
        case keychain(OSStatus)

        var errorDescription: String? {
            switch self {
            case .encryptionFailed: return "无法生成加密数据"
            case .keyGenerationFailed: return "无法生成加密密钥"
            case .keychain(let status): return "钥匙串写入失败（\(status)）"
            }
        }
    }
}

enum DynamicAIContextBuilder {
    static func build(
        mode: DynamicAIChatMode,
        query: String,
        memories: [DynamicAIMemory],
        knowledge: [DynamicAIKnowledgeMatch],
        blockedRules: [String]
    ) -> String {
        var sections = [mode.systemPrompt]
        if !blockedRules.isEmpty {
            sections.append("禁止记忆或复述的内容规则：\(blockedRules.joined(separator: "、"))")
        }
        if !memories.isEmpty {
            sections.append("可用的已确认记忆（只在相关时使用）：\n" + memories.map {
                "- [\($0.category)] \($0.content)（来源：\($0.source.title)）"
            }.joined(separator: "\n"))
        }
        if !knowledge.isEmpty {
            sections.append("本轮检索到的资料：\n" + knowledge.map {
                "- 文档《\($0.document.name)》：\($0.snippet)"
            }.joined(separator: "\n"))
        }
        sections.append("用户当前问题：\(query)")
        return sections.joined(separator: "\n\n")
    }
}
