import Combine
import Foundation
import LocalAuthentication
import Security

enum DynamicAIProvider: String, Codable, CaseIterable, Identifiable {
    case dify
    case deepSeek
    case openAI
    case compatible

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .dify: return "Dify Agent"
        case .deepSeek: return "DeepSeek"
        case .openAI: return "OpenAI"
        case .compatible: return "OpenAI 兼容服务"
        }
    }

    var defaultBaseURL: String {
        switch self {
        case .dify: return "https://api.dify.ai/v1"
        case .deepSeek: return "https://api.deepseek.com"
        case .openAI: return "https://api.openai.com/v1"
        case .compatible: return ""
        }
    }

    var defaultModel: String {
        switch self {
        case .dify: return ""
        case .deepSeek: return "deepseek-v4-flash"
        case .openAI: return "gpt-5.2"
        case .compatible: return ""
        }
    }

    var requiresModel: Bool { self != .dify }

    static func inferred(from baseURLString: String) -> DynamicAIProvider {
        let host = URL(string: baseURLString)?.host?.lowercased() ?? baseURLString.lowercased()
        if host.contains("deepseek.com") { return .deepSeek }
        if host.contains("openai.com") { return .openAI }
        if host.contains("dify.ai") { return .dify }
        return .compatible
    }
}

struct DynamicAIConversation: Codable, Identifiable, Equatable {
    let id: String
    let name: String
    let createdAt: Date
    let updatedAt: Date

    init(id: String, name: String, createdAt: Date, updatedAt: Date) {
        self.id = id
        self.name = name
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    private enum CodingKeys: String, CodingKey {
        case id, name
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        name = try container.decodeIfPresent(String.self, forKey: .name) ?? "新对话"
        createdAt = Date(timeIntervalSince1970: try container.decodeIfPresent(Double.self, forKey: .createdAt) ?? 0)
        updatedAt = Date(timeIntervalSince1970: try container.decodeIfPresent(Double.self, forKey: .updatedAt) ?? 0)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(createdAt.timeIntervalSince1970, forKey: .createdAt)
        try container.encode(updatedAt.timeIntervalSince1970, forKey: .updatedAt)
    }
}

struct DynamicAIChatMessage: Identifiable, Equatable, Codable {
    enum Role: String, Codable { case user, assistant }
    let id: String
    let role: Role
    var text: String
    let createdAt: Date
    var isStreaming: Bool
}

struct DynamicDifyStreamEvent: Decodable {
    let event: String
    let answer: String?
    let thought: String?
    let tool: String?
    let conversationID: String?
    let message: String?

    private enum CodingKeys: String, CodingKey {
        case event, answer, thought, tool, message
        case conversationID = "conversation_id"
    }
}

struct DynamicOpenAIStreamChunk: Decodable {
    struct Choice: Decodable {
        struct Delta: Decodable {
            let content: String?
            let reasoningContent: String?

            private enum CodingKeys: String, CodingKey {
                case content
                case reasoningContent = "reasoning_content"
            }
        }
        let delta: Delta
    }

    let choices: [Choice]
}

@MainActor
final class DynamicDifyChatStore: ObservableObject {
    static let shared = DynamicDifyChatStore()

    @Published private(set) var conversations: [DynamicAIConversation] = []
    @Published private(set) var messages: [DynamicAIChatMessage] = []
    @Published private(set) var isLoadingConversations = false
    @Published private(set) var isLoadingMessages = false
    @Published private(set) var isSending = false
    @Published private(set) var activityText: String?
    @Published private(set) var errorMessage: String?
    @Published private(set) var isAPIKeyConfigured: Bool
    @Published private(set) var currentProvider: DynamicAIProvider
    @Published private(set) var modelName: String
    @Published var selectedConversationID: String?
    @Published var apiBaseURLString: String

    private enum DefaultsKey {
        static let provider = "dynamic.ai.provider"
        static let apiBaseURL = "dynamic.ai.apiBaseURL"
        static let model = "dynamic.ai.model"
        static let legacyAPIBaseURL = "dynamic.dify.apiBaseURL"
        static let endUserID = "dynamic.dify.endUserID"
    }

    private let defaults: UserDefaults
    private let credentialStore: DynamicDifyCredentialStore
    private let endUserID: String
    private var hasLoadedInitialData = false
    private var sendTask: Task<Void, Never>?

