import AppKit
import Combine
import SwiftUI

@MainActor
final class DynamicScreenshotManager: ObservableObject {
    static let shared = DynamicScreenshotManager()

    @Published private(set) var latestScreenshotURL: URL?
    @Published private(set) var latestImage: NSImage?
    @Published private(set) var isCapturing = false
    @Published private(set) var isPinned = false
    @Published private(set) var errorMessage: String?

    private var pinnedWindowController: DynamicPinnedScreenshotWindowController?
    private var notificationObserver: NSObjectProtocol?

    private init() {
        notificationObserver = NotificationCenter.default.addObserver(
            forName: .dynamicCaptureScreenshot,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.captureInteractive() }
        }
    }

    func captureInteractive() {
        guard !isCapturing else { return }
        isCapturing = true
        errorMessage = nil

        // 先收起 Dynamic 主界面并暂时隐藏置顶截图，避免挡住系统的区域选择层。
        NotificationCenter.default.post(name: .traeFlowCollapseLeftExpanded, object: nil)
        let shouldRestorePinnedWindow = isPinned
        pinnedWindowController?.window?.orderOut(nil)

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in
            self?.startRegionCapture(shouldRestorePinnedWindow: shouldRestorePinnedWindow)
        }
    }

    private func startRegionCapture(shouldRestorePinnedWindow: Bool) {
        guard isCapturing else { return }

        let directory = BridgeRuntimePaths.runtimeDirectoryURL
            .appendingPathComponent("screenshots", isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        } catch {
            isCapturing = false
            errorMessage = "无法创建截图目录"
            return
        }

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        let destination = directory.appendingPathComponent("Dynamic-\(formatter.string(from: Date())).png")

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
        // 显示 macOS 截图选择工具栏，并默认进入区域选择模式。
        // 用户可在工具栏切换区域、窗口或全屏截图，Esc 取消。
        process.arguments = ["-i", "-U", "-Jselection", "-x", destination.path]
        process.terminationHandler = { [weak self] process in
            Task { @MainActor in
                guard let self else { return }
                self.isCapturing = false
                guard process.terminationStatus == 0,
                      FileManager.default.fileExists(atPath: destination.path),
                      let image = NSImage(contentsOf: destination) else {
                    if shouldRestorePinnedWindow,
                       let previousImage = self.latestImage {
                        self.showPinnedWindow(image: previousImage)
                    }
                    return
                }
                self.latestScreenshotURL = destination
                self.latestImage = image
                if self.isPinned {
                    self.showPinnedWindow(image: image)
                }
            }
        }

        do {
            try process.run()
        } catch {
            isCapturing = false
            errorMessage = "无法启动系统截图工具"
        }
    }

    func togglePinned() {
        guard let image = latestImage else { return }
        if isPinned {
            pinnedWindowController?.close()
            pinnedWindowController = nil
            isPinned = false
        } else {
            isPinned = true
            showPinnedWindow(image: image)
        }
    }

    func revealLatestScreenshot() {
        guard let latestScreenshotURL else { return }
        NSWorkspace.shared.activateFileViewerSelecting([latestScreenshotURL])
    }

    private func showPinnedWindow(image: NSImage) {
        if let controller = pinnedWindowController {
            controller.update(image: image)
            controller.showWindow(nil)
            controller.window?.makeKeyAndOrderFront(nil)
            return
        }

        let controller = DynamicPinnedScreenshotWindowController(image: image) { [weak self] in
            self?.pinnedWindowController = nil
            self?.isPinned = false
        }
        pinnedWindowController = controller
        controller.showWindow(nil)
        controller.window?.makeKeyAndOrderFront(nil)
    }
}

@MainActor
private final class DynamicPinnedScreenshotWindowController: NSWindowController, NSWindowDelegate {
    private let hostingView: NSHostingView<DynamicPinnedScreenshotView>
    private let onClose: () -> Void

    init(image: NSImage, onClose: @escaping () -> Void) {
        self.hostingView = NSHostingView(rootView: DynamicPinnedScreenshotView(image: image))
        self.onClose = onClose
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 560, height: 380),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .utilityWindow],
            backing: .buffered,
            defer: false
        )
        panel.title = "Dynamic 截图置顶"
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isReleasedWhenClosed = false
        panel.contentView = hostingView
        panel.center()
        super.init(window: panel)
        panel.delegate = self
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func update(image: NSImage) {
        hostingView.rootView = DynamicPinnedScreenshotView(image: image)
    }

    func windowWillClose(_ notification: Notification) {
        onClose()
    }
}

private struct DynamicPinnedScreenshotView: View {
    let image: NSImage

    var body: some View {
        ZStack {
            Color(red: 0.015, green: 0.025, blue: 0.045)
            Image(nsImage: image)
                .resizable()
                .scaledToFit()
                .padding(10)
        }
        .ignoresSafeArea()
    }
}
