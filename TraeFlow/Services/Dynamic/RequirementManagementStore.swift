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

    var directoryName: String {
        switch self {
        case .prd: return "01-需求PRD"
        case .prototype: return "02-原型文档"
        case .acceptance: return "03-测试验收"
        case .launch: return "04-上线"
        }
    }
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
    @Published private(set) var storageMessage: String?
    @Published private(set) var storageMessageIsError = false

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
        ensureFolderStructuresForExistingRequirements()
        selectedRequirementID = requirements.first?.id
    }

    var selectedRequirement: ManagedRequirement? {
        guard let selectedRequirementID else { return requirements.first }
        return requirements.first { $0.id == selectedRequirementID } ?? requirements.first
    }

    @discardableResult
    func addRequirement(title: String, details: String, priority: String) -> Bool {
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

        do {
            let folderURL = try createFolderStructure(for: item)
            setStorageMessage("已创建需求文件夹：\(folderURL.lastPathComponent)")
        } catch {
            setStorageError("需求文件夹创建失败：\(error.localizedDescription)")
            return false
        }

        requirements.insert(item, at: 0)
        selectedRequirementID = item.id
        persist()
        return true
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

    @discardableResult
    func prepareRequirementFolder(requirementID: String) -> URL? {
        guard let requirement = requirements.first(where: { $0.id == requirementID }) else {
            setStorageError("找不到该需求，无法创建文件夹")
            return nil
        }
        do {
            let folderURL = try createFolderStructure(for: requirement)
            return folderURL
        } catch {
            setStorageError("需求文件夹创建失败：\(error.localizedDescription)")
            return nil
        }
    }

    func importDocuments(_ sourceURLs: [URL], requirementID: String, stage: RequirementLifecycleStage) {
        guard let index = requirements.firstIndex(where: { $0.id == requirementID }) else {
            setStorageError("找不到该需求，无法保存文件")
            return
        }

        let requirement = requirements[index]
        let destinationDirectory: URL
        do {
            destinationDirectory = try createFolderStructure(for: requirement)
                .appendingPathComponent(stage.directoryName, isDirectory: true)
        } catch {
            setStorageError("需求文件夹创建失败：\(error.localizedDescription)")
            return
        }

        var importedCount = 0
        var failedNames: [String] = []

        for sourceURL in sourceURLs {
            let didAccessSecurityScopedResource = sourceURL.startAccessingSecurityScopedResource()
            defer {
                if didAccessSecurityScopedResource {
                    sourceURL.stopAccessingSecurityScopedResource()
                }
            }

            let destinationURL = availableDestinationURL(
                for: sourceURL.lastPathComponent,
                in: destinationDirectory
            )
            do {
                try FileManager.default.copyItem(at: sourceURL, to: destinationURL)
                requirements[index].documents.append(RequirementDocument(
                    id: UUID().uuidString,
                    stage: stage,
                    name: sourceURL.lastPathComponent,
                    storedPath: destinationURL.path,
                    uploadedAt: Date()
                ))
                importedCount += 1
            } catch {
                failedNames.append(sourceURL.lastPathComponent)
            }
        }

        if importedCount > 0 {
            requirements[index].updatedAt = Date()
            persist()
        }

        if failedNames.isEmpty {
            setStorageMessage("已将 \(importedCount) 个文件保存到「\(stage.title)」文件夹")
        } else if importedCount > 0 {
            setStorageError("已保存 \(importedCount) 个文件，\(failedNames.count) 个文件保存失败")
        } else {
            setStorageError("文件保存失败，请检查文件访问权限")
        }
    }

    func openDocument(_ document: RequirementDocument) {
        NSWorkspace.shared.open(URL(fileURLWithPath: document.storedPath))
    }

    func openRequirementFolder(requirementID: String) {
        guard let folderURL = prepareRequirementFolder(requirementID: requirementID) else { return }
        NSWorkspace.shared.open(folderURL)
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

    private func ensureFolderStructuresForExistingRequirements() {
        for requirement in requirements {
            do {
                _ = try createFolderStructure(for: requirement)
            } catch {
                NSLog("[Dynamic] 需求文件夹创建失败: \(error.localizedDescription)")
            }
        }
    }

    private func createFolderStructure(for requirement: ManagedRequirement) throws -> URL {
        let requirementDirectory = Self.documentsRootURL.appendingPathComponent(
            requirementDirectoryName(for: requirement),
            isDirectory: true
        )
        try FileManager.default.createDirectory(
            at: requirementDirectory,
            withIntermediateDirectories: true
        )
        for stage in RequirementLifecycleStage.allCases {
            try FileManager.default.createDirectory(
                at: requirementDirectory.appendingPathComponent(stage.directoryName, isDirectory: true),
                withIntermediateDirectories: true
            )
        }
        return requirementDirectory
    }

    private func requirementDirectoryName(for requirement: ManagedRequirement) -> String {
        let invalidCharacters = CharacterSet(charactersIn: "/:\\?%*|\"<>")
            .union(.newlines)
            .union(.controlCharacters)
        let cleanedTitle = requirement.title
            .components(separatedBy: invalidCharacters)
            .joined(separator: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let readableTitle = cleanedTitle.isEmpty ? "未命名需求" : String(cleanedTitle.prefix(48))
        return "\(requirement.code)-\(readableTitle)-\(requirement.id.prefix(8))"
    }

    private func availableDestinationURL(for fileName: String, in directory: URL) -> URL {
        let fileManager = FileManager.default
        let originalURL = directory.appendingPathComponent(fileName)
        guard fileManager.fileExists(atPath: originalURL.path) else { return originalURL }

        let fileExtension = originalURL.pathExtension
        let baseName = originalURL.deletingPathExtension().lastPathComponent
        var copyNumber = 2
        while true {
            let candidateName = fileExtension.isEmpty
                ? "\(baseName)-\(copyNumber)"
                : "\(baseName)-\(copyNumber).\(fileExtension)"
            let candidateURL = directory.appendingPathComponent(candidateName)
            if !fileManager.fileExists(atPath: candidateURL.path) {
                return candidateURL
            }
            copyNumber += 1
        }
    }

    private func setStorageMessage(_ message: String) {
        storageMessage = message
        storageMessageIsError = false
    }

    private func setStorageError(_ message: String) {
        storageMessage = message
        storageMessageIsError = true
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
