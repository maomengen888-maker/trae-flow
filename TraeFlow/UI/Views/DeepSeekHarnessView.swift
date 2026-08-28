import AppKit
import Combine
import Foundation
import SwiftUI
import WebKit

@MainActor
final class DeepSeekHarnessManager: ObservableObject {
    enum Phase: Equatable {
        case idle
        case starting
        case running
        case failed(String)
    }

    static let shared = DeepSeekHarnessManager()
    static let serverURL = URL(string: "http://127.0.0.1:3080")!

    @Published private(set) var phase: Phase = .idle
    @Published private(set) var recentLog = ""

    private var process: Process?
    private var readinessTask: Task<Void, Never>?
    private var ownsRunningProcess = false

    private init() {}

    var statusText: String {
        switch phase {
        case .idle: return "尚未启动"
        case .starting: return "正在启动官方 Harness…"
        case .running: return "本地服务已连接"
        case .failed: return "启动失败"
        }
    }

    func start() {
        guard phase != .starting, phase != .running else { return }
        readinessTask?.cancel()
        readinessTask = Task { [weak self] in
            await self?.startAndWaitUntilReady()
        }
    }

    func retry() {
        stop()
        start()
    }

    func stop() {
        readinessTask?.cancel()
        readinessTask = nil
        if ownsRunningProcess, let process, process.isRunning {
            process.terminate()
        }
        process = nil
        ownsRunningProcess = false
        phase = .idle
    }

    private func startAndWaitUntilReady() async {
        if await serverIsReachable() {
            ownsRunningProcess = false
            phase = .running
            return
        }

        guard let npxURL = resolvedNPXURL() else {
            phase = .failed("未找到 Node.js / npx。请先安装 Node.js，再重试。")
            return
        }

        do {
            let workingDirectory = BridgeRuntimePaths.runtimeDirectoryURL
                .appendingPathComponent("deepseek-harness", isDirectory: true)
            try FileManager.default.createDirectory(
                at: workingDirectory,
                withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o700]
            )

            recentLog = ""
            phase = .starting

            let process = Process()
            process.executableURL = npxURL
            process.arguments = [
                "-y", "@deepseek-ai/dsh", "web",
                "--host", "127.0.0.1",
                "--port", "3080",
                "--no-open"
            ]
            process.currentDirectoryURL = workingDirectory

            var environment = Foundation.ProcessInfo.processInfo.environment
            let executableDirectory = npxURL.deletingLastPathComponent().path
            let currentPath = environment["PATH"] ?? ""
            environment["PATH"] = ([executableDirectory, "/opt/homebrew/bin", "/usr/local/bin", "/usr/bin", "/bin", currentPath])
                .filter { !$0.isEmpty }
                .joined(separator: ":")
            environment["NO_COLOR"] = "1"
            environment["BROWSER"] = "none"
            process.environment = environment

            let outputPipe = Pipe()
            process.standardOutput = outputPipe
            process.standardError = outputPipe
            outputPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
                let data = handle.availableData
                guard !data.isEmpty, let text = String(data: data, encoding: .utf8) else { return }
                Task { @MainActor [weak self] in
                    self?.appendLog(text)
                }
            }
            process.terminationHandler = { [weak self] finishedProcess in
                outputPipe.fileHandleForReading.readabilityHandler = nil
                Task { @MainActor [weak self] in
                    guard let self, self.process === finishedProcess else { return }
                    self.process = nil
                    self.ownsRunningProcess = false
                    if case .idle = self.phase { return }
                    let detail = self.recentLog.trimmingCharacters(in: .whitespacesAndNewlines)
                    self.phase = .failed(detail.isEmpty
                        ? "Harness 进程已退出（代码 \(finishedProcess.terminationStatus)）。"
                        : String(detail.suffix(1200)))
                }
            }

            try process.run()
            self.process = process
            ownsRunningProcess = true

            for _ in 0..<240 {
                try Task.checkCancellation()
                if await serverIsReachable() {
                    phase = .running
                    return
                }
                if !process.isRunning {
                    let detail = recentLog.trimmingCharacters(in: .whitespacesAndNewlines)
                    phase = .failed(detail.isEmpty ? "Harness 进程未能启动。" : String(detail.suffix(1200)))
                    return
                }
                try await Task.sleep(for: .milliseconds(500))
            }

            phase = .failed("启动超时。请检查网络后重试，首次下载官方包可能需要更长时间。")
        } catch is CancellationError {
            return
        } catch {
            phase = .failed(error.localizedDescription)
        }
    }

    private func serverIsReachable() async -> Bool {
        var request = URLRequest(url: Self.serverURL)
        request.timeoutInterval = 1.5
        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            guard let response = response as? HTTPURLResponse else { return false }
            return (200..<500).contains(response.statusCode)
        } catch {
            return false
        }
    }

    private func resolvedNPXURL() -> URL? {
        let candidates = [
            "/opt/homebrew/bin/npx",
            "/usr/local/bin/npx",
            "/usr/bin/npx"
        ]
        return candidates
            .map { URL(fileURLWithPath: $0) }
            .first { FileManager.default.isExecutableFile(atPath: $0.path) }
    }

    private func appendLog(_ text: String) {
        recentLog.append(text)
        if recentLog.count > 8_000 {
            recentLog = String(recentLog.suffix(8_000))
        }
    }
}