    private var localConversationsURL: URL {
        BridgeRuntimePaths.runtimeDirectoryURL.appendingPathComponent("dynamic-ai-conversations.json")
    }

    private init() {
        let defaults = UserDefaults.standard
        let credentialStore = DynamicDifyCredentialStore.shared
        self.defaults = defaults
        self.credentialStore = credentialStore

        let savedURL = defaults.string(forKey: DefaultsKey.apiBaseURL)
            ?? defaults.string(forKey: DefaultsKey.legacyAPIBaseURL)
            ?? DynamicAIProvider.dify.defaultBaseURL
        let provider = defaults.string(forKey: DefaultsKey.provider)
            .flatMap(DynamicAIProvider.init(rawValue:))
            ?? DynamicAIProvider.inferred(from: savedURL)

        let savedModel = defaults.string(forKey: DefaultsKey.model) ?? provider.defaultModel
        currentProvider = provider
        apiBaseURLString = savedURL
        modelName = savedModel

        if credentialStore.readAPIKey(for: provider) == nil,
           let legacyKey = credentialStore.readLegacyAPIKey() {
            try? credentialStore.saveAPIKey(legacyKey, for: provider)
        }
        isAPIKeyConfigured = credentialStore.readAPIKey(for: provider) != nil

        defaults.set(provider.rawValue, forKey: DefaultsKey.provider)
        defaults.set(savedURL, forKey: DefaultsKey.apiBaseURL)
        defaults.set(savedModel, forKey: DefaultsKey.model)

        if let existingID = defaults.string(forKey: DefaultsKey.endUserID) {
            endUserID = existingID
        } else {
            let newID = "dynamic-mac-\(UUID().uuidString.lowercased())"
            defaults.set(newID, forKey: DefaultsKey.endUserID)
            endUserID = newID
        }
    }

    deinit { sendTask?.cancel() }

    var selectedConversationName: String {
        guard let selectedConversationID else { return "新对话" }
        return conversations.first(where: { $0.id == selectedConversationID })?.name ?? "对话"
    }

    var providerDisplayName: String { currentProvider.displayName }

    var serviceDescription: String {
        currentProvider == .dify ? "Dify Agent 工作流" : "\(currentProvider.displayName) · \(modelName)"
    }

    func hasSavedAPIKey(for provider: DynamicAIProvider) -> Bool {
        credentialStore.readAPIKey(for: provider) != nil
    }

    func connectIfNeeded() {
        guard isAPIKeyConfigured, !hasLoadedInitialData else { return }
        hasLoadedInitialData = true
        Task { await refreshConversations() }
    }

    @discardableResult
    func saveConfiguration(
        provider: DynamicAIProvider,
        apiKey: String,
        baseURLString: String,
        modelName: String
    ) async -> Bool {
        let trimmedURL = baseURLString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let baseURL = URL(string: trimmedURL),
              let scheme = baseURL.scheme?.lowercased(),
              ["http", "https"].contains(scheme), baseURL.host != nil else {
            errorMessage = "API 地址无效，请填写完整的 http 或 https 地址"
            return false
        }

        let trimmedModel = modelName.trimmingCharacters(in: .whitespacesAndNewlines)
        if provider.requiresModel && trimmedModel.isEmpty {
            errorMessage = "请填写模型名称"
            return false
        }

        let trimmedKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedKey.isEmpty {
            do { try credentialStore.saveAPIKey(trimmedKey, for: provider) }
            catch {
                errorMessage = "API Key 保存失败：\(error.localizedDescription)"
                return false
            }
        } else if credentialStore.readAPIKey(for: provider) == nil {
            errorMessage = provider == .dify ? "请填写 Dify App API Key" : "请填写 API Key"
            return false
        }

        sendTask?.cancel()
        currentProvider = provider
        apiBaseURLString = trimmedURL.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        self.modelName = trimmedModel
        defaults.set(provider.rawValue, forKey: DefaultsKey.provider)
        defaults.set(apiBaseURLString, forKey: DefaultsKey.apiBaseURL)
        defaults.set(trimmedModel, forKey: DefaultsKey.model)
        isAPIKeyConfigured = true
        selectedConversationID = nil
        conversations = []
        messages = []
        errorMessage = nil
        hasLoadedInitialData = true
        await refreshConversations()
        return errorMessage == nil
    }

