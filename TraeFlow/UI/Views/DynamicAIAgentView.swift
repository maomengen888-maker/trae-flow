import AppKit
import SwiftUI
import UniformTypeIdentifiers

private enum DynamicAIRoute: String, CaseIterable, Identifiable {
    case chat, memories, knowledge, privacy, audit, harness
    var id: String { rawValue }

    var title: String {
        switch self {
        case .chat: return "陪伴对话"
        case .memories: return "记忆管理"
        case .knowledge: return "资料库"
        case .privacy: return "隐私空间"
        case .audit: return "调用记录"
        case .harness: return "开发者工作台"
        }
    }

    var icon: String {
        switch self {
        case .chat: return "bubble.left.and.bubble.right.fill"
        case .memories: return "brain.head.profile"
        case .knowledge: return "books.vertical.fill"
        case .privacy: return "lock.shield.fill"
        case .audit: return "list.bullet.clipboard.fill"
        case .harness: return "shippingbox.fill"
        }
    }
}

/// 灵动岛 AI 主界面：陪伴产品层自研，DeepSeek Harness 作为隔离的二级开发者工作台。
struct DynamicAIAgentView: View {
    @ObservedObject private var chatStore = DynamicDifyChatStore.shared
    @ObservedObject private var memoryStore = DynamicAIMemoryStore.shared
    @ObservedObject private var knowledgeStore = DynamicAIKnowledgeStore.shared
    @ObservedObject private var privacyStore = DynamicAIPrivateVaultStore.shared
    @ObservedObject private var auditStore = DynamicAIAuditStore.shared

    @State private var route: DynamicAIRoute = .chat
    @State private var mode: DynamicAIChatMode = .companion
    @State private var draft = ""
    @State private var isConfigurationPresented = false
    @State private var conversationToRename: DynamicAIConversation?
    @State private var renameDraft = ""

    var body: some View {
        HStack(spacing: 0) {
            sidebar.frame(width: 238)
            Divider().overlay(Color.white.opacity(0.08))
            mainContent.frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(DynamicVisualTheme.canvasGradient)
        .dynamicSurface(radius: DynamicVisualTheme.outerRadius, neonBorder: true)
        .sheet(isPresented: $isConfigurationPresented) {
            DynamicAIConfigurationSheet(store: chatStore)
        }
        .alert("重命名会话", isPresented: Binding(
            get: { conversationToRename != nil },
            set: { if !$0 { conversationToRename = nil } }
        )) {
            TextField("会话名称", text: $renameDraft)
            Button("取消", role: .cancel) { conversationToRename = nil }
            Button("保存") {
                guard let conversationToRename else { return }
                Task { await chatStore.renameConversation(conversationToRename.id, name: renameDraft) }
                self.conversationToRename = nil
            }
        }
        .onAppear { chatStore.connectIfNeeded() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didResignActiveNotification)) { _ in
            privacyStore.lock()
        }
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                JianyuCompanionPet(size: 38)
                VStack(alignment: .leading, spacing: 2) {
                    Text("灵动岛")
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                        .foregroundStyle(.white.opacity(0.94))
                    Text("安静地陪你想清楚")
                        .font(.system(size: 9.5, weight: .medium))
                        .foregroundStyle(.white.opacity(0.42))
                }
                Spacer()
            }
            .padding(.horizontal, 14)
            .padding(.top, 14)

