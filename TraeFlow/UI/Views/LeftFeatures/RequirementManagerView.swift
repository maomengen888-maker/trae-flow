import AppKit
import SwiftUI

struct RequirementManagerView: View {
    var onModalInteractionStateChanged: (Bool) -> Void = { _ in }
    @ObservedObject private var store = RequirementManagementStore.shared
    @State private var selectedStage: RequirementLifecycleStage = .prd
    @State private var isAddingRequirement = false
    @State private var newTitle = ""
    @State private var newDetails = ""
    @State private var newPriority = "中优先级"
    @State private var isChoosingDocuments = false
    @State private var documentPendingDeletion: RequirementDocument?
    @State private var isConfirmingDocumentDeletion = false

    var body: some View {
        HStack(spacing: 14) {
            requirementSidebar
                .frame(width: 220)

            if let requirement = store.selectedRequirement {
                requirementWorkspace(requirement)
            } else {
                ContentUnavailableView("暂无需求", systemImage: "doc.badge.plus")
            }
        }
        .padding(16)
        .background(DynamicVisualTheme.canvasGradient)
        .dynamicSurface(radius: DynamicVisualTheme.outerRadius, neonBorder: true)
        .sheet(isPresented: $isAddingRequirement) {
            addRequirementSheet
        }
        .onChange(of: isAddingRequirement) { _, isPresented in
            onModalInteractionStateChanged(isPresented)
        }
        .onDisappear {
            if isAddingRequirement {
                onModalInteractionStateChanged(false)
            }
        }
        .alert(
            "将文件移到废纸篓？",
            isPresented: $isConfirmingDocumentDeletion,
            presenting: documentPendingDeletion
        ) { document in
            Button("取消", role: .cancel) {
                documentPendingDeletion = nil
            }
            Button("移到废纸篓", role: .destructive) {
                if let requirementID = store.selectedRequirementID {
                    store.moveDocumentToTrash(document, requirementID: requirementID)
                }
                documentPendingDeletion = nil
            }
        } message: { document in
            Text("“\(document.name)”将从当前需求中移除，并放入 macOS 废纸篓，可在废纸篓中恢复。")
        }
        .onChange(of: store.selectedRequirementID) { _, _ in
            selectedStage = store.selectedRequirement?.currentStage ?? .prd
            store.clearStorageMessage()
        }
    }

