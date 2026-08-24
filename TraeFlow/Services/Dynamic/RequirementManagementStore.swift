import AppKit
import Combine
import Foundation

enum RequirementLifecycleStage: String, Codable, CaseIterable, Identifiable {
    case prd
    case prototype
    case acceptance
    case launch

    var id: String { rawValue }

    var title: String {
        switch self {
        case .prd: return "需求 PRD"
        case .prototype: return "原型文档"
        case .acceptance: return "测试验收"
        case .launch: return "上线"
        }
    }

    var subtitle: String {
        switch self {
        case .prd: return "需求说明、业务规则与评审结论"
        case .prototype: return "交互原型、页面流程与视觉说明"
        case .acceptance: return "测试用例、验收记录与问题清单"
        case .launch: return "发布说明、上线计划与回滚方案"
        }
    }

    var systemImage: String {
        switch self {
        case .prd: return "doc.text.fill"
        case .prototype: return "point.3.filled.connected.trianglepath.dotted"
        case .acceptance: return "checkmark.seal.fill"
        case .launch: return "rocket.fill"
        }
    }

    var index: Int { Self.allCases.firstIndex(of: self) ?? 0 }
}

struct RequirementDocument: Codable, Identifiable, Equatable {
    let id: String
    let stage: RequirementLifecycleStage
    let name: String
    let storedPath: String
    let uploadedAt: Date
}

struct ManagedRequirement: Codable, Identifiable, Equatable {
    let id: String
    var code: String
    var title: String
    var details: String
    var priority: String
    var currentStage: RequirementLifecycleStage
    var isLaunched: Bool
    var documents: [RequirementDocument]
    let createdAt: Date
    var updatedAt: Date
}

@MainActor
final class RequirementManagementStore: ObservableObject {
    static let shared = RequirementManagementStore()

    @Published private(set) var requirements: [ManagedRequirement] = []
    @Published var selectedRequirementID: String?

    private static var persistenceURL: URL {
        BridgeRuntimePaths.runtimeDirectoryURL.appendingPathComponent("dynamic-requirements.json")
    }

    private static var documentsRootURL: URL {
        BridgeRuntimePaths.runtimeDirectoryURL.appendingPathComponent("requirements", isDirectory: true)
    }

    init() {
        load()
        if requirements.isEmpty {
            seedInitialRequirement()
        }
        selectedRequirementID = requirements.first?.id
    }

    var selectedRequirement: ManagedRequirement? {
        guard let selectedRequirementID else { return requirements.first }
        return requirements.first { $0.id == selectedRequirementID } ?? requirements.first
    }

    func addRequirement(title: String, details: String, priority: String) {
        let sequence = (requirements.compactMap { Int($0.code.replacingOccurrences(of: "REQ-", with: "")) }.max() ?? 0) + 1
        let item = ManagedRequirement(
            id: UUID().uuidString,
            code: String(format: "REQ-%03d", sequence),
            title: title,
            details: details,
            priority: priority,
            currentStage: .prd,
            isLaunched: false,
            documents: [],
            createdAt: Date(),
            updatedAt: Date()
        )
        requirements.insert(item, at: 0)
        selectedRequirementID = item.id
        persist()
    }

    func advance(_ requirementID: String) {
        guard let index = requirements.firstIndex(where: { $0.id == requirementID }) else { return }
        let current = requirements[index].currentStage
        if current == .launch {
            requirements[index].isLaunched = true
        } else if let next = RequirementLifecycleStage.allCases.first(where: { $0.index == current.index + 1 }) {
            requirements[index].currentStage = next
        }
        requirements[index].updatedAt = Date()
        persist()
    }

    func importDocuments(_ sourceURLs: [URL], requirementID: String, stage: RequirementLifecycleStage) {
        guard let index = requirements.firstIndex(where: { $0.id == requirementID }) else { return }
        let destinationDirectory = Self.documentsRootURL
            .appendingPathComponent(requirementID, isDirectory: true)
            .appendingPathComponent(stage.rawValue, isDirectory: true)

        do {
            try FileManager.default.createDirectory(at: destinationDirectory, withIntermediateDirectories: true)
        } catch {
            return
        }

        for sourceURL in sourceURLs {
            let destinationName = "\(UUID().uuidString.prefix(8))-\(sourceURL.lastPathComponent)"
            let destinationURL = destinationDirectory.appendingPathComponent(destinationName)
            do {
                try FileManager.default.copyItem(at: sourceURL, to: destinationURL)
                requirements[index].documents.append(RequirementDocument(
                    id: UUID().uuidString,
                    stage: stage,
                    name: sourceURL.lastPathComponent,
                    storedPath: destinationURL.path,
                    uploadedAt: Date()
                ))
            } catch {
                continue
            }
        }
        requirements[index].updatedAt = Date()
        persist()
    }

    func openDocument(_ document: RequirementDocument) {
        NSWorkspace.shared.open(URL(fileURLWithPath: document.storedPath))
    }

    private func load() {
        guard let data = try? Data(contentsOf: Self.persistenceURL),
              let decoded = try? JSONDecoder().decode([ManagedRequirement].self, from: data) else {
            requirements = []
            return
        }
        requirements = decoded.sorted { $0.updatedAt > $1.updatedAt }
    }

    private func persist() {
        do {
            try FileManager.default.createDirectory(
                at: Self.persistenceURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let data = try JSONEncoder().encode(requirements)
            try data.write(to: Self.persistenceURL, options: [.atomic])
        } catch {
            NSLog("[Dynamic] 需求数据保存失败: \(error.localizedDescription)")
        }
    }

    private func seedInitialRequirement() {
        requirements = [ManagedRequirement(
            id: UUID().uuidString,
            code: "REQ-001",
            title: "我的第一个需求",
            details: "从 PRD、原型、测试验收到上线，集中管理所有阶段文档。",
            priority: "中优先级",
            currentStage: .prd,
            isLaunched: false,
            documents: [],
            createdAt: Date(),
            updatedAt: Date()
        )]
        persist()
    }
}