            Button {
                route = .chat
                chatStore.startNewConversation()
            } label: {
                Label("新建对话", systemImage: "square.and.pencil")
                    .font(.system(size: 11, weight: .semibold))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 12)
                    .frame(height: 34)
                    .background(DynamicVisualTheme.elevatedCard, in: RoundedRectangle(cornerRadius: 14))
                    .overlay {
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .strokeBorder(Color.white.opacity(0.08), lineWidth: 0.8)
                    }
            }
            .buttonStyle(.plain)
            .foregroundStyle(.white.opacity(0.86))
            .padding(.horizontal, 12)

            Text("最近会话")
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(.white.opacity(0.32))
                .padding(.horizontal, 16)

            ScrollView {
                LazyVStack(spacing: 3) {
                    ForEach(chatStore.conversations) { conversation in
                        Button {
                            route = .chat
                            chatStore.selectConversation(conversation.id)
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: "bubble.left")
                                    .font(.system(size: 10))
                                    .foregroundStyle(.white.opacity(0.38))
                                Text(conversation.name)
                                    .font(.system(size: 10.5, weight: .medium))
                                    .lineLimit(1)
                                Spacer(minLength: 0)
                            }
                            .foregroundStyle(.white.opacity(0.72))
                            .padding(.horizontal, 10)
                            .frame(height: 30)
                            .background(
                                chatStore.selectedConversationID == conversation.id
                                    ? DynamicVisualTheme.elevatedCard
                                    : Color.clear,
                                in: RoundedRectangle(cornerRadius: 12)
                            )
                            .overlay {
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .strokeBorder(
                                        chatStore.selectedConversationID == conversation.id
                                            ? DynamicVisualTheme.orange.opacity(0.9)
                                            : Color.clear,
                                        lineWidth: 1.2
                                    )
                            }
                        }
                        .buttonStyle(.plain)
                        .contextMenu {
                            Button("重命名") {
                                renameDraft = conversation.name
                                conversationToRename = conversation
                            }
                            Button("删除", role: .destructive) {
                                Task { await chatStore.deleteConversation(conversation.id) }
                            }
                        }
                    }
                }
                .padding(.horizontal, 10)
            }
            .frame(maxHeight: .infinity)

            VStack(spacing: 3) {
                sidebarRoute(.memories, badge: memoryStore.pendingCount)
                sidebarRoute(.knowledge, badge: knowledgeStore.documents.count)
                sidebarRoute(.privacy)
                sidebarRoute(.audit)
                Divider().overlay(Color.white.opacity(0.08)).padding(.vertical, 3)
                sidebarRoute(.harness)
            }
            .padding(.horizontal, 10)
            .padding(.bottom, 12)
        }
        .background(DynamicVisualTheme.card.opacity(0.92))
    }

    private func sidebarRoute(_ item: DynamicAIRoute, badge: Int? = nil) -> some View {
        Button {
            route = item
            if item == .harness { DeepSeekHarnessManager.shared.start() }
        } label: {
            HStack(spacing: 9) {
                Image(systemName: item.icon).frame(width: 16)
                Text(item.title)
                Spacer()
                if let badge, badge > 0 {
                    Text("\(badge)")
                        .font(.system(size: 8, weight: .bold))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.orange.opacity(0.18), in: Capsule())
                        .foregroundStyle(.orange.opacity(0.9))
                }
            }
            .font(.system(size: 10.5, weight: .medium))
            .foregroundStyle(route == item ? .white : .white.opacity(0.55))
            .padding(.horizontal, 10)
            .frame(height: 30)
            .background(
                route == item ? DynamicVisualTheme.elevatedCard : .clear,
                in: RoundedRectangle(cornerRadius: 13)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 13, style: .continuous)
                    .strokeBorder(
                        route == item
                            ? DynamicVisualTheme.orange.opacity(0.94)
                            : Color.white.opacity(0.06),
                        lineWidth: route == item ? 1.3 : 0.7
                    )
            }
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var mainContent: some View {
        switch route {
        case .chat: chatWorkspace
        case .memories: DynamicAIMemoryManagementView(store: memoryStore)
        case .knowledge: DynamicAIKnowledgeLibraryView(store: knowledgeStore)
        case .privacy: DynamicAIPrivateVaultView(store: privacyStore)
        case .audit: DynamicAIAuditView(store: auditStore)
        case .harness: DeepSeekHarnessView()
        }
    }

    private var chatWorkspace: some View {
        VStack(spacing: 0) {
            chatHeader
            Divider().overlay(Color.white.opacity(0.08))
            messagesView
            composer
        }
    }

    private var chatHeader: some View {
        HStack(spacing: 10) {
            JianyuCompanionPet(size: 32)
            VStack(alignment: .leading, spacing: 2) {
                Text(chatStore.selectedConversationName)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.9))
                    .lineLimit(1)
                Text(chatStore.serviceDescription)
                    .font(.system(size: 9))
                    .foregroundStyle(.white.opacity(0.36))
            }
            Spacer()
            Menu {
                ForEach(DynamicAIChatMode.allCases) { item in
                    Button(item.title) { mode = item }
                }
            } label: {
                Label(mode.title, systemImage: "sparkles")
                    .font(.system(size: 10, weight: .semibold))
                    .padding(.horizontal, 10)
                    .frame(height: 28)
                    .background(DynamicVisualTheme.elevatedCard, in: Capsule())
                    .overlay(Capsule().strokeBorder(Color.white.opacity(0.08), lineWidth: 0.8))
            }
            .menuStyle(.borderlessButton)
            .foregroundStyle(.white.opacity(0.74))
            Button { isConfigurationPresented = true } label: {
                Image(systemName: "slider.horizontal.3")
                    .font(.system(size: 11, weight: .semibold))
                    .frame(width: 28, height: 28)
                    .background(DynamicVisualTheme.elevatedCard, in: Circle())
                    .overlay(Circle().strokeBorder(Color.white.opacity(0.08), lineWidth: 0.8))
            }
            .buttonStyle(.plain)
            .foregroundStyle(.white.opacity(0.7))
            .help("模型与连接设置")
        }
        .padding(.horizontal, 16)
        .frame(height: 54)
        .background(DynamicVisualTheme.card.opacity(0.72))
    }

    private var messagesView: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 16) {
                    if chatStore.messages.isEmpty {
                        emptyConversation.padding(.top, 70)
                    }
                    ForEach(chatStore.messages) { message in
                        DynamicAIMessageRow(message: message).id(message.id)
                    }
                    if let error = chatStore.errorMessage {
                        Text(error)
                            .font(.system(size: 10))
                            .foregroundStyle(.orange.opacity(0.9))
                            .padding(10)
                            .background(Color.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
                    }
                }
                .padding(18)
            }
            .onChange(of: chatStore.messages.count) { _, _ in
                if let last = chatStore.messages.last { proxy.scrollTo(last.id, anchor: .bottom) }
            }
        }
    }

    private var emptyConversation: some View {
        VStack(spacing: 16) {
            JianyuCompanionPet(size: 92)
            VStack(spacing: 6) {
                Text("今天想从哪里开始？")
                    .font(.system(size: 22, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.92))
                Text("我会自动参考相关记忆和资料；你随时可以查看来源、修改或删除。")
                    .font(.system(size: 10.5))
                    .foregroundStyle(.white.opacity(0.4))
            }
            HStack(spacing: 8) {
                suggestion("帮我复盘今天", .review)
                suggestion("给我一个下一步建议", .advice)
                suggestion("根据资料回答", .knowledge)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func suggestion(_ title: String, _ targetMode: DynamicAIChatMode) -> some View {
        Button(title) {
            mode = targetMode
            draft = title
        }
        .buttonStyle(.plain)
        .font(.system(size: 9.5, weight: .medium))
        .foregroundStyle(.white.opacity(0.62))
        .padding(.horizontal, 11)
        .frame(height: 30)
        .background(DynamicVisualTheme.card, in: Capsule())
        .overlay(Capsule().strokeBorder(Color.white.opacity(0.07), lineWidth: 0.8))
    }

    private var composer: some View {
        VStack(spacing: 8) {
            let memoryMatches = memoryStore.context(for: draft)
            let knowledgeMatches = knowledgeStore.matches(for: draft)
            if !draft.isEmpty && (!memoryMatches.isEmpty || !knowledgeMatches.isEmpty) {
                HStack(spacing: 8) {
                    Image(systemName: "link")
                    Text("本轮将参考 \(memoryMatches.count) 条记忆、\(knowledgeMatches.count) 份资料")
                    Spacer()
                    Button("查看") { route = memoryMatches.isEmpty ? .knowledge : .memories }
                        .buttonStyle(.plain)
                        .foregroundStyle(.cyan.opacity(0.8))
                }
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(.white.opacity(0.4))
                .padding(.horizontal, 4)
            }

            HStack(alignment: .bottom, spacing: 10) {
                TextField("说点什么…", text: $draft, axis: .vertical)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12))
                    .foregroundStyle(.white.opacity(0.9))
                    .lineLimit(1...5)
                    .padding(.horizontal, 13)
                    .padding(.vertical, 10)
                    .background(DynamicVisualTheme.elevatedCard, in: RoundedRectangle(cornerRadius: 18))
                    .overlay {
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .strokeBorder(Color.white.opacity(0.09), lineWidth: 0.8)
                    }
                    .onSubmit { sendDraft() }

                Button {
                    chatStore.isSending ? chatStore.stopGenerating() : sendDraft()
                } label: {
                    Image(systemName: chatStore.isSending ? "stop.fill" : "arrow.up")
                        .font(.system(size: 13, weight: .bold))
                        .frame(width: 36, height: 36)
                        .background(
                            draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !chatStore.isSending
                                ? Color.white.opacity(0.08)
                                : DynamicVisualTheme.orange,
                            in: Circle()
                        )
                        .foregroundStyle(chatStore.isSending ? .black : .white)
                }
                .buttonStyle(.plain)
                .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !chatStore.isSending)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(DynamicVisualTheme.card.opacity(0.84))
    }

    private func sendDraft() {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !chatStore.isSending else { return }
        draft = ""
        if let safetyResponse = DynamicAISafetyRouter.response(for: text) {
            chatStore.appendLocalSafetyResponse(userText: text, response: safetyResponse)
            return
        }
        memoryStore.propose(from: text, sourceMessageID: UUID().uuidString)
        let context = DynamicAIContextBuilder.build(
            mode: mode,
            query: text,
            memories: memoryStore.context(for: text),
            knowledge: knowledgeStore.matches(for: text),
            blockedRules: memoryStore.blockedRules
        )
        chatStore.send(text, systemContext: context)
    }
}

private struct JianyuCompanionPet: View {
    let size: CGFloat
    @State private var breathing = false

    var body: some View {
        ZStack {
            Circle()
                .fill(RadialGradient(
                    colors: [Color.orange.opacity(0.72), Color.pink.opacity(0.42), Color.purple.opacity(0.16)],
                    center: .topLeading,
                    startRadius: 2,
                    endRadius: size * 0.62
                ))
                .overlay(Circle().stroke(Color.white.opacity(0.28), lineWidth: 0.7))
            HStack(spacing: size * 0.16) {
                Capsule().fill(Color.white.opacity(0.9)).frame(width: size * 0.10, height: size * 0.16)
                Capsule().fill(Color.white.opacity(0.9)).frame(width: size * 0.10, height: size * 0.16)
            }
            .offset(y: -size * 0.03)
            Capsule().fill(Color.white.opacity(0.72))
                .frame(width: size * 0.25, height: size * 0.06)
                .offset(y: size * 0.18)
        }
        .frame(width: size, height: size)
        .scaleEffect(breathing ? 1.025 : 0.985)
        .shadow(color: Color.orange.opacity(0.2), radius: breathing ? 12 : 6)
        .onAppear {
            withAnimation(.easeInOut(duration: 2.8).repeatForever(autoreverses: true)) { breathing = true }
        }
        .accessibilityLabel("灵动岛陪伴宠物")
    }
}

private struct DynamicAIMessageRow: View {
    let message: DynamicAIChatMessage

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            if message.role == .user { Spacer(minLength: 90) }
            if message.role == .assistant { JianyuCompanionPet(size: 26) }
            VStack(alignment: .leading, spacing: 5) {
                Text(message.text.isEmpty && message.isStreaming ? "正在想…" : message.text)
                    .font(.system(size: 11.5))
                    .foregroundStyle(.white.opacity(message.text.isEmpty ? 0.38 : 0.86))
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                if message.isStreaming { ProgressView().controlSize(.mini).tint(.orange.opacity(0.7)) }
            }
            .padding(.horizontal, 13)
            .padding(.vertical, 10)
            .background(
                message.role == .user ? Color.white.opacity(0.10) : Color.white.opacity(0.055),
                in: RoundedRectangle(cornerRadius: 12)
            )
            if message.role == .assistant { Spacer(minLength: 70) }
        }
        .frame(maxWidth: .infinity)
    }
}

