import AppKit
import Combine
import Foundation

struct InstalledApplication: Identifiable, Equatable {
    let id: String
    let name: String
    let url: URL
    let bundleIdentifier: String?
    let version: String?
}

@MainActor
final class InstalledApplicationStore: ObservableObject {
    static let shared = InstalledApplicationStore()

    @Published private(set) var applications: [InstalledApplication] = []

    private let defaults: UserDefaults
    private let hiddenPathsKey = "dynamicHiddenApplicationPaths"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        refresh()
    }

    func refresh() {
        let hiddenPaths = Set(defaults.stringArray(forKey: hiddenPathsKey) ?? [])
        let fileManager = FileManager.default
        let roots = [
            URL(fileURLWithPath: "/Applications", isDirectory: true),
            URL(fileURLWithPath: "/System/Applications", isDirectory: true),
            fileManager.homeDirectoryForCurrentUser.appendingPathComponent("Applications", isDirectory: true)
        ]

        var discovered: [InstalledApplication] = []
        var seen = Set<String>()

        for root in roots where fileManager.fileExists(atPath: root.path) {
            guard let enumerator = fileManager.enumerator(
                at: root,
                includingPropertiesForKeys: [.isDirectoryKey, .isPackageKey],
                options: [.skipsHiddenFiles, .skipsPackageDescendants]
            ) else { continue }

            for case let url as URL in enumerator where url.pathExtension.lowercased() == "app" {
                let path = url.standardizedFileURL.path
                guard !hiddenPaths.contains(path), seen.insert(path).inserted else { continue }

                let bundle = Bundle(url: url)
                let displayName = (bundle?.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String)
                    ?? (bundle?.object(forInfoDictionaryKey: "CFBundleName") as? String)
                    ?? url.deletingPathExtension().lastPathComponent
                let version = (bundle?.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String)
                    ?? (bundle?.object(forInfoDictionaryKey: "CFBundleVersion") as? String)

                discovered.append(InstalledApplication(
                    id: path,
                    name: displayName,
                    url: url,
                    bundleIdentifier: bundle?.bundleIdentifier,
                    version: version
                ))
            }
        }

        applications = discovered.sorted {
            $0.name.localizedStandardCompare($1.name) == .orderedAscending
        }
    }

    func open(_ application: InstalledApplication) {
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        NSWorkspace.shared.openApplication(at: application.url, configuration: configuration) { _, _ in }
    }

    /// “删除”仅从 Dynamic 的列表隐藏，不修改真实 App 文件。
    func hide(_ application: InstalledApplication) {
        var hiddenPaths = Set(defaults.stringArray(forKey: hiddenPathsKey) ?? [])
        hiddenPaths.insert(application.url.standardizedFileURL.path)
        defaults.set(Array(hiddenPaths).sorted(), forKey: hiddenPathsKey)
        applications.removeAll { $0.id == application.id }
    }
}