struct DeepSeekHarnessView: View {
    @ObservedObject private var manager = DeepSeekHarnessManager.shared

    var body: some View {
        Group {
            switch manager.phase {
            case .running:
                harnessWorkspace
            case .idle:
                launchState(
                    icon: "shippingbox.fill",
                    title: "DeepSeek 官方 Harness",
                    description: "在简屿的 AI 界面内启动官方 Web UI，统一管理模型、工作区、插件、工具与操作审批。",
                    buttonTitle: "启动官方 Harness",
                    action: manager.start
                )
            case .starting:
                launchState(
                    icon: "arrow.triangle.2.circlepath",
                    title: "正在准备 Harness",
                    description: "首次使用会通过 npx 下载 DeepSeek 官方包，之后启动会更快。",
                    buttonTitle: nil,
                    action: nil
                )
            case .failed(let message):
                launchState(
                    icon: "exclamationmark.triangle.fill",
                    title: "Harness 启动失败",
                    description: message,
                    buttonTitle: "重试",
                    action: manager.retry
                )
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(red: 0.035, green: 0.038, blue: 0.047))
    }

    private var harnessWorkspace: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Circle().fill(Color.green).frame(width: 6, height: 6)
                Text("DeepSeek Harness 已连接")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.white.opacity(0.62))
                Text("官方开发者预览")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.orange)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(Color.orange.opacity(0.12), in: Capsule())
                Spacer()
                Button {
                    NSWorkspace.shared.open(DeepSeekHarnessManager.serverURL)
                } label: {
                    Label("在浏览器打开", systemImage: "arrow.up.right.square")
                        .font(.system(size: 9, weight: .medium))
                }
                .buttonStyle(.plain)
                .foregroundStyle(.white.opacity(0.52))
                Button {
                    manager.retry()
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.plain)
                .foregroundStyle(.white.opacity(0.52))
                .help("重启 Harness")
            }
            .padding(.horizontal, 14)
            .frame(height: 38)
            .background(Color.black.opacity(0.18))

            DeepSeekHarnessWebView(url: DeepSeekHarnessManager.serverURL)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func launchState(
        icon: String,
        title: String,
        description: String,
        buttonTitle: String?,
        action: (() -> Void)?
    ) -> some View {
        VStack(spacing: 18) {
            ZStack {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Color.white.opacity(0.07))
                Image(systemName: icon)
                    .font(.system(size: 28, weight: .medium))
                    .foregroundStyle(.white.opacity(0.88))
            }
            .frame(width: 72, height: 72)

            VStack(spacing: 8) {
                Text(title)
                    .font(.system(size: 20, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.94))
                Text(description)
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.48))
                    .multilineTextAlignment(.center)
                    .lineLimit(5)
                    .frame(maxWidth: 520)
                    .textSelection(.enabled)
            }

            if case .starting = manager.phase {
                ProgressView().controlSize(.small)
            }
            if let buttonTitle, let action {
                Button(buttonTitle, action: action)
                    .buttonStyle(.borderedProminent)
                    .tint(.white)
                    .foregroundStyle(.black)
            }

            Text("官方 Harness 可读写你在其界面中选择的工作区，并会在执行敏感操作前请求审批。")
                .font(.system(size: 9))
                .foregroundStyle(.white.opacity(0.28))
                .multilineTextAlignment(.center)
        }
        .padding(36)
    }
}

private struct DeepSeekHarnessWebView: NSViewRepresentable {
    let url: URL

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .default()
        configuration.preferences.setValue(true, forKey: "developerExtrasEnabled")
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        webView.uiDelegate = context.coordinator
        webView.allowsBackForwardNavigationGestures = true
        webView.setValue(false, forKey: "drawsBackground")
        webView.load(URLRequest(url: url))
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        guard webView.url == nil else { return }
        webView.load(URLRequest(url: url))
    }

    final class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate {
        func webView(
            _ webView: WKWebView,
            decidePolicyFor navigationAction: WKNavigationAction,
            decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
        ) {
            guard let url = navigationAction.request.url else {
                decisionHandler(.cancel)
                return
            }
            let host = url.host?.lowercased()
            if url.scheme == "about" || host == "127.0.0.1" || host == "localhost" {
                decisionHandler(.allow)
                return
            }
            if navigationAction.navigationType == .linkActivated,
               let scheme = url.scheme?.lowercased(), ["http", "https"].contains(scheme) {
                NSWorkspace.shared.open(url)
            }
            decisionHandler(.cancel)
        }

        func webView(
            _ webView: WKWebView,
            createWebViewWith configuration: WKWebViewConfiguration,
            for navigationAction: WKNavigationAction,
            windowFeatures: WKWindowFeatures
        ) -> WKWebView? {
            if let url = navigationAction.request.url {
                NSWorkspace.shared.open(url)
            }
            return nil
        }
    }
}