private struct DynamicAIMemoryManagementView: View {
    @ObservedObject var store: DynamicAIMemoryStore
    @State private var blockedRuleDraft = ""

    var body: some View {
        DynamicAIManagementScaffold(title: "记忆管理", subtitle: "每条记忆都可以查看来源、确认、修改或删除。") {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    blockedRules
                    if store.memories.isEmpty {
                        DynamicAIEmptyState(
                            icon: "brain.head.profile",
                            title: "还没有记忆",
                            detail: "聊天中出现稳定偏好、目标或重要事件后，会先进入这里。"
                        )
                        .padding(.top, 60)
                    } else {
                        ForEach(store.memories) { memory in memoryCard(memory) }
                    }
                }
                .padding(18)
            }
        }
    }

    private var blockedRules: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("禁止记忆")
                .font(.system(size: 12, weight: .semibold))
            HStack {
                TextField("例如：密码、公司机密、某个人名", text: $blockedRuleDraft)
                    .textFieldStyle(.plain)
                    .padding(9)
                    .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))
                Button("添加") {
                    store.addBlockedRule(blockedRuleDraft)
                    blockedRuleDraft = ""
                }
                .buttonStyle(.bordered)
            }
            if !store.blockedRules.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(store.blockedRules, id: \.self) { rule in
                            HStack(spacing: 5) {
                                Text(rule)
                                Button { store.deleteBlockedRule(rule) } label: {
                                    Image(systemName: "xmark.circle.fill")
                                }
                                .buttonStyle(.plain)
                            }
                            .font(.system(size: 9.5))
                            .padding(.horizontal, 8)
                            .frame(height: 25)
                            .background(Color.red.opacity(0.10), in: Capsule())
                        }
                    }
                }
            }
        }
        .foregroundStyle(.white.opacity(0.75))
        .padding(14)
        .background(Color.white.opacity(0.045), in: RoundedRectangle(cornerRadius: 12))
    }

    private func memoryCard(_ memory: DynamicAIMemory) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack {
                Text(memory.category)
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(memory.status == .conflicted ? .orange : .cyan.opacity(0.85))
                Text(memory.status == .confirmed ? "已确认" : (memory.status == .conflicted ? "存在冲突" : "待确认"))
                    .font(.system(size: 8.5, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.36))
                Spacer()
                if memory.status != .confirmed {
                    Button("确认") { store.confirm(memory.id) }.buttonStyle(.borderless)
                }
                Button(role: .destructive) { store.delete(memory.id) } label: {
                    Image(systemName: "trash")
                }
                .buttonStyle(.borderless)
            }
            Text(memory.content)
                .font(.system(size: 11))
                .foregroundStyle(.white.opacity(0.82))
                .textSelection(.enabled)
            Label(
                "来源：\(memory.source.title) · \(memory.source.createdAt.formatted(date: .abbreviated, time: .shortened))",
                systemImage: "link"
            )
            .font(.system(size: 8.5))
            .foregroundStyle(.white.opacity(0.34))
        }
        .padding(13)
        .background(Color.white.opacity(0.045), in: RoundedRectangle(cornerRadius: 12))
    }
}

