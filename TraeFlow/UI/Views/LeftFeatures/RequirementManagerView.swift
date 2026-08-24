import AppKit
import SwiftUI

struct RequirementManagerView: View {
    @ObservedObject private var store = RequirementManagementStore.shared
    @State private var selectedStage: RequirementLifecycleStage = .prd
    @State private var isAddingRequirement = false
    @State private var newTitle = ""
    @State private var newDetails = ""
    @State private var newPriority = "中优先级"

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
        .background(dynamicBackground)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .sheet(isPresented: $isAddingRequirement) {
            addRequirementSheet
        }
        .onChange(of: store.selectedRequirementID) { _, _ in
            selectedStage = store.selectedRequirement?.currentStage ?? .prd
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
                .foregroundStyle(.cyan)
            }
            .padding(.horizontal, 8)

            ScrollView {
                LazyVStack(spacing: 7) {
                    ForEach(store.requirements) { requirement in
                        Button {
                            store.selectedRequirementID = requirement.id
                            selectedStage = requirement.currentStage
                        } label: {
                            VStack(alignment: .leading, spacing: 6) {
                                Text(requirement.code)
                                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                                    .foregroundStyle(.cyan)
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
                            .background(
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .fill(store.selectedRequirementID == requirement.id
                                          ? Color.cyan.opacity(0.13)
                                          : Color.white.opacity(0.035))
                                    .overlay {
                                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                                            .strokeBorder(
                                                store.selectedRequirementID == requirement.id
                                                    ? Color.cyan.opacity(0.36)
                                                    : Color.white.opacity(0.06),
                                                lineWidth: 1
                                            )
                                    }
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .padding(12)
        .background(panelBackground)
        .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
    }

    private func requirementWorkspace(_ requirement: ManagedRequirement) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 5) {
                    Text(requirement.code)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(.cyan)
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
                    .foregroundStyle(requirement.isLaunched ? Color.green : Color.cyan)
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
                    Button("上传文档") {
                        chooseDocuments(for: requirement, stage: selectedStage)
                    }
                    .buttonStyle(.bordered)
                    .tint(.cyan)

                    if selectedStage == requirement.currentStage, !requirement.isLaunched {
                        Button(requirement.currentStage == .launch ? "确认上线" : "完成本阶段") {
                            store.advance(requirement.id)
                            selectedStage = store.selectedRequirement?.currentStage ?? selectedStage
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.cyan)
                    }
                }

                let documents = requirement.documents.filter { $0.stage == selectedStage }
                if documents.isEmpty {
                    VStack(spacing: 8) {
                        Image(systemName: "arrow.up.doc")
                            .font(.system(size: 25, weight: .light))
                            .foregroundStyle(.cyan.opacity(0.7))
                        Text("还没有上传文档")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ScrollView {
                        LazyVStack(spacing: 7) {
                            ForEach(documents) { document in
                                Button {
                                    store.openDocument(document)
                                } label: {
                                    HStack(spacing: 10) {
                                        Image(systemName: "doc.fill")
                                            .foregroundStyle(.cyan)
                                        VStack(alignment: .leading, spacing: 3) {
                                            Text(document.name)
                                                .font(.system(size: 11, weight: .medium))
                                                .foregroundStyle(.white.opacity(0.9))
                                            Text(document.uploadedAt.formatted(date: .abbreviated, time: .shortened))
                                                .font(.system(size: 9))
                                                .foregroundStyle(.secondary)
                                        }
                                        Spacer()
                                        Image(systemName: "arrow.up.forward.app")
                                            .foregroundStyle(.secondary)
                                    }
                                    .padding(10)
                                    .background(Color.white.opacity(0.035), in: RoundedRectangle(cornerRadius: 9))
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .background(panelBackground)
            .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
        }
        .padding(16)
        .background(panelBackground)
        .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
    }

    private func lifecycleBar(_ requirement: ManagedRequirement) -> some View {
        HStack(spacing: 8) {
            ForEach(RequirementLifecycleStage.allCases) { stage in
                let complete = requirement.isLaunched || stage.index < requirement.currentStage.index
                let current = !requirement.isLaunched && stage == requirement.currentStage
                Button {
                    selectedStage = stage
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
                            .foregroundStyle(complete ? Color.green : (current ? Color.cyan : Color.secondary))
                    }
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(selectedStage == stage ? Color.cyan.opacity(0.12) : Color.white.opacity(0.03))
                            .overlay {
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .strokeBorder(selectedStage == stage ? Color.cyan.opacity(0.38) : Color.white.opacity(0.06))
                            }
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
                    store.addRequirement(title: newTitle, details: newDetails, priority: newPriority)
                    selectedStage = .prd
                    newTitle = ""
                    newDetails = ""
                    newPriority = "中优先级"
                    isAddingRequirement = false
                }
                .buttonStyle(.borderedProminent)
                .disabled(newTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(22)
        .frame(width: 460)
    }

    private func chooseDocuments(for requirement: ManagedRequirement, stage: RequirementLifecycleStage) {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = true
        panel.prompt = "上传"
        guard panel.runModal() == .OK else { return }
        store.importDocuments(panel.urls, requirementID: requirement.id, stage: stage)
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
