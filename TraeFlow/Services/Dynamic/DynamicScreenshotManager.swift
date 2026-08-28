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
    @Published private(set) var latestUploadURL: URL?
    @Published private(set) var isUploading = false
    @Published private(set) var uploadMessage: String?

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
        let destination = directory.appendingPathComponent("简屿-\(formatter.string(from: Date())).png")

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
                self.latestUploadURL = nil
                self.uploadMessage = nil
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

    /// 按 screenshot-upload skill 的流程显式上传图床；绝不在截图完成后自动上传。
    /// 已上传时再次点击只复制现有链接，避免重复产生云端副本。
    func uploadOrCopyLatestScreenshot() {
        guard !isUploading else { return }

        if let latestUploadURL {
            copyToPasteboard(latestUploadURL.absoluteString)
            uploadMessage = "图片链接已复制"
            return
        }

        guard let latestScreenshotURL else { return }
        isUploading = true
        uploadMessage = "正在上传…"

        Task { [weak self] in
            guard let self else { return }
            do {
                let remoteURL = try await Self.uploadImage(at: latestScreenshotURL)
                self.latestUploadURL = remoteURL
                self.copyToPasteboard(remoteURL.absoluteString)
                self.uploadMessage = "上传成功，链接已复制"
            } catch {
                self.uploadMessage = "上传失败：\(error.localizedDescription)"
            }
            self.isUploading = false
        }
    }

    private func copyToPasteboard(_ value: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(value, forType: .string)
    }

    private static func uploadImage(at fileURL: URL) async throws -> URL {
        let userAgent = [
            "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 Chrome/124.0 Safari/537.36",
            "Mozilla/5.0 (Macintosh; Apple Silicon Mac OS X 14_5) AppleWebKit/605.1.15 Safari/605.1.15"
        ].randomElement()!

        var tokenRequest = URLRequest(url: URL(string: "https://imgloc.com/upload.php?action=token")!)
        tokenRequest.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        tokenRequest.timeoutInterval = 12

        let (tokenData, tokenResponse) = try await URLSession.shared.data(for: tokenRequest)
        guard let httpTokenResponse = tokenResponse as? HTTPURLResponse,
              200..<300 ~= httpTokenResponse.statusCode,
              let tokenJSON = try JSONSerialization.jsonObject(with: tokenData) as? [String: Any],
              tokenJSON["ok"] as? Bool == true,
              let token = tokenJSON["token"] as? String else {
            throw DynamicScreenshotUploadError("无法获取上传凭证")
        }

        let imageData = try Data(contentsOf: fileURL)
        let boundary = "DynamicBoundary-\(UUID().uuidString)"
        var body = Data()
        body.appendMultipart("--\(boundary)\r\n")
        body.appendMultipart("Content-Disposition: form-data; name=\"token\"\r\n\r\n")
        body.appendMultipart("\(token)\r\n")
        body.appendMultipart("--\(boundary)\r\n")
        body.appendMultipart("Content-Disposition: form-data; name=\"image\"; filename=\"简屿.png\"\r\n")
        body.appendMultipart("Content-Type: image/png\r\n\r\n")
        body.append(imageData)
        body.appendMultipart("\r\n--\(boundary)--\r\n")

        var uploadRequest = URLRequest(url: URL(string: "https://imgloc.com/upload.php")!)
        uploadRequest.httpMethod = "POST"
        uploadRequest.httpBody = body
        uploadRequest.timeoutInterval = 35
        uploadRequest.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        uploadRequest.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        let (responseData, response) = try await URLSession.shared.data(for: uploadRequest)
        guard let httpResponse = response as? HTTPURLResponse,
              200..<300 ~= httpResponse.statusCode,
              let responseJSON = try JSONSerialization.jsonObject(with: responseData) as? [String: Any],
              responseJSON["ok"] as? Bool == true,
              let urlString = responseJSON["url"] as? String,
              let remoteURL = URL(string: urlString) else {
            throw DynamicScreenshotUploadError("图床没有返回有效链接")
        }
        return remoteURL
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

private struct DynamicScreenshotUploadError: LocalizedError {
    let message: String

    init(_ message: String) {
        self.message = message
    }

    var errorDescription: String? { message }
}

private extension Data {
    mutating func appendMultipart(_ string: String) {
        if let data = string.data(using: .utf8) {
            append(data)
        }
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
        panel.title = "简屿截图置顶"
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