private struct DynamicAIKnowledgeLibraryView: View {
    @ObservedObject var store: DynamicAIKnowledgeStore
    @State private var isImporterPresented = false

    var body: some View {
        DynamicAIManagementScaffold(
            title: "资料库",
            subtitle: "主动上传日记和文件；回答时会自动检索，不需要手动切换模式。"
        ) {
            VStack(spacing: 0) {
                HStack {
                    Text("\(store.documents.count) 份资料")
                        .font(.system(size: 10))
                        .foregroundStyle(.white.opacity(0.4))
                    Spacer()
                    Button { isImporterPresented = true } label: {
                        Label(store.isImporting ? "正在导入" : "上传文件", systemImage: "square.and.arrow.down")
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Color.orange.opacity(0.82))
                    .disabled(store.isImporting)
                }
                .padding(16)

                ScrollView {
                    LazyVStack(spacing: 10) {
                        if store.documents.isEmpty {
                            DynamicAIEmptyState(
                                icon: "books.vertical",
                                title: "还没有资料",
                                detail: "支持 TXT、Markdown、PDF、DOCX 等常见文件，单个文件不超过 50MB。"
                            )
                            .padding(.top, 80)
                        }
                        ForEach(store.documents) { document in
                            HStack(spacing: 12) {
                                Image(systemName: "doc.text.fill")
                                    .font(.system(size: 22))
                                    .foregroundStyle(.cyan.opacity(0.7))
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(document.name)
                                        .font(.system(size: 11, weight: .semibold))
                                        .foregroundStyle(.white.opacity(0.84))
                                        .lineLimit(1)
                                    Text(document.status == .ready ? "已建立文本索引" : (document.errorMessage ?? "仅保存原文件"))
                                        .font(.system(size: 8.5))
                                        .foregroundStyle(document.status == .ready ? .green.opacity(0.7) : .orange.opacity(0.7))
                                }
                                Spacer()
                                Button {
                                    NSWorkspace.shared.open(URL(fileURLWithPath: document.localPath))
                                } label: { Image(systemName: "arrow.up.right.square") }
                                .buttonStyle(.borderless)
                                Button(role: .destructive) { store.delete(document.id) } label: {
                                    Image(systemName: "trash")
                                }
                                .buttonStyle(.borderless)
                            }
                            .padding(13)
                            .background(Color.white.opacity(0.045), in: RoundedRectangle(cornerRadius: 12))
                        }
                    }
                    .padding(.horizontal, 18)
                    .padding(.bottom, 18)
                }
            }
            .fileImporter(
                isPresented: $isImporterPresented,
                allowedContentTypes: [.plainText, .pdf, .text, .data],
                allowsMultipleSelection: true
            ) { result in
                if case .success(let urls) = result {
                    Task { await store.importFiles(urls) }
                }
            }
        }
    }
}

