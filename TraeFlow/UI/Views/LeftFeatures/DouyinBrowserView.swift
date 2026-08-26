import AppKit
import Combine
import SwiftUI
import WebKit

/// Dynamic 内的抖音窗口页，并提供独立、可移动、默认置顶的悬浮小窗。
struct DouyinBrowserView: View {
    @ObservedObject private var floatingWindow = DouyinFloatingWindowController.shared

    private static let homeURL = URL(string: "https://www.douyin.com/")!

    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "play.rectangle.fill")
                    .foregroundStyle(.white)
                VStack(alignment: .leading, spacing: 1) {
                    Text("抖音")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.9))
                    Text(floatingWindow.isPresented ? "悬浮小窗已打开" : "窗口模式")
                        .font(.system(size: 9))
                        .foregroundStyle(.white.opacity(0.4))
                }
                Spacer()
                Button {
                    openFloatingWindow()
                } label: {
                    Label(
                        floatingWindow.isPresented ? "显示小窗" : "小窗播放",
                        systemImage: "pip.enter"
                    )
                    .font(.system(size: 10, weight: .semibold))
                    .padding(.horizontal, 10)
                    .frame(height: 28)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.white.opacity(0.9))
                .background(Color.white.opacity(0.09), in: Capsule())
                .overlay(Capsule().strokeBorder(Color.white.opacity(0.12)))
                .help("打开可移动、默认置顶的抖音悬浮小窗")
            }
            .padding(.horizontal, 12)
            .frame(height: 38)
            .background(Color.white.opacity(0.035), in: RoundedRectangle(cornerRadius: 8))

            CustomAreaWebView(
                source: .douyin(Self.homeURL, prefersMobileLayout: false),
                keepsAlive: true
            )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .onAppear {
            setMainPlaybackSuspended(false)
        }
        .onDisappear {
            setMainPlaybackSuspended(true)
        }
    }

    private func openFloatingWindow() {
        let cachedWebView = CustomAreaWebViewCache.shared.webView(for: Self.homeURL)
        let currentURL = cachedWebView?.url ?? Self.homeURL
        let targetScreen = cachedWebView?.window?.screen
            ?? NSScreen.screens.first(where: { NSMouseInRect(NSEvent.mouseLocation, $0.frame, false) })
            ?? NSScreen.main
        if let cachedWebView {
            Self.pausePlayback(cachedWebView)
        }
        floatingWindow.show(url: currentURL, on: targetScreen)
    }

    private func setMainPlaybackSuspended(_ suspended: Bool) {
        guard let webView = CustomAreaWebViewCache.shared.webView(for: Self.homeURL) else { return }
        if suspended {
            Self.pausePlayback(webView)
        }
        webView.setAllMediaPlaybackSuspended(suspended) {}
    }

    private static func pausePlayback(_ webView: WKWebView) {
        webView.evaluateJavaScript(
            "document.querySelectorAll('video, audio').forEach(function(media) { media.pause(); });"
        )
        webView.pauseAllMediaPlayback {}
    }
}

/// 单例窗口控制器确保无论点击多少次都只存在一个抖音小窗。
@MainActor
final class DouyinFloatingWindowController: NSObject, ObservableObject, NSWindowDelegate {
    static let shared = DouyinFloatingWindowController()
    /// Dynamic 主面板打开时使用 rawValue 151；小窗必须再高一级才不会被主界面遮挡。
    private static let alwaysOnTopLevel = NSWindow.Level(rawValue: NotchPanel.compactLevel.rawValue + 1)

    @Published private(set) var isPresented = false
    @Published private(set) var isAlwaysOnTop = true

    private var panel: NSPanel?

    private override init() {
        super.init()
    }