    private var requirementSidebar: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("需求")
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                Spacer()
                Button {
                    isAddingRequirement = true
                } label: {
                    Image(systemName: "plus")
                }
                .buttonStyle(.plain)
                .foregroundStyle(DynamicVisualTheme.cyan)
            }
            .padding(.horizontal, 8)

            ScrollView {
                LazyVStack(spacing: 7) {
                    ForEach(store.requirements) { requirement in
                        Button {
                            store.selectedRequirementID = requirement.id
                            selectedStage = requirement.currentStage
                            store.clearStorageMessage()
                        } label: {
                            VStack(alignment: .leading, spacing: 6) {
                                Text(requirement.code)
                                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                                    .foregroundStyle(DynamicVisualTheme.cyan)
                                Text(requirement.title)
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundStyle(.white.opacity(0.92))
                                    .lineLimit(2)
                                HStack {
                                    Text(requirement.priority)
                                    Spacer()
                                    Text(requirement.isLaunched ? "已上线" : requirement.currentStage.title)
                                }
                                .font(.system(size: 9))
                                .foregroundStyle(.secondary)
                            }
                            .padding(10)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .dynamicSurface(
                                radius: DynamicVisualTheme.cardRadius,
                                focused: store.selectedRequirementID == requirement.id,
                                elevated: store.selectedRequirementID == requirement.id
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .padding(12)
        .dynamicSurface(radius: DynamicVisualTheme.panelRadius)
    }

    private func requirementWorkspace(_ requirement: ManagedRequirement) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 5) {
                    Text(requirement.code)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(DynamicVisualTheme.cyan)
                    Text(requirement.title)
                        .font(.system(size: 18, weight: .semibold, design: .rounded))
                    Text(requirement.details)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                Spacer()
                Text(requirement.isLaunched ? "已上线" : "\(requirement.currentStage.title)中")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(requirement.isLaunched ? Color.green : DynamicVisualTheme.cyan)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 5)
                    .background(Capsule().fill(Color.white.opacity(0.05)))
            }

            lifecycleBar(requirement)

            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(selectedStage.title)
                            .font(.system(size: 14, weight: .semibold))
                        Text(selectedStage.subtitle)
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button {
                        store.openRequirementFolder(requirementID: requirement.id)
                    } label: {
                        Label("打开文件夹", systemImage: "folder")
                    }
                    .buttonStyle(.bordered)

                    Button {
                        chooseDocuments(for: requirement, stage: selectedStage)
                    } label: {
                        Label(isChoosingDocuments ? "等待选择…" : "上传文档", systemImage: "arrow.up.doc")
                    }
                    .buttonStyle(.bordered)
                    .tint(DynamicVisualTheme.cyan)
                    .disabled(isChoosingDocuments)

                    if selectedStage == requirement.currentStage, !requirement.isLaunched {
                        Button(requirement.currentStage == .launch ? "确认上线" : "完成本阶段") {
                            store.advance(requirement.id)
                            selectedStage = store.selectedRequirement?.currentStage ?? selectedStage
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(DynamicVisualTheme.orange)
                    }
                }

                if let storageMessage = store.storageMessage {
                    Label(
                        storageMessage,
                        systemImage: store.storageMessageIsError
                            ? "exclamationmark.triangle.fill"
                            : "checkmark.circle.fill"
                    )
                    .font(.system(size: 10))
                    .foregroundStyle(store.storageMessageIsError ? Color.orange : Color.green)
                    .lineLimit(3)
                    .textSelection(.enabled)
                }

                let documents = requirement.documents
                    .filter { $0.stage == selectedStage }
                    .sorted { $0.uploadedAt > $1.uploadedAt }
                HStack(spacing: 7) {
                    Text("文档名称")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.84))
                    Text("\(documents.count)")
                        .font(.system(size: 9, weight: .medium, design: .rounded))
                        .foregroundStyle(DynamicVisualTheme.cyan)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(DynamicVisualTheme.cyan.opacity(0.12)))
                    Spacer()
                }

                if documents.isEmpty {
                    VStack(spacing: 8) {
                        Image(systemName: "arrow.up.doc")
                            .font(.system(size: 25, weight: .light))
                            .foregroundStyle(DynamicVisualTheme.cyan.opacity(0.7))
                        Text("该阶段还没有文档")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                        if !requirement.documents.isEmpty {
                            Text("其他阶段已有 \(requirement.documents.count) 个文档，可点击上方阶段查看文件名")
                                .font(.system(size: 9))
                                .foregroundStyle(.secondary.opacity(0.75))
                        } else {
                            Text("上传后将在这里显示完整文档名")
                                .font(.system(size: 9))
                                .foregroundStyle(.secondary.opacity(0.75))
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ScrollView {
                        LazyVStack(spacing: 7) {
                            ForEach(documents) { document in
                                HStack(spacing: 6) {
                                    Button {
                                        store.openDocument(document)
                                    } label: {
                                        HStack(spacing: 10) {
                                            Image(systemName: documentIcon(for: document.name))
                                                .foregroundStyle(DynamicVisualTheme.cyan)
                                                .frame(width: 18)
                                            VStack(alignment: .leading, spacing: 3) {
                                                Text(document.name)
                                                    .font(.system(size: 12, weight: .semibold))
                                                    .foregroundStyle(.white.opacity(0.9))
                                                    .lineLimit(2)
                                                    .truncationMode(.middle)
                                                Text("\(document.stage.title) · \(document.uploadedAt.formatted(date: .abbreviated, time: .shortened))")
                                                    .font(.system(size: 9))
                                                    .foregroundStyle(.secondary)
                                            }
                                            Spacer()
                                            Image(systemName: "arrow.up.forward.app")
                                                .foregroundStyle(.secondary)
                                        }
                                        .contentShape(Rectangle())
                                    }
                                    .buttonStyle(.plain)

                                    Button {
                                        documentPendingDeletion = document
                                        isConfirmingDocumentDeletion = true
                                    } label: {
                                        Image(systemName: "trash")
                                            .font(.system(size: 11, weight: .semibold))
                                            .foregroundStyle(Color.red.opacity(0.88))
                                            .frame(width: 30, height: 30)
                                            .background(Color.red.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
                                    }
                                    .buttonStyle(.plain)
                                    .help("删除文件")
                                }
                                .padding(8)
                                .dynamicSurface(radius: DynamicVisualTheme.cardRadius, elevated: true)
                            }
                        }
                    }
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .dynamicSurface(radius: DynamicVisualTheme.panelRadius)
        }
        .padding(16)
        .dynamicSurface(radius: DynamicVisualTheme.panelRadius)
    }

    private func lifecycleBar(_ requirement: ManagedRequirement) -> some View {
        HStack(spacing: 8) {
            ForEach(RequirementLifecycleStage.allCases) { stage in
                let complete = requirement.isLaunched || stage.index < requirement.currentStage.index
                let current = !requirement.isLaunched && stage == requirement.currentStage
                Button {
                    selectedStage = stage
                    store.clearStorageMessage()
                } label: {
                    VStack(alignment: .leading, spacing: 7) {
                        HStack {
                            Image(systemName: stage.systemImage)
                            Spacer()
                            Text(String(format: "%02d", stage.index + 1))
                                .font(.system(size: 9, design: .monospaced))
                        }
                        Text(stage.title)
                            .font(.system(size: 11, weight: .medium))
                        Text(complete ? "已完成" : (current ? "进行中" : "待开始"))
                            .font(.system(size: 9))
                            .foregroundStyle(complete ? Color.green : (current ? DynamicVisualTheme.cyan : Color.secondary))
                    }
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .dynamicSurface(
                        radius: DynamicVisualTheme.cardRadius,
                        focused: selectedStage == stage,
                        elevated: selectedStage == stage
                    )
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var addRequirementSheet: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("新建需求")
                .font(.title2.bold())
            TextField("需求名称", text: $newTitle)
            TextField("需求说明", text: $newDetails, axis: .vertical)
                .lineLimit(3...6)
            Picker("优先级", selection: $newPriority) {
                Text("高优先级").tag("高优先级")
                Text("中优先级").tag("中优先级")
                Text("低优先级").tag("低优先级")
            }
            HStack {
                Spacer()
                Button("取消") { isAddingRequirement = false }
                Button("创建并进入 PRD") {
                    if store.addRequirement(title: newTitle, details: newDetails, priority: newPriority) {
                        selectedStage = .prd
                        newTitle = ""
                        newDetails = ""
                        newPriority = "中优先级"
                        isAddingRequirement = false
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(newTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(22)
        .frame(width: 460)
        .background(DynamicVisualTheme.canvasGradient)
        .dynamicSurface(radius: DynamicVisualTheme.outerRadius, neonBorder: true)
    }

    private func chooseDocuments(for requirement: ManagedRequirement, stage: RequirementLifecycleStage) {
        guard !isChoosingDocuments,
              store.prepareRequirementFolder(requirementID: requirement.id) != nil else { return }

        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = true
        panel.prompt = "上传"
        panel.message = "选择要保存到「\(requirement.title) / \(stage.title)」的文件"
        panel.level = NSWindow.Level(rawValue: 200)
        isChoosingDocuments = true
        NSApp.activate(ignoringOtherApps: true)

        // Dynamic 主窗口层级较高，使用非阻塞式选择器避免弹窗被压在后面造成“卡死”错觉。
        panel.begin { response in
            Task { @MainActor in
                isChoosingDocuments = false
                guard response == .OK else { return }
                store.importDocuments(panel.urls, requirementID: requirement.id, stage: stage)
            }
        }
    }

    private func documentIcon(for fileName: String) -> String {
        switch URL(fileURLWithPath: fileName).pathExtension.lowercased() {
        case "pdf":
            return "doc.richtext.fill"
        case "doc", "docx", "pages", "txt", "md":
            return "doc.text.fill"
        case "png", "jpg", "jpeg", "gif", "webp", "svg":
            return "photo.fill"
        case "ppt", "pptx", "key":
            return "rectangle.on.rectangle.angled"
        case "xls", "xlsx", "csv", "numbers":
            return "tablecells.fill"
        default:
            return "doc.fill"
        }
    }
}