private struct DynamicAIPrivateVaultView: View {
    @ObservedObject var store: DynamicAIPrivateVaultStore
    @State private var title = ""
    @State private var content = ""

    var body: some View {
        DynamicAIManagementScaffold(title: "隐私空间", subtitle: "锁定时不显示标题、数量、搜索结果或内容。") {
            if store.isUnlocked {
                VStack(spacing: 0) {
                    HStack {
                        Text("已通过 Touch ID 解锁")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(.green.opacity(0.75))
                        Spacer()
                        Button("立即锁定") { store.lock() }.buttonStyle(.bordered)
                    }
                    .padding(16)
                    ScrollView {
                        VStack(spacing: 12) {
                            VStack(alignment: .leading, spacing: 8) {
                                TextField("标题", text: $title).textFieldStyle(.plain)
                                TextField("私密内容", text: $content, axis: .vertical)
                                    .textFieldStyle(.plain)
                                    .lineLimit(2...5)
                                HStack {
                                    Spacer()
                                    Button("保存到隐私空间") {
                                        store.add(title: title, content: content)
                                        title = ""
                                        content = ""
                                    }
                                    .buttonStyle(.borderedProminent)
                                    .tint(.orange.opacity(0.82))
                                }
                            }
                            .padding(13)
                            .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 12))

                            ForEach(store.items) { item in
                                HStack(alignment: .top) {
                                    VStack(alignment: .leading, spacing: 5) {
                                        Text(item.title).font(.system(size: 11, weight: .semibold))
                                        Text(item.content)
                                            .font(.system(size: 10))
                                            .foregroundStyle(.white.opacity(0.6))
                                            .textSelection(.enabled)
                                    }
                                    Spacer()
                                    Button(role: .destructive) { store.delete(item.id) } label: {
                                        Image(systemName: "trash")
                                    }
                                    .buttonStyle(.borderless)
                                }
                                .padding(13)
                                .background(Color.white.opacity(0.045), in: RoundedRectangle(cornerRadius: 12))
                            }
                        }
                        .padding(18)
                    }
                }
            } else {
                VStack(spacing: 18) {
                    Image(systemName: "lock.shield.fill")
                        .font(.system(size: 44))
                        .foregroundStyle(.orange.opacity(0.72))
                    Text("隐私内容已锁定")
                        .font(.system(size: 18, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white.opacity(0.9))
                    Text("解锁前不会显示任何内容摘要。窗口失焦后会自动重新锁定。")
                        .font(.system(size: 10))
                        .foregroundStyle(.white.opacity(0.4))
                    Button(store.biometryLabel) { Task { await store.unlock() } }
                        .buttonStyle(.borderedProminent)
                        .tint(.orange.opacity(0.82))
                    if let error = store.errorMessage {
                        Text(error).font(.system(size: 9)).foregroundStyle(.orange.opacity(0.8))
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }
}

private struct DynamicAIAuditView: View {
    @ObservedObject var store: DynamicAIAuditStore

    var body: some View {
        DynamicAIManagementScaffold(title: "调用记录", subtitle: "只记录模型、耗时和结果，不保存 API Key 或隐私正文。") {
            ScrollView {
                LazyVStack(spacing: 8) {
                    if store.records.isEmpty {
                        DynamicAIEmptyState(
                            icon: "list.bullet.clipboard",
                            title: "暂无调用记录",
                            detail: "完成一次模型对话后会在这里显示。"
                        )
                        .padding(.top, 90)
                    }
                    ForEach(store.records) { record in
                        HStack(spacing: 12) {
                            Circle()
                                .fill(record.outcome == "success" ? Color.green : Color.orange)
                                .frame(width: 7, height: 7)
                            VStack(alignment: .leading, spacing: 3) {
                                Text("\(record.provider) · \(record.model.isEmpty ? "默认模型" : record.model)")
                                    .font(.system(size: 10.5, weight: .semibold))
                                Text(record.startedAt.formatted(date: .abbreviated, time: .standard))
                                    .font(.system(size: 8.5))
                                    .foregroundStyle(.white.opacity(0.35))
                            }
                            Spacer()
                            Text(String(format: "%.1fs", record.duration))
                            Text(record.outcome)
                        }
                        .font(.system(size: 9.5))
                        .foregroundStyle(.white.opacity(0.68))
                        .padding(12)
                        .background(Color.white.opacity(0.045), in: RoundedRectangle(cornerRadius: 10))
                    }
                }
                .padding(18)
            }
        }
    }
}

private struct DynamicAIManagementScaffold<Content: View>: View {
    let title: String
    let subtitle: String
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.system(size: 16, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white.opacity(0.92))
                    Text(subtitle)
                        .font(.system(size: 9.5))
                        .foregroundStyle(.white.opacity(0.38))
                }
                Spacer()
            }
            .padding(.horizontal, 18)
            .frame(height: 62)
            .background(Color.black.opacity(0.14))
            Divider().overlay(Color.white.opacity(0.08))
            content().frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

private struct DynamicAIEmptyState: View {
    let icon: String
    let title: String
    let detail: String

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: icon).font(.system(size: 34)).foregroundStyle(.white.opacity(0.22))
            Text(title).font(.system(size: 13, weight: .semibold)).foregroundStyle(.white.opacity(0.7))
            Text(detail)
                .font(.system(size: 9.5))
                .foregroundStyle(.white.opacity(0.34))
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
    }
}

