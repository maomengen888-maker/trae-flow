import AppKit
import SwiftUI

/// Dynamic 原生 AI 工作台：支持 Dify 与 OpenAI Chat Completions 兼容服务。
struct DynamicAIAgentView: View {
    @ObservedObject private var store = DynamicDifyChatStore.shared
    @State private var composerText = ""
    @State private var isShowingConfiguration = false
    @State private var providerInput: DynamicAIProvider = .dify
    @State private var apiKeyInput = ""
    @State private var apiBaseURLInput = ""
    @State private var modelInput = ""
    @FocusState private var isComposerFocused: Bool

    var body: some View {
        HStack(spacing: 0) {
            sidebar
            Divider().overlay(Color.white.opacity(0.08))
            chatWorkspace
        }
        .background(Color(red: 0.035, green: 0.038, blue: 0.047))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Color.white.opacity(0.09), lineWidth: 1)
        }
        .overlay {
            if isShowingConfiguration || !store.isAPIKeyConfigured {
                configurationOverlay
            }
        }
        .onAppear {
            loadConfigurationInputs()
            isShowingConfiguration = !store.isAPIKeyConfigured
            store.connectIfNeeded()
            if store.isAPIKeyConfigured { isComposerFocused = true }
        }
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 9) {
                aiIcon(size: 30)
                VStack(alignment: .leading, spacing: 1) {
                    Text("摸鱼岛 AI")
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white)
                    Text(store.serviceDescription)
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(.white.opacity(0.45))
                }
                Spacer()
            }
            .padding(.horizontal, 4)

            Button {
                store.startNewConversation()
                composerText = ""
                isComposerFocused = true
            } label: {
                Label("新建对话", systemImage: "square.and.pencil")
                    .font(.system(size: 11, weight: .medium))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 11)
                    .padding(.vertical, 9)
                    .background(Color.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 8))
            }
            .buttonStyle(.plain)
            .foregroundStyle(.white.opacity(0.9))
            .disabled(store.isSending)

            Text("最近")
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(.white.opacity(0.36))
                .padding(.horizontal, 8)

            ScrollView {
                LazyVStack(spacing: 3) {
                    if store.isLoadingConversations && store.conversations.isEmpty {
                        ProgressView().controlSize(.small).padding(.top, 18)
                    }
                    ForEach(store.conversations) { conversation in
                        conversationRow(conversation)
                    }
                }
            }

            Spacer(minLength: 0)

            Button {
                loadConfigurationInputs()
                isShowingConfiguration = true
            } label: {
                HStack(spacing: 8) {
                    Circle()
                        .fill(connectionStatusColor)
                        .frame(width: 6, height: 6)
                    Text(connectionStatusText)
                        .font(.system(size: 10, weight: .medium))
                    Spacer()
                    Image(systemName: "gearshape").font(.system(size: 10))
                }
                .foregroundStyle(.white.opacity(0.62))
                .padding(.horizontal, 9)
                .padding(.vertical, 8)
            }
            .buttonStyle(.plain)
        }
        .padding(12)
        .frame(width: 224)
        .background(Color(red: 0.025, green: 0.027, blue: 0.033))
    }

    private func conversationRow(_ conversation: DynamicAIConversation) -> some View {
        Button {
            store.selectConversation(conversation.id)
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "bubble.left")
                    .font(.system(size: 10))
                    .foregroundStyle(.white.opacity(0.45))
                Text(conversation.name.isEmpty ? "未命名对话" : conversation.name)
                    .font(.system(size: 10, weight: .medium))
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            .foregroundStyle(.white.opacity(0.8))
            .padding(.horizontal, 9)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 7)
                    .fill(store.selectedConversationID == conversation.id ? Color.white.opacity(0.09) : Color.clear)
            )
        }
        .buttonStyle(.plain)
        .disabled(store.isSending)
    }

    private var chatWorkspace: some View {
        VStack(spacing: 0) {
            HStack(spacing: 9) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(store.selectedConversationName)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.9))
                        .lineLimit(1)
                    Text(store.isSending ? (store.activityText ?? "正在执行…") : store.serviceDescription)
                        .font(.system(size: 9))
                        .foregroundStyle(store.isSending ? Color.cyan : Color.white.opacity(0.38))
                }
                Spacer()
                if store.isLoadingMessages { ProgressView().controlSize(.small) }
                Button {
                    Task { await store.refreshConversations() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.plain)
                .foregroundStyle(.white.opacity(0.55))
                .help("刷新会话")
            }
            .padding(.horizontal, 18)
            .frame(height: 48)
            .background(Color.black.opacity(0.08))

            Divider().overlay(Color.white.opacity(0.07))
            messageArea
            composer
        }
    }

    @ViewBuilder
    private var messageArea: some View {
        if store.messages.isEmpty && !store.isLoadingMessages {
            emptyChat
        } else {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 22) {
                        ForEach(store.messages) { message in
                            messageRow(message).id(message.id)
                        }
                    }
                    .padding(.horizontal, 34)
                    .padding(.vertical, 28)
                }
                .onChange(of: store.messages) { _, messages in
                    guard let id = messages.last?.id else { return }
                    withAnimation(.easeOut(duration: 0.18)) {
                        proxy.scrollTo(id, anchor: .bottom)
                    }
                }
            }
        }
    }

    private var emptyChat: some View {
        VStack(spacing: 16) {
            Spacer()
            ZStack {
                Circle().fill(Color.white.opacity(0.06))
                Image(systemName: "sparkles")
                    .font(.system(size: 23, weight: .medium))
                    .foregroundStyle(.white.opacity(0.9))
            }
            .frame(width: 58, height: 58)
            Text("我可以帮你做什么？")
                .font(.system(size: 20, weight: .semibold, design: .rounded))
                .foregroundStyle(.white.opacity(0.92))
            Text("连接你选择的 AI 模型，处理需求、整理文档或完成任务")
                .font(.system(size: 11))
                .foregroundStyle(.white.opacity(0.42))
            HStack(spacing: 8) {
                suggestion("帮我整理今日工作")
                suggestion("帮我梳理一份 PRD")
                suggestion("分析当前需求风险")
            }
            Spacer()
        }
        .padding(30)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func messageRow(_ message: DynamicAIChatMessage) -> some View {
        HStack(alignment: .top, spacing: 12) {
            if message.role == .user { Spacer(minLength: 90) }
            if message.role == .assistant { aiIcon(size: 27) }

            VStack(alignment: .leading, spacing: 8) {
                Text(message.role == .user ? "你" : "摸鱼岛")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.46))
                if message.text.isEmpty && message.isStreaming {
                    HStack(spacing: 5) {
                        ProgressView().controlSize(.mini)
                        Text(store.activityText ?? "正在思考…")
                            .font(.system(size: 11))
                            .foregroundStyle(.white.opacity(0.48))
                    }
                } else {
                    Text(markdownText(message.text))
                        .font(.system(size: 12))
                        .foregroundStyle(.white.opacity(0.88))
                        .textSelection(.enabled)
                        .lineSpacing(4)
                }
                if message.role == .assistant && !message.text.isEmpty && !message.isStreaming {
                    Button {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(message.text, forType: .string)
                    } label: {
                        Label("复制", systemImage: "doc.on.doc").font(.system(size: 9))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.white.opacity(0.36))
                }
            }
            .padding(message.role == .user ? 12 : 0)
            .background(
                message.role == .user ? Color.white.opacity(0.07) : Color.clear,
                in: RoundedRectangle(cornerRadius: 12)
            )

            if message.role == .assistant { Spacer(minLength: 28) }
        }
        .frame(maxWidth: .infinity)
    }

    private var composer: some View {
        VStack(spacing: 8) {
            if let errorMessage = store.errorMessage {
                Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                    .font(.system(size: 10))
                    .foregroundStyle(.orange)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            HStack(alignment: .bottom, spacing: 10) {
                TextField("向摸鱼岛发送消息…", text: $composerText, axis: .vertical)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12))
                    .lineLimit(1...6)
                    .focused($isComposerFocused)
                    .onSubmit(sendComposerText)

                if store.isSending {
                    Button(action: store.stopGenerating) {
                        Image(systemName: "stop.fill")
                            .font(.system(size: 10, weight: .bold))
                            .frame(width: 29, height: 29)
                            .background(Color.white, in: Circle())
                            .foregroundStyle(.black)
                    }
                    .buttonStyle(.plain)
                    .help("停止生成")
                } else {
                    Button(action: sendComposerText) {
                        Image(systemName: "arrow.up")
                            .font(.system(size: 12, weight: .bold))
                            .frame(width: 29, height: 29)
                            .background(canSend ? Color.white : Color.white.opacity(0.16), in: Circle())
                            .foregroundStyle(canSend ? Color.black : Color.white.opacity(0.32))
                    }
                    .buttonStyle(.plain)
                    .disabled(!canSend)
                }
            }
            .padding(12)
            .background(Color.white.opacity(0.055), in: RoundedRectangle(cornerRadius: 14))
            .overlay {
                RoundedRectangle(cornerRadius: 14)
                    .strokeBorder(Color.white.opacity(0.11), lineWidth: 1)
            }
            Text("回车发送 · API Key 仅保存在本机受保护配置中")
                .font(.system(size: 9))
                .foregroundStyle(.white.opacity(0.28))
        }
        .padding(.horizontal, 34)
        .padding(.top, 8)
        .padding(.bottom, 18)
    }

    private var configurationOverlay: some View {
        ZStack {
            Color.black.opacity(0.72).ignoresSafeArea()
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    ZStack {
                        RoundedRectangle(cornerRadius: 9).fill(Color.white)
                        Image(systemName: "key.fill").foregroundStyle(.black)
                    }
                    .frame(width: 34, height: 34)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("连接 AI 服务").font(.system(size: 16, weight: .semibold))
                        Text(configurationSubtitle)
                            .font(.system(size: 10)).foregroundStyle(.secondary)
                    }
                    Spacer()
                    if store.isAPIKeyConfigured {
                        Button { isShowingConfiguration = false } label: { Image(systemName: "xmark") }
                            .buttonStyle(.plain)
                    }
                }

                configurationField(title: "服务提供商") {
                    Picker("服务提供商", selection: $providerInput) {
                        ForEach(DynamicAIProvider.allCases) { provider in
                            Text(provider.displayName).tag(provider)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .onChange(of: providerInput) { _, provider in
                        if provider == store.currentProvider {
                            apiBaseURLInput = store.apiBaseURLString
                            modelInput = store.modelName
                        } else {
                            apiBaseURLInput = provider.defaultBaseURL
                            modelInput = provider.defaultModel
                        }
                        apiKeyInput = ""
                    }
                }

                configurationField(title: "API Base URL") {
                    TextField(providerInput.defaultBaseURL.isEmpty ? "https://api.example.com/v1" : providerInput.defaultBaseURL, text: $apiBaseURLInput)
                        .textFieldStyle(.plain)
                }
                if providerInput.requiresModel {
                    configurationField(title: "模型名称") {
                        TextField(providerInput.defaultModel.isEmpty ? "例如：model-name" : providerInput.defaultModel, text: $modelInput)
                            .textFieldStyle(.plain)
                    }
                }
                configurationField(title: providerInput == .dify ? "Dify App API Key" : "API Key") {
                    SecureField(keyPlaceholder, text: $apiKeyInput)
                        .textFieldStyle(.plain)
                }

                if let errorMessage = store.errorMessage {
                    Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                        .font(.system(size: 10)).foregroundStyle(.orange)
                }
                Text("Key 保存在仅当前 Mac 用户可读的本地配置中，不会触发钥匙串授权，也不会写入源码或上传 GitHub。")
                    .font(.system(size: 10)).foregroundStyle(.secondary)

                HStack {
                    if store.isAPIKeyConfigured && providerInput == store.currentProvider {
                        Button("移除配置", role: .destructive) {
                            store.removeConfiguration()
                            apiKeyInput = ""
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(.red.opacity(0.85))
                    }
                    Spacer()
                    Button("保存并连接") {
                        Task {
                            if await store.saveConfiguration(
                                provider: providerInput,
                                apiKey: apiKeyInput,
                                baseURLString: apiBaseURLInput,
                                modelName: modelInput
                            ) {
                                apiKeyInput = ""
                                isShowingConfiguration = false
                                isComposerFocused = true
                            }
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.white)
                    .foregroundStyle(.black)
                }
            }
            .padding(22)
            .frame(width: 500)
            .background(Color(red: 0.07, green: 0.073, blue: 0.085), in: RoundedRectangle(cornerRadius: 16))
            .overlay {
                RoundedRectangle(cornerRadius: 16)
                    .strokeBorder(Color.white.opacity(0.13), lineWidth: 1)
            }
            .shadow(color: .black.opacity(0.5), radius: 30, y: 14)
        }
    }

    private func configurationField<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.system(size: 10, weight: .semibold))
            content()
                .padding(10)
                .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))
        }
    }

    private func aiIcon(size: CGFloat) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.25, style: .continuous).fill(Color.white)
            Image(systemName: "sparkles")
                .font(.system(size: size * 0.4, weight: .bold))
                .foregroundStyle(.black)
        }
        .frame(width: size, height: size)
    }

    private func suggestion(_ text: String) -> some View {
        Button {
            composerText = text
            isComposerFocused = true
        } label: {
            Text(text)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.white.opacity(0.66))
                .padding(.horizontal, 11)
                .padding(.vertical, 8)
                .background(Color.white.opacity(0.045), in: RoundedRectangle(cornerRadius: 9))
                .overlay { RoundedRectangle(cornerRadius: 9).strokeBorder(Color.white.opacity(0.08)) }
        }
        .buttonStyle(.plain)
    }

    private var canSend: Bool {
        store.isAPIKeyConfigured && !store.isSending
            && !composerText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var connectionStatusText: String {
        if !store.isAPIKeyConfigured { return "配置 AI 服务" }
        return store.errorMessage == nil
            ? "\(store.providerDisplayName) 已连接"
            : "\(store.providerDisplayName) 连接异常"
    }

    private var connectionStatusColor: Color {
        guard store.isAPIKeyConfigured else { return .orange }
        return store.errorMessage == nil ? .green : .orange
    }

    private func sendComposerText() {
        guard canSend else { return }
        let text = composerText
        composerText = ""
        store.send(text)
    }

    private var configurationSubtitle: String {
        providerInput == .dify
            ? "Dify 使用 App API Key；其他服务使用模型供应商 API Key"
            : "使用模型供应商 API Key，通过 Chat Completions 协议连接"
    }

    private var keyPlaceholder: String {
        store.hasSavedAPIKey(for: providerInput)
            ? "已保存，留空表示不修改"
            : (providerInput == .dify ? "app-xxxxxxxxxxxxxxxx" : "输入 API Key")
    }

    private func loadConfigurationInputs() {
        providerInput = store.currentProvider
        apiBaseURLInput = store.apiBaseURLString
        modelInput = store.modelName
        apiKeyInput = ""
    }

    private func markdownText(_ text: String) -> AttributedString {
        (try? AttributedString(
            markdown: text,
            options: AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        )) ?? AttributedString(text)
    }
}