    func removeConfiguration() {
        sendTask?.cancel()
        credentialStore.deleteAPIKey(for: currentProvider)
        conversations = []
        messages = []
        selectedConversationID = nil
        isAPIKeyConfigured = false
        hasLoadedInitialData = false
        activityText = nil
        errorMessage = nil
    }

    func startNewConversation() {
        guard !isSending else { return }
        selectedConversationID = nil
        messages = []
        activityText = nil
        errorMessage = nil
    }

    func selectConversation(_ id: String) {
        guard !isSending, selectedConversationID != id else { return }
        selectedConversationID = id
        messages = []
        activityText = nil
        errorMessage = nil
        Task { await loadMessages(conversationID: id) }
    }

    func refreshConversations() async {
        guard let configuration = configuration() else { return }
        isLoadingConversations = true
        defer { isLoadingConversations = false }

        if configuration.provider != .dify {
            conversations = loadLocalConversations()
                .filter { $0.provider == configuration.provider }
                .map(\.conversation)
                .sorted { $0.updatedAt > $1.updatedAt }
            errorMessage = nil
            return
        }

        do {
            var components = URLComponents(url: configuration.baseURL.appendingPathComponent("conversations"), resolvingAgainstBaseURL: false)
            components?.queryItems = [
                URLQueryItem(name: "user", value: endUserID),
                URLQueryItem(name: "limit", value: "100"),
                URLQueryItem(name: "sort_by", value: "-updated_at")
            ]
            guard let url = components?.url else { throw DynamicAIError.invalidURL }
            let response: ConversationListResponse = try await requestJSON(url: url, configuration: configuration)
            conversations = response.data
            errorMessage = nil
        } catch { errorMessage = userFacingError(error) }
    }

    func loadMessages(conversationID: String) async {
        guard let configuration = configuration() else { return }
        isLoadingMessages = true
        defer { isLoadingMessages = false }

        if configuration.provider != .dify {
            messages = loadLocalConversations().first(where: { $0.conversation.id == conversationID })?.messages ?? []
            errorMessage = nil
            return
        }

        do {
            var components = URLComponents(url: configuration.baseURL.appendingPathComponent("messages"), resolvingAgainstBaseURL: false)
            components?.queryItems = [
                URLQueryItem(name: "conversation_id", value: conversationID),
                URLQueryItem(name: "user", value: endUserID),
                URLQueryItem(name: "limit", value: "100")
            ]
            guard let url = components?.url else { throw DynamicAIError.invalidURL }
            let response: MessageListResponse = try await requestJSON(url: url, configuration: configuration)
            messages = response.data.sorted { $0.createdAt < $1.createdAt }.flatMap { item in
                [
                    DynamicAIChatMessage(id: "\(item.id)-user", role: .user, text: item.query, createdAt: item.createdAt, isStreaming: false),
                    DynamicAIChatMessage(id: "\(item.id)-assistant", role: .assistant, text: item.answer, createdAt: item.createdAt.addingTimeInterval(0.001), isStreaming: false)
                ]
            }.filter { !$0.text.isEmpty }
            errorMessage = nil
        } catch { errorMessage = userFacingError(error) }
    }

    func send(_ rawText: String) {
        let text = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !isSending, let configuration = configuration() else { return }

        if configuration.provider != .dify, selectedConversationID == nil {
            selectedConversationID = UUID().uuidString
        }

        let assistantMessageID = UUID().uuidString
        messages.append(DynamicAIChatMessage(id: UUID().uuidString, role: .user, text: text, createdAt: Date(), isStreaming: false))
        messages.append(DynamicAIChatMessage(id: assistantMessageID, role: .assistant, text: "", createdAt: Date(), isStreaming: true))
        if configuration.provider != .dify { persistCurrentLocalConversation(configuration: configuration) }

        isSending = true
        activityText = "正在思考…"
        errorMessage = nil
        let conversationID = selectedConversationID ?? ""

        sendTask = Task { [weak self] in
            guard let self else { return }
            do {
                if configuration.provider == .dify {
                    try await self.streamDifyMessage(text, conversationID: conversationID, assistantMessageID: assistantMessageID, configuration: configuration)
                } else {
                    try await self.streamCompatibleMessage(assistantMessageID: assistantMessageID, configuration: configuration)
                }
                self.finishStreamingMessage(id: assistantMessageID)
                if configuration.provider != .dify { self.persistCurrentLocalConversation(configuration: configuration) }
                self.activityText = nil
                self.isSending = false
                await self.refreshConversations()
            } catch is CancellationError {
                self.finishStreamingMessage(id: assistantMessageID)
                if configuration.provider != .dify { self.persistCurrentLocalConversation(configuration: configuration) }
                self.activityText = nil
                self.isSending = false
            } catch {
                self.finishStreamingMessage(id: assistantMessageID)
                if configuration.provider != .dify { self.persistCurrentLocalConversation(configuration: configuration) }
                self.activityText = nil
                self.isSending = false
                self.errorMessage = self.userFacingError(error)
            }
        }
    }