private struct DynamicAIConfigurationSheet: View {
    @ObservedObject var store: DynamicDifyChatStore
    @Environment(\.dismiss) private var dismiss
    @State private var provider: DynamicAIProvider
    @State private var baseURL: String
    @State private var model: String
    @State private var apiKey = ""
    @State private var isSaving = false

    init(store: DynamicDifyChatStore) {
        self.store = store
        _provider = State(initialValue: store.currentProvider)
        _baseURL = State(initialValue: store.apiBaseURLString)
        _model = State(initialValue: store.modelName)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("模型与连接")
                        .font(.system(size: 18, weight: .semibold, design: .rounded))
                    Text("API Key 仅保存在当前 Mac，不会写入项目或上传 GitHub。")
                        .font(.system(size: 9.5))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button { dismiss() } label: { Image(systemName: "xmark") }.buttonStyle(.plain)
            }

            Picker("服务", selection: $provider) {
                ForEach(DynamicAIProvider.allCases) { provider in
                    Text(provider.displayName).tag(provider)
                }
            }
            .onChange(of: provider) { _, newValue in
                baseURL = newValue.defaultBaseURL
                model = newValue.defaultModel
            }
            TextField("API Base URL", text: $baseURL)
            if provider.requiresModel { TextField("模型名称", text: $model) }
            SecureField(store.hasSavedAPIKey(for: provider) ? "留空则继续使用已保存 Key" : "API Key", text: $apiKey)

            if let error = store.errorMessage {
                Text(error).font(.system(size: 9.5)).foregroundStyle(.orange)
            }

            HStack {
                Button("移除当前配置", role: .destructive) { store.removeConfiguration() }
                Spacer()
                Button("取消") { dismiss() }
                Button(isSaving ? "正在连接" : "保存并连接") {
                    isSaving = true
                    Task {
                        let saved = await store.saveConfiguration(
                            provider: provider,
                            apiKey: apiKey,
                            baseURLString: baseURL,
                            modelName: model
                        )
                        isSaving = false
                        if saved { dismiss() }
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(isSaving)
            }
        }
        .padding(22)
        .frame(width: 520)
    }
}