    func show(url: URL, on screen: NSScreen?) {
        if let panel {
            positionAtRightEdge(panel, on: screen ?? panel.screen)
            panel.makeKeyAndOrderFront(nil)
            panel.orderFrontRegardless()
            return
        }

        isAlwaysOnTop = true
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 430, height: 720),
            styleMask: [.titled, .closable, .resizable, .utilityWindow],
            backing: .buffered,
            defer: false
        )
        panel.title = "抖音小窗 · 始终置顶"
        panel.level = Self.alwaysOnTopLevel
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.isMovableByWindowBackground = true
        panel.minSize = NSSize(width: 340, height: 520)
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.delegate = self
        panel.contentViewController = NSHostingController(
            rootView: DouyinFloatingContentView(initialURL: url, controller: self)
        )
        positionAtRightEdge(panel, on: screen)

        self.panel = panel
        isPresented = true
        panel.makeKeyAndOrderFront(nil)
        panel.orderFrontRegardless()
    }

    func toggleAlwaysOnTop() {
        isAlwaysOnTop.toggle()
        panel?.level = isAlwaysOnTop ? Self.alwaysOnTopLevel : .normal
        panel?.title = isAlwaysOnTop ? "抖音小窗 · 始终置顶" : "抖音小窗"
        if isAlwaysOnTop, let panel {
            panel.orderFrontRegardless()
        }
    }

    private func positionAtRightEdge(_ panel: NSPanel, on screen: NSScreen?) {
        guard let visibleFrame = (screen ?? NSScreen.main)?.visibleFrame else {
            panel.center()
            return
        }
        let margin: CGFloat = 14
        var frame = panel.frame
        frame.size.width = min(frame.width, max(340, visibleFrame.width - margin * 2))
        frame.size.height = min(frame.height, max(520, visibleFrame.height - margin * 2))
        frame.origin.x = visibleFrame.maxX - frame.width - margin
        frame.origin.y = visibleFrame.maxY - frame.height - margin
        panel.setFrame(frame, display: true)
    }

    func pauseFloatingPlayback() {
        guard let contentView = panel?.contentView else { return }
        webViews(in: contentView).forEach { webView in
            webView.evaluateJavaScript(
                "document.querySelectorAll('video, audio').forEach(function(media) { media.pause(); });"
            )
            webView.pauseAllMediaPlayback {}
            webView.setAllMediaPlaybackSuspended(true) {}
        }
    }

    private func webViews(in view: NSView) -> [WKWebView] {
        let current = (view as? WKWebView).map { [$0] } ?? []
        return current + view.subviews.flatMap(webViews(in:))
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        pauseFloatingPlayback()
        return true
    }

    func windowWillClose(_ notification: Notification) {
        pauseFloatingPlayback()
        isPresented = false
        panel?.contentViewController = nil
        panel = nil
    }
}

private struct DouyinFloatingContentView: View {
    let initialURL: URL
    @ObservedObject var controller: DouyinFloatingWindowController

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 7) {
                Image(systemName: "play.rectangle.fill")
                    .foregroundStyle(.white.opacity(0.82))
                Text("抖音悬浮播放")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.82))
                Spacer()
                Button {
                    controller.toggleAlwaysOnTop()
                } label: {
                    Label(
                        controller.isAlwaysOnTop ? "已置顶" : "置顶",
                        systemImage: controller.isAlwaysOnTop ? "pin.fill" : "pin"
                    )
                    .font(.system(size: 9, weight: .medium))
                }
                .buttonStyle(.plain)
                .foregroundStyle(controller.isAlwaysOnTop ? Color.cyan : Color.white.opacity(0.6))
                .help(controller.isAlwaysOnTop ? "点击取消始终置顶" : "点击保持窗口置顶")
            }
            .padding(.horizontal, 10)
            .frame(height: 34)
            .background(Color(red: 0.035, green: 0.038, blue: 0.047))

            // 小窗恢复桌面站点：由抖音网页自身接收滚轮/触控板事件切换推荐视频。
            // 移动 UA 会落到“打开 App”的单视频页，无法形成可上下滑动的视频流。
            CustomAreaWebView(source: .douyin(initialURL, prefersMobileLayout: false))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(Color.black)
        .onDisappear {
            controller.pauseFloatingPlayback()
        }
    }
}