    func stopGenerating() {
        sendTask?.cancel()
        sendTask = nil
    }

    private func streamDifyMessage(
        _ text: String,
        conversationID: String,
        assistantMessageID: String,
        configuration: Configuration
    ) async throws {
        var request = authorizedRequest(url: configuration.baseURL.appendingPathComponent("chat-messages"), configuration: configuration)
        request.httpMethod = "POST"
        request.timeoutInterval = 300
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "inputs": [:], "query": text, "response_mode": "streaming",
            "conversation_id": conversationID, "user": endUserID,
            "files": [], "auto_generate_name": true
        ])

        let (bytes, response) = try await URLSession.shared.bytes(for: request)
        if let httpResponse = response as? HTTPURLResponse, !(200..<300 ~= httpResponse.statusCode) {
            var errorBody = Data()
            for try await byte in bytes { errorBody.append(byte) }
            try validate(response: response, body: errorBody, provider: configuration.provider)
        }
        try validate(response: response, body: nil, provider: configuration.provider)
        var receivedAgentMessage = false
        for try await line in bytes.lines {
            try Task.checkCancellation()
            guard line.hasPrefix("data: "), let data = String(line.dropFirst(6)).data(using: .utf8) else { continue }
            let event = try JSONDecoder().decode(DynamicDifyStreamEvent.self, from: data)
            if let id = event.conversationID, !id.isEmpty { selectedConversationID = id }
            switch event.event {
            case "agent_thought":
                if let tool = event.tool, !tool.isEmpty { activityText = "正在使用 \(tool)…" }
                else if let thought = event.thought, !thought.isEmpty { activityText = thought.count > 60 ? "正在思考…" : thought }
            case "agent_message":
                receivedAgentMessage = true
                appendAnswer(event.answer ?? "", to: assistantMessageID)
                activityText = "正在回答…"
            case "message":
                if receivedAgentMessage { replaceAnswerIfMoreComplete(event.answer ?? "", in: assistantMessageID) }
                else { appendAnswer(event.answer ?? "", to: assistantMessageID) }
                activityText = "正在回答…"
            case "error": throw DynamicAIError.server(event.message ?? "Dify 返回了未知错误")
            default: break
            }
        }
    }

    private func streamCompatibleMessage(assistantMessageID: String, configuration: Configuration) async throws {
        var request = authorizedRequest(
            url: configuration.baseURL.appendingPathComponent("chat/completions"),
            configuration: configuration
        )
        request.httpMethod = "POST"
        request.timeoutInterval = 300
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("text/event-stream", forHTTPHeaderField: "Accept")

        let chatMessages = messages
            .filter { !$0.text.isEmpty }
            .map { ["role": $0.role.rawValue, "content": $0.text] }
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "model": configuration.model,
            "messages": chatMessages,
            "stream": true
        ])

        let (bytes, response) = try await URLSession.shared.bytes(for: request)
        if let httpResponse = response as? HTTPURLResponse, !(200..<300 ~= httpResponse.statusCode) {
            var errorBody = Data()
            for try await byte in bytes { errorBody.append(byte) }
            try validate(response: response, body: errorBody, provider: configuration.provider)
        }
        try validate(response: response, body: nil, provider: configuration.provider)
        for try await line in bytes.lines {
            try Task.checkCancellation()
            guard line.hasPrefix("data:") else { continue }
            let payload = String(line.dropFirst(5)).trimmingCharacters(in: .whitespaces)
            if payload == "[DONE]" { break }
            guard let data = payload.data(using: .utf8) else { continue }
            let chunk = try JSONDecoder().decode(DynamicOpenAIStreamChunk.self, from: data)
            for choice in chunk.choices {
                if let content = choice.delta.content, !content.isEmpty {
                    appendAnswer(content, to: assistantMessageID)
                    activityText = "正在回答…"
                } else if let reasoning = choice.delta.reasoningContent, !reasoning.isEmpty {
                    activityText = "正在推理…"
                }
            }
        }
    }

    private func appendAnswer(_ answer: String, to messageID: String) {
        guard !answer.isEmpty, let index = messages.firstIndex(where: { $0.id == messageID }) else { return }
        messages[index].text += answer
    }

    private func replaceAnswerIfMoreComplete(_ answer: String, in messageID: String) {
        guard !answer.isEmpty,
              let index = messages.firstIndex(where: { $0.id == messageID }),
              answer.count > messages[index].text.count else { return }
        messages[index].text = answer
    }

    private func finishStreamingMessage(id: String) {
        guard let index = messages.firstIndex(where: { $0.id == id }) else { return }
        messages[index].isStreaming = false
        if messages[index].text.isEmpty { messages[index].text = "未收到回复，请重试。" }
    }

    private func requestJSON<Response: Decodable>(url: URL, configuration: Configuration) async throws -> Response {
        let (data, response) = try await URLSession.shared.data(for: authorizedRequest(url: url, configuration: configuration))
        try validate(response: response, body: data, provider: configuration.provider)
        return try JSONDecoder().decode(Response.self, from: data)
    }

    private func authorizedRequest(url: URL, configuration: Configuration) -> URLRequest {
        var request = URLRequest(url: url)
        request.timeoutInterval = 60
        request.setValue("Bearer \(configuration.apiKey)", forHTTPHeaderField: "Authorization")
        return request
    }

    private func validate(response: URLResponse, body: Data?, provider: DynamicAIProvider) throws {
        guard let response = response as? HTTPURLResponse else { throw DynamicAIError.invalidResponse }
        guard 200..<300 ~= response.statusCode else {
            if let body, let envelope = try? JSONDecoder().decode(APIErrorEnvelope.self, from: body) {
                throw DynamicAIError.server(envelope.resolvedMessage)
            }
            if response.statusCode == 401 { throw DynamicAIError.server("API Key 无效或已失效") }
            throw DynamicAIError.server("\(provider.displayName) 请求失败（\(response.statusCode)）")
        }
    }

    private func configuration() -> Configuration? {
        guard let apiKey = credentialStore.readAPIKey(for: currentProvider),
              let baseURL = URL(string: apiBaseURLString) else {
            isAPIKeyConfigured = false
            errorMessage = currentProvider == .dify ? "请先配置 Dify App API Key" : "请先配置 API Key"
            return nil
        }
        return Configuration(provider: currentProvider, baseURL: baseURL, apiKey: apiKey, model: modelName)
    }

    private func loadLocalConversations() -> [LocalConversation] {
        guard let data = try? Data(contentsOf: localConversationsURL) else { return [] }
        return (try? JSONDecoder().decode([LocalConversation].self, from: data)) ?? []
    }

    private func persistCurrentLocalConversation(configuration: Configuration) {
        guard configuration.provider != .dify, let id = selectedConversationID else { return }
        var saved = loadLocalConversations()
        let now = Date()
        let existing = saved.first(where: { $0.conversation.id == id })
        let firstPrompt = messages.first(where: { $0.role == .user })?.text ?? "新对话"
        let title = existing?.conversation.name ?? String(firstPrompt.prefix(28))
        let local = LocalConversation(
            conversation: DynamicAIConversation(
                id: id,
                name: title.isEmpty ? "新对话" : title,
                createdAt: existing?.conversation.createdAt ?? now,
                updatedAt: now
            ),
            provider: configuration.provider,
            model: configuration.model,
            messages: messages.map {
                var message = $0
                message.isStreaming = false
                return message
            }
        )
        saved.removeAll { $0.conversation.id == id }
        saved.append(local)
        do {
            try FileManager.default.createDirectory(
                at: localConversationsURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(saved).write(to: localConversationsURL, options: .atomic)
        } catch {
            errorMessage = "本地会话保存失败：\(error.localizedDescription)"
        }
    }

    private func userFacingError(_ error: Error) -> String {
        (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
    }
}

private extension DynamicDifyChatStore {
    struct Configuration {
        let provider: DynamicAIProvider
        let baseURL: URL
        let apiKey: String
        let model: String
    }

    struct LocalConversation: Codable {
        let conversation: DynamicAIConversation
        let provider: DynamicAIProvider
        let model: String
        let messages: [DynamicAIChatMessage]
    }

    struct ConversationListResponse: Decodable { let data: [DynamicAIConversation] }
    struct MessageListResponse: Decodable { let data: [HistoryItem] }

    struct HistoryItem: Decodable {
        let id: String
        let query: String
        let answer: String
        let createdAt: Date

        private enum CodingKeys: String, CodingKey {
            case id, query, answer
            case createdAt = "created_at"
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            id = try container.decode(String.self, forKey: .id)
            query = try container.decodeIfPresent(String.self, forKey: .query) ?? ""
            answer = try container.decodeIfPresent(String.self, forKey: .answer) ?? ""
            createdAt = Date(timeIntervalSince1970: try container.decodeIfPresent(Double.self, forKey: .createdAt) ?? 0)
        }
    }

    struct APIErrorEnvelope: Decodable {
        struct Detail: Decodable { let message: String? }
        let message: String?
        let error: Detail?
        var resolvedMessage: String { message ?? error?.message ?? "服务返回了未知错误" }
    }
}

private enum DynamicAIError: LocalizedError {
    case invalidURL
    case invalidResponse
    case server(String)

    var errorDescription: String? {
        switch self {
        case .invalidURL: return "API 地址无效"
        case .invalidResponse: return "AI 服务返回了无效响应"
        case let .server(message): return message
        }
    }
}

/// AI 凭据存储：使用当前用户专属的本地文件，避免开发版反复签名后触发 macOS
/// 钥匙串授权弹窗。旧钥匙串数据只做“禁止 UI”的静默迁移；无法静默读取时用户需重填一次。
final class DynamicDifyCredentialStore {
    static let shared = DynamicDifyCredentialStore()
    private let service = "ai.dynamic.app.dify"
    private let legacyAccount = "app-api-key"

    private var credentialsURL: URL {
        BridgeRuntimePaths.runtimeDirectoryURL
            .appendingPathComponent("dynamic-ai-credentials.json")
    }

    func readAPIKey(for provider: DynamicAIProvider) -> String? {
        let account = account(for: provider)
        if let key = readLocalCredentials()[account], !key.isEmpty {
            return key
        }
        guard let legacy = readLegacyKeychainSilently(account: account) else { return nil }
        try? saveLocalValue(legacy, account: account)
        return legacy
    }

    func readLegacyAPIKey() -> String? {
        if let key = readLocalCredentials()[legacyAccount], !key.isEmpty {
            return key
        }
        return readLegacyKeychainSilently(account: legacyAccount)
    }

    func saveAPIKey(_ apiKey: String, for provider: DynamicAIProvider) throws {
        try saveLocalValue(apiKey, account: account(for: provider))
    }

    func deleteAPIKey(for provider: DynamicAIProvider) {
        var credentials = readLocalCredentials()
        credentials.removeValue(forKey: account(for: provider))
        try? writeLocalCredentials(credentials)
    }

    private func readLegacyKeychainSilently(account: String) -> String? {
        var query = baseQuery(account: account)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        // 开发版每次重新签名可能不再匹配旧 ACL；明确禁止 Security.framework 弹授权 UI。
        let authenticationContext = LAContext()
        authenticationContext.interactionNotAllowed = true
        query[kSecUseAuthenticationContext as String] = authenticationContext
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private func account(for provider: DynamicAIProvider) -> String {
        "provider-\(provider.rawValue)-api-key"
    }

    private func baseQuery(account: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
    }

    private func readLocalCredentials() -> [String: String] {
        guard let data = try? Data(contentsOf: credentialsURL) else { return [:] }
        return (try? JSONDecoder().decode([String: String].self, from: data)) ?? [:]
    }

    private func saveLocalValue(_ value: String, account: String) throws {
        var credentials = readLocalCredentials()
        credentials[account] = value
        try writeLocalCredentials(credentials)
    }

    private func writeLocalCredentials(_ credentials: [String: String]) throws {
        let directory = credentialsURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        let data = try JSONEncoder().encode(credentials)
        try data.write(to: credentialsURL, options: .atomic)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o600],
            ofItemAtPath: credentialsURL.path
        )
    }
}
