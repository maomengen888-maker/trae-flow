import AppKit
import Combine
import SwiftUI
import WebKit

/// Spec: 实现 WKWebView 包装组件，支持加载本地文件目录并正确处理相对路径资源
/// Spec: 实现安全策略：限制 WebView 网络/JS 能力，防止加载外部资源带来的风险
/// Spec: 支持 JS Bridge —— HTML 通过 `window.webkit.messageHandlers.traeFlowHint.postMessage(...)`
/// 向紧凑态 Flow 岛推送提示文本，由 `CustomAreaHintStore` 接收并自动超时清除。
/// Spec: 支持双内容源（本地自定义区域目录 / 远程 URL），按源选择 `loadFileURL` 或 `load(URLRequest)`。
struct CustomAreaWebView: NSViewRepresentable {
    /// 抖音网页版使用桌面 Chrome 标识，避免被站点误判为移动端后只展示“打开 App”。
    static let douyinDesktopUserAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36"
    /// 抖音悬浮小窗使用 iPhone Safari 标识；抖音移动布局仍由 www.douyin.com 提供。
    static let douyinMobileUserAgent = "Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Mobile/15E148 Safari/604.1"
    /// 在文档加载最早阶段固定手机 viewport，并在直播/video 节点出现后滚动到画面中心。
    static let douyinMobileLayoutScript = """
    (function () {
        var dynamicWheelLocked = false;
        var dynamicUserNavigated = false;

        function ensureViewport() {
            var viewport = document.querySelector('meta[name="viewport"]');
            if (!viewport) {
                viewport = document.createElement('meta');
                viewport.name = 'viewport';
                (document.head || document.documentElement).appendChild(viewport);
            }
            viewport.content = 'width=device-width, initial-scale=1, maximum-scale=1, viewport-fit=cover';
        }

        function applyMobileLayout() {
            ensureViewport();
            document.documentElement.style.setProperty('width', '100%', 'important');
            document.documentElement.style.setProperty('max-width', '100vw', 'important');
            document.documentElement.style.setProperty('overflow-x', 'hidden', 'important');
            if (document.body) {
                document.body.style.setProperty('width', '100%', 'important');
                document.body.style.setProperty('max-width', '100vw', 'important');
                document.body.style.setProperty('min-width', '0', 'important');
                document.body.style.setProperty('overflow-x', 'hidden', 'important');
                document.body.style.setProperty('background', '#000', 'important');
            }
            var videos = Array.from(document.querySelectorAll('video'));
            var bestVideo = null;
            var bestScore = -1;
            videos.forEach(function (video) {
                video.style.setProperty('max-width', '100vw', 'important');
                video.style.setProperty('max-height', '100vh', 'important');
                video.style.setProperty('object-fit', 'contain', 'important');
                var rect = video.getBoundingClientRect();
                var visibleWidth = Math.max(0, Math.min(rect.right, innerWidth) - Math.max(rect.left, 0));
                var visibleHeight = Math.max(0, Math.min(rect.bottom, innerHeight) - Math.max(rect.top, 0));
                var score = (visibleWidth * visibleHeight) + (video.paused ? 0 : 1000000000);
                if (score > bestScore) { bestScore = score; bestVideo = video; }
            });
            if (!dynamicUserNavigated && bestVideo && !bestVideo.dataset.dynamicMobileCentered) {
                bestVideo.dataset.dynamicMobileCentered = '1';
                setTimeout(function () {
                    bestVideo.scrollIntoView({ block: 'center', inline: 'center', behavior: 'auto' });
                }, 120);
            }
        }

        function visibleVideos() {
            return Array.from(document.querySelectorAll('video')).filter(function (video) {
                var rect = video.getBoundingClientRect();
                return rect.width > 40 && rect.height > 80;
            });
        }

        function currentVideoIndex(videos) {
            var centerY = innerHeight / 2;
            var bestIndex = 0;
            var bestDistance = Infinity;
            videos.forEach(function (video, index) {
                var rect = video.getBoundingClientRect();
                var distance = Math.abs((rect.top + rect.bottom) / 2 - centerY);
                if (!video.paused) { distance -= 100000; }
                if (distance < bestDistance) {
                    bestDistance = distance;
                    bestIndex = index;
                }
            });
            return bestIndex;
        }

        function swipePage(direction) {
            var target = document.elementFromPoint(innerWidth / 2, innerHeight / 2) || document.body;
            var startY = direction > 0 ? innerHeight * 0.76 : innerHeight * 0.24;
            var endY = direction > 0 ? innerHeight * 0.24 : innerHeight * 0.76;
            try {
                if (typeof Touch === 'function' && typeof TouchEvent === 'function') {
                    var startTouch = new Touch({ identifier: Date.now(), target: target, clientX: innerWidth / 2, clientY: startY });
                    target.dispatchEvent(new TouchEvent('touchstart', { touches: [startTouch], targetTouches: [startTouch], changedTouches: [startTouch], bubbles: true, cancelable: true }));
                    var endTouch = new Touch({ identifier: startTouch.identifier, target: target, clientX: innerWidth / 2, clientY: endY });
                    target.dispatchEvent(new TouchEvent('touchmove', { touches: [endTouch], targetTouches: [endTouch], changedTouches: [endTouch], bubbles: true, cancelable: true }));
                    target.dispatchEvent(new TouchEvent('touchend', { touches: [], targetTouches: [], changedTouches: [endTouch], bubbles: true, cancelable: true }));
                }
            } catch (_) {}
            var key = direction > 0 ? 'ArrowDown' : 'ArrowUp';
            target.dispatchEvent(new KeyboardEvent('keydown', { key: key, code: key, bubbles: true }));
            target.dispatchEvent(new KeyboardEvent('keyup', { key: key, code: key, bubbles: true }));
        }

        function moveByVideo(direction) {
            var videos = visibleVideos();
            if (videos.length > 1) {
                var index = currentVideoIndex(videos);
                var nextIndex = Math.max(0, Math.min(videos.length - 1, index + direction));
                if (nextIndex !== index) {
                    videos[nextIndex].scrollIntoView({ block: 'center', inline: 'center', behavior: 'smooth' });
                    setTimeout(function () { videos[nextIndex].play().catch(function () {}); }, 240);
                    return;
                }
            }
            swipePage(direction);
        }

        window.addEventListener('wheel', function (event) {
            if (Math.abs(event.deltaY) < 12 || dynamicWheelLocked) { return; }
            event.preventDefault();
            event.stopImmediatePropagation();
            dynamicUserNavigated = true;
            dynamicWheelLocked = true;
            moveByVideo(event.deltaY > 0 ? 1 : -1);
            setTimeout(function () { dynamicWheelLocked = false; }, 620);
        }, { passive: false, capture: true });

        ensureViewport();
        document.addEventListener('DOMContentLoaded', applyMobileLayout, { once: true });
        new MutationObserver(applyMobileLayout).observe(document.documentElement, { childList: true, subtree: true });
        setTimeout(applyMobileLayout, 500);
    })();
    """
    /// JS Bridge 消息处理器名称 —— HTML 端通过 `window.webkit.messageHandlers.traeFlowHint` 调用
    static let hintMessageHandlerName = "traeFlowHint"
    /// JS Bridge 系统指标消息处理器 —— HTML 端通过 `window.webkit.messageHandlers.traeFlowMetrics` 请求指标
    static let metricsMessageHandlerName = "traeFlowMetrics"
    /// JS Bridge 收起展开面板处理器 —— HTML 端通过 `window.webkit.messageHandlers.traeFlowCollapse.postMessage(...)` 收起 Flow 岛展开面板
    static let collapseMessageHandlerName = "traeFlowCollapse"
    /// JS Bridge 在 TRAE 中打开编辑处理器 —— HTML 端通过 `window.webkit.messageHandlers.traeFlowOpenInTrae.postMessage(...)`
    /// 触发以当前自定义区域目录为工作区在指定 TRAE 变体（默认 TRAE CN）中打开，便于用户直接编辑 HTML 源文件。
    static let openInTraeMessageHandlerName = "traeFlowOpenInTrae"

    /// Spec: network-block-injection —— 当 `allowsNetworkAccess == false` 时注入的 JS 脚本，
    /// 拦截 `window.fetch` 与 `XMLHttpRequest`，使其立即 reject（抛出 "网络访问已被禁用" 错误）。
    /// 原因：fetch/XHR 不触发 `decidePolicyFor navigationAction`，仅靠 navigation delegate
    /// 无法拦截 JS 发起的网络请求；必须在 atDocumentStart 注入脚本从源头阻断。
    /// 保留 `traeFlowMetrics` / `traeFlowHint` / `traeFlowCollapse` / `traeFlowOpenInTrae` 消息通道（用于 JS Bridge）。
    static let networkBlockScript = """
    (function () {
      var blockedMsg = "网络访问已被禁用（未开启允许请求外部接口）";
      var allowedHosts = ["messageHandlers.traeFlowHint", "messageHandlers.traeFlowMetrics", "messageHandlers.traeFlowCollapse", "messageHandlers.traeFlowOpenInTrae"];
      function isAllowed(url) {
        try {
          var u = new URL(url, location.href);
          // 允许 file: / trae-flow-local: 本地资源
          return u.protocol === "file:" || u.protocol === "trae-flow-local:";
        } catch (e) { return false; }
      }
      // 拦截 fetch
      if (window.fetch) {
        var origFetch = window.fetch;
        window.fetch = function (input, init) {
          var url = typeof input === "string" ? input : (input && input.url) || "";
          if (isAllowed(url)) return origFetch.apply(this, arguments);
          return Promise.reject(new TypeError(blockedMsg));
        };
      }
      // 拦截 XMLHttpRequest
      if (window.XMLHttpRequest) {
        var origOpen = XMLHttpRequest.prototype.open;
        XMLHttpRequest.prototype.open = function (method, url) {
          if (!isAllowed(url)) {
            this._traeFlowBlocked = true;
            this._traeFlowBlockedMsg = blockedMsg;
          }
          return origOpen.apply(this, arguments);
        };
        var origSend = XMLHttpRequest.prototype.send;
        XMLHttpRequest.prototype.send = function () {
          if (this._traeFlowBlocked) {
            Object.defineProperty(this, "status", { value: 0 });
            Object.defineProperty(this, "readyState", { value: 4 });
            if (typeof this.onerror === "function") {
              var self = this;
              setTimeout(function () { self.onerror(new Event("error")); }, 0);
            }
            return;
          }
          return origSend.apply(this, arguments);
        };
      }
      // 拦截 Navigator.sendBeacon
      if (navigator.sendBeacon) {
        navigator.sendBeacon = function (url) {
          if (isAllowed(url)) return true;
          return false;
        };
      }
    })();
    """

    /// Spec: network-block-content-rule-list —— WKContentRuleList 标识符
    /// 用于在 `WKContentRuleListStore` 中编译/获取网络拦截规则（block 所有 http/https 请求）。
    private static let networkBlockRuleListIdentifier = "ai.traeflow.app.networkBlock"

    /// Spec: network-block-content-rule-list —— 规则 JSON：block 所有 http/https 请求
    /// `file:` / `trae-flow-local:` 协议不在 url-filter 范围内，本地资源不受影响。
    /// WKContentRuleList 在 WebKit 网络层拦截，JS 无法绕过（含 fetch / XHR / 资源加载）。
    private static let networkBlockRuleListJSON = """
    [{"trigger":{"url-filter":"https?://.*"},"action":{"type":"block"}}]
    """

    /// Spec: scrollbar-style-injection —— 为本地自定义区域 HTML 注入深色半透明滚动条样式，
    /// 避免 WebKit 在透明背景下显示与 Flow Island 深色主题不协调的浅色系统滚动条。
    static let scrollbarStyleScript = """
    (function () {
        var css = `
            html { color-scheme: dark; }
            ::-webkit-scrollbar { width: 8px; height: 8px; }
            ::-webkit-scrollbar-track { background: transparent; }
            ::-webkit-scrollbar-thumb { background: rgba(255,255,255,0.22); border-radius: 4px; }
            ::-webkit-scrollbar-thumb:hover { background: rgba(255,255,255,0.35); }
            ::-webkit-scrollbar-corner { background: transparent; }
        `;
        var style = document.createElement("style");
        style.textContent = css;
        (document.head || document.documentElement).appendChild(style);
    })();
    """

    /// Dynamic 专用 Dify Agent 视觉层。仅注入 `.dynamicAgent`，不修改远端应用逻辑。
    static let dynamicAgentStyleScript = """
    (function () {
        var styleID = "dynamic-agent-future-theme";
        var css = `
            :root { color-scheme: dark; --dynamic-cyan: #35E6FF; --dynamic-blue: #2775FF; }
            html, body, #__next {
                background: radial-gradient(circle at 78% 5%, rgba(39,117,255,.16), transparent 32%),
                            radial-gradient(circle at 12% 92%, rgba(53,230,255,.10), transparent 28%),
                            #050914 !important;
                color: #EAFBFF !important;
                font-family: -apple-system, BlinkMacSystemFont, "SF Pro Display", "PingFang SC", sans-serif !important;
            }
            body::before {
                content: ""; position: fixed; inset: 0; pointer-events: none; z-index: 9999;
                background-image: linear-gradient(rgba(53,230,255,.025) 1px, transparent 1px),
                                  linear-gradient(90deg, rgba(53,230,255,.025) 1px, transparent 1px);
                background-size: 28px 28px;
                mask-image: linear-gradient(to bottom, rgba(0,0,0,.55), transparent 80%);
            }
            * { scrollbar-width: thin; scrollbar-color: rgba(53,230,255,.32) transparent; }
            ::-webkit-scrollbar { width: 7px; height: 7px; }
            ::-webkit-scrollbar-track { background: transparent; }
            ::-webkit-scrollbar-thumb { background: rgba(53,230,255,.30); border-radius: 8px; }
            ::-webkit-scrollbar-thumb:hover { background: rgba(53,230,255,.52); }

            [class*="bg-white"], [class*="bg-gray-50"], [class*="bg-gray-100"],
            [class*="bg-slate-50"], [class*="bg-slate-100"] {
                background-color: rgba(8,16,33,.86) !important;
                backdrop-filter: blur(22px) saturate(135%);
            }
            [class*="border-gray"], [class*="border-slate"] {
                border-color: rgba(53,230,255,.16) !important;
            }
            [class*="text-gray-900"], [class*="text-gray-800"], [class*="text-slate-900"] {
                color: #F1FCFF !important;
            }
            [class*="text-gray-700"], [class*="text-gray-600"], [class*="text-slate-600"] {
                color: rgba(218,246,255,.78) !important;
            }
            [class*="text-gray-500"], [class*="text-gray-400"] {
                color: rgba(190,226,238,.58) !important;
            }
            [class*="shadow"] { box-shadow: 0 18px 55px rgba(0,0,0,.32) !important; }

            aside, nav {
                background: linear-gradient(180deg, rgba(8,18,38,.96), rgba(5,12,26,.92)) !important;
                border-color: rgba(53,230,255,.13) !important;
            }
            button {
                transition: transform .18s ease, border-color .18s ease, background-color .18s ease, box-shadow .18s ease !important;
            }
            button:not(:disabled):hover {
                transform: translateY(-1px);
                border-color: rgba(53,230,255,.42) !important;
                box-shadow: 0 8px 24px rgba(39,117,255,.16) !important;
            }
            textarea, input, [contenteditable="true"], [role="textbox"] {
                color: #F3FDFF !important;
                caret-color: var(--dynamic-cyan) !important;
            }
            textarea::placeholder, input::placeholder { color: rgba(187,222,234,.46) !important; }
            form:has(textarea), form:has([contenteditable="true"]), form:has([role="textbox"]) {
                background: linear-gradient(135deg, rgba(11,24,49,.96), rgba(7,16,34,.98)) !important;
                border: 1px solid rgba(53,230,255,.22) !important;
                border-radius: 18px !important;
                box-shadow: 0 14px 38px rgba(0,0,0,.36), inset 0 1px 0 rgba(255,255,255,.04) !important;
            }
            form:has(textarea):focus-within, form:has([contenteditable="true"]):focus-within,
            form:has([role="textbox"]):focus-within {
                border-color: rgba(53,230,255,.62) !important;
                box-shadow: 0 0 0 3px rgba(53,230,255,.08), 0 18px 45px rgba(0,0,0,.42) !important;
            }
            .markdown-body, [class*="markdown"] { color: rgba(235,250,255,.92) !important; line-height: 1.72 !important; }
            pre, code { background: rgba(2,8,18,.78) !important; border-color: rgba(53,230,255,.13) !important; }
            a { color: #69E9FF !important; }
            ::selection { background: rgba(53,230,255,.30); color: #FFFFFF; }
        `;

        function applyTheme() {
            if (!document.getElementById(styleID)) {
                var style = document.createElement("style");
                style.id = styleID;
                style.textContent = css;
                (document.head || document.documentElement).appendChild(style);
            }
            document.querySelectorAll("body *").forEach(function (element) {
                var text = (element.textContent || "").replace(/\\s+/g, " ").trim().toUpperCase();
                if ((text === "POWERED BY DIFY" || text === "POWERED BY") && element.children.length < 4) {
                    element.style.opacity = "0.28";
                    element.style.filter = "grayscale(1)";
                }
            });
        }

        applyTheme();
        new MutationObserver(applyTheme).observe(document.documentElement, { childList: true, subtree: true });
    })();
    """

    /// Spec: network-block-content-rule-list —— 内存缓存的 WKContentRuleList
    /// 首次获取后缓存，避免每次创建 WebView 都触发 store I/O。
    private static var cachedNetworkBlockRule: WKContentRuleList?
    private static let cachedNetworkBlockRuleLock = NSLock()

    /// Spec: network-block-content-rule-list —— 获取网络拦截规则
    /// 优先从内存缓存取，其次从 `WKContentRuleListStore` 读取已编译的，不存在则编译。
    /// `WKContentRuleListStore` 是 `@MainActor`，completion 在主线程回调。
    static func loadNetworkBlockRule(completion: @escaping (WKContentRuleList?) -> Void) {
        cachedNetworkBlockRuleLock.lock()
        if let cached = cachedNetworkBlockRule {
            cachedNetworkBlockRuleLock.unlock()
            completion(cached)
            return
        }
        cachedNetworkBlockRuleLock.unlock()

        guard let store = WKContentRuleListStore.default() else {
            completion(nil)
            return
        }

        Task { @MainActor in
            // 先尝试读取已编译的
            var ruleList = try? await store.contentRuleList(forIdentifier: networkBlockRuleListIdentifier)
            if ruleList == nil {
                // 不存在，编译并持久化（下次启动可直接读取）
                ruleList = try? await store.compileContentRuleList(
                    forIdentifier: networkBlockRuleListIdentifier,
                    encodedContentRuleList: networkBlockRuleListJSON
                )
            }
            if let ruleList = ruleList {
                cachedNetworkBlockRuleLock.lock()
                cachedNetworkBlockRule = ruleList
                cachedNetworkBlockRuleLock.unlock()
            }
            completion(ruleList)
        }
    }

    /// WebView 内容源
    enum ContentSource: Equatable {
        /// 本地自定义区域目录
        case localArea(CustomArea)
        /// 远程 URL
        case remoteURL(URL)
        /// Dynamic 内嵌 Dify Agent（远程 URL + 专属未来科技主题）
        case dynamicAgent(URL)
        /// Dynamic 内嵌抖音网页版（共享 Cookie、允许媒体播放与站内登录跳转）
        case douyin(URL, prefersMobileLayout: Bool)
        /// Mineradio 网页（注入 Bridge 兼容层 + JSC 引擎）
        /// Spec: mineradio-bridge-compat-layer
        case mineradio(URL)

        /// 关联的区域（仅 .localArea 有值）
        var area: CustomArea? {
            if case .localArea(let area) = self { return area }
            return nil
        }

        /// 是否允许外部网络访问
        /// - `.localArea` 跟随 `CustomArea.allowsNetworkAccess`
        /// - `.remoteURL` / `.mineradio` 恒为 true（远程站点本身即需网络）
        var allowsNetworkAccess: Bool {
            switch self {
            case .localArea(let area): return area.allowsNetworkAccess
            case .remoteURL, .dynamicAgent, .douyin: return true
            case .mineradio: return true
            }
        }

        /// 用于 JS Bridge 的 areaID（远程 URL / mineradio 无 areaID，hint 不生效）
        var areaID: String? {
            if case .localArea(let area) = self { return area.id }
            return nil
        }

        /// 是否为 Mineradio 源（需注入 Bridge user script + 注册 message handler）
        var isMineradio: Bool {
            if case .mineradio = self { return true }
            return false
        }

        var isRemoteSource: Bool {
            if case .remoteURL = self { return true }
            if case .dynamicAgent = self { return true }
            return false
        }

        var isDynamicAgent: Bool {
            if case .dynamicAgent = self { return true }
            return false
        }

        var isDouyin: Bool {
            if case .douyin = self { return true }
            return false
        }

        var prefersDouyinMobileLayout: Bool {
            if case .douyin(_, let prefersMobileLayout) = self { return prefersMobileLayout }
            return false
        }
    }

    let source: ContentSource
    /// Spec: 远程 URL 功能收起后保活开关 —— 仅展开态传 true 时启用缓存复用。
    /// 开启后 SwiftUI 移除宿主视图时 WKWebView 由 `CustomAreaWebViewCache` 持有强引用继续存活；
    /// 下次 `makeNSView` 从缓存取回同一实例并重新绑定 Coordinator（message handler / delegate）。
    let keepsAlive: Bool
    /// 远程页面允许在当前 WebView 内跨域导航的域名后缀（例如 Apple 登录域名）。
    let allowedRemoteDomains: [String]
    /// 远程媒体站点允许无额外点击继续播放音频。
    let enablesRemoteMediaPlayback: Bool

    init(
        source: ContentSource,
        keepsAlive: Bool = false,
        allowedRemoteDomains: [String] = [],
        enablesRemoteMediaPlayback: Bool = false
    ) {
        self.source = source
        self.keepsAlive = keepsAlive
        self.allowedRemoteDomains = allowedRemoteDomains
        self.enablesRemoteMediaPlayback = enablesRemoteMediaPlayback
    }

    /// Spec: 缓存复用 —— `.remoteURL` / `.mineradio` 源 + `keepsAlive == true` 时查缓存。
    /// 命中缓存时复用 WKWebView（重新绑定 Coordinator），否则新建并存入缓存。
    /// `.localArea` 源不经过缓存（本地文件资源开销低，无需保活）。
    private func cachedURL() -> URL? {
        guard keepsAlive else { return nil }
        switch source {
        case .remoteURL(let url): return url
        case .dynamicAgent(let url): return url
        case .douyin(let url, _): return url
        case .mineradio(let url): return url
        case .localArea: return nil
        }
    }

    func makeNSView(context: Context) -> WKWebView {
        // Spec: 保活缓存命中 —— 复用已存在的 WKWebView，重新绑定 Coordinator 后返回
        if let cachedURL = cachedURL(),
           let cached = CustomAreaWebViewCache.shared.webView(for: cachedURL) {
            rebindCoordinator(to: cached, context: context)
            cached.removeFromSuperview()
            loadAreaIfNeeded(into: cached, context: context)
            return cached
        }

        let configuration = WKWebViewConfiguration()
        configuration.preferences = WKPreferences()

        // Spec: 限制 WebView 网络/JS 能力
        let preferences = configuration.preferences
        preferences.javaScriptCanOpenWindowsAutomatically = false
        if #available(macOS 13.0, *) {
            preferences.isElementFullscreenEnabled = false
        }

        // Spec: mineradio-bridge-compat-layer —— Mineradio 源特殊配置
        if source.isMineradio {
            // 使用 default dataStore 共享 cookie（登录 WebView 与 mineradio WebView 共用）
            configuration.websiteDataStore = WKWebsiteDataStore.default()
            // 桌面 Chrome UA（避免 mineradio.art 检测为移动端）
            configuration.applicationNameForUserAgent = "Chrome/124.0.0.0"
            // 允许自动播放媒体（mineradio 是音乐播放器）
            configuration.mediaTypesRequiringUserActionForPlayback = []
        }

        if source.isDouyin {
            configuration.websiteDataStore = WKWebsiteDataStore.default()
            configuration.applicationNameForUserAgent = source.prefersDouyinMobileLayout
                ? "Mobile/15E148 Safari/604.1"
                : "Chrome/131.0.0.0"
            configuration.mediaTypesRequiringUserActionForPlayback = []
            if source.prefersDouyinMobileLayout {
                configuration.userContentController.addUserScript(WKUserScript(
                    source: Self.douyinMobileLayoutScript,
                    injectionTime: .atDocumentStart,
                    forMainFrameOnly: true
                ))
            }
        }

        if source.isRemoteSource, enablesRemoteMediaPlayback {
            configuration.websiteDataStore = WKWebsiteDataStore.default()
            configuration.mediaTypesRequiringUserActionForPlayback = []
        }

        // Spec: 仅在不允许外部网络时注册本地 scheme handler（限制外部资源）
        if !source.allowsNetworkAccess {
            configuration.setURLSchemeHandler(LocalFileSchemeHandler(), forURLScheme: "trae-flow-local")
            // Spec: network-block-injection —— fetch/XHR 不触发 decidePolicyFor navigationAction
            // （它们走 WebKit NetworkProcess，不经 navigation delegate）。当不允许外部网络时，
            // 注入 WKUserScript 在 atDocumentStart 拦截 window.fetch 与 XMLHttpRequest，
            // 使其立即 reject，从源头阻断外部请求（无论同源/跨域/资源加载均覆盖）。
            let blockScript = WKUserScript(
                source: Self.networkBlockScript,
                injectionTime: .atDocumentStart,
                forMainFrameOnly: false
            )
            configuration.userContentController.addUserScript(blockScript)
        }

        // Spec: scrollbar-style-injection —— 本地自定义区域统一深色滚动条，与 Flow Island 深色主题协调
        if case .localArea = source {
            let scrollbarScript = WKUserScript(
                source: Self.scrollbarStyleScript,
                injectionTime: .atDocumentStart,
                forMainFrameOnly: false
            )
            configuration.userContentController.addUserScript(scrollbarScript)
        }

        if source.isDynamicAgent {
            let agentStyleScript = WKUserScript(
                source: Self.dynamicAgentStyleScript,
                injectionTime: .atDocumentEnd,
                forMainFrameOnly: true
            )
            configuration.userContentController.addUserScript(agentStyleScript)
        }

        // Spec: 注册 JS Bridge —— 自定义 HTML 提示消息通道
        configuration.userContentController.add(context.coordinator, name: Self.hintMessageHandlerName)
        // Spec: 注册 JS Bridge —— 系统指标查询通道（HTML 可通过此通道获取真实 CPU/内存/负载数据）
        configuration.userContentController.add(context.coordinator, name: Self.metricsMessageHandlerName)
        // Spec: 注册 JS Bridge —— 收起 Flow 岛展开面板通道（HTML 通过 postMessage 触发收起）
        configuration.userContentController.add(context.coordinator, name: Self.collapseMessageHandlerName)
        // Spec: 注册 JS Bridge —— 在 TRAE 中打开编辑通道（HTML 通过 postMessage 触发，以当前区域目录为工作区打开 TRAE CN）
        configuration.userContentController.add(context.coordinator, name: Self.openInTraeMessageHandlerName)

        // Spec: mineradio-bridge-compat-layer —— 注入 Bridge user script + 注册 message handler
        if source.isMineradio {
            let bridgeScript = MineradioBridgeUserScript.makeUserScript()
            configuration.userContentController.addUserScript(bridgeScript)
            configuration.userContentController.add(context.coordinator, name: MineradioBridgeUserScript.apiMessageHandlerName)
            configuration.userContentController.add(context.coordinator, name: MineradioBridgeUserScript.binaryMessageHandlerName)
            // Spec: mineradio-bridge-compat-layer —— 播放状态 handler（歌词显示用）
            configuration.userContentController.add(context.coordinator, name: MineradioBridgeUserScript.playbackMessageHandlerName)
        }

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        webView.uiDelegate = context.coordinator
        webView.translatesAutoresizingMaskIntoConstraints = false
        webView.setValue(false, forKey: "drawsBackground") // 透明背景
        webView.underPageBackgroundColor = .clear

        // Spec: mineradio 桌面 Chrome UA
        if source.isMineradio {
            webView.customUserAgent = MineradioBridgeUserScript.desktopChromeUserAgent
        } else if source.isDouyin {
            webView.customUserAgent = source.prefersDouyinMobileLayout
                ? Self.douyinMobileUserAgent
                : Self.douyinDesktopUserAgent
        }

        // Spec: 禁用内置缩放、强制可访问性
        if #available(macOS 13.0, *) {
            webView.pageZoom = 1.0
        }

        context.coordinator.webView = webView
        // 同步当前 areaID 与网络访问策略（区域/源切换时 JS Bridge 与导航策略需引用最新值）
        context.coordinator.currentAreaID = source.areaID
        context.coordinator.allowsNetworkAccess = source.allowsNetworkAccess
        // Spec: 同步保活标记与缓存键 —— dismantleNSView 据此决定是否移入离屏窗口
        context.coordinator.keepsAlive = keepsAlive
        context.coordinator.cachedURLString = cachedURL()?.absoluteString
        context.coordinator.allowedRemoteDomains = allowedRemoteDomains
        // 同步源类型 —— decidePolicyFor 据此区分跳转策略：
        // - `.remoteURL`：同 host 在 WebView 内导航，不同 host 转系统浏览器
        // - `.mineradio`：所有 http/https 主框架导航在 WebView 内（允许跨 host）
        // - `.localArea`：所有 http/https 主框架导航转系统浏览器
        if source.isRemoteSource {
            context.coordinator.isRemoteSource = true
            context.coordinator.isMineradioSource = false
            context.coordinator.isDouyinSource = false
        } else if source.isDouyin {
            context.coordinator.isRemoteSource = false
            context.coordinator.isMineradioSource = false
            context.coordinator.isDouyinSource = true
        } else if source.isMineradio {
            context.coordinator.isRemoteSource = false
            context.coordinator.isMineradioSource = true
            context.coordinator.isDouyinSource = false
        } else {
            context.coordinator.isRemoteSource = false
            context.coordinator.isMineradioSource = false
            context.coordinator.isDouyinSource = false
        }

        // Spec: mineradio-bridge-compat-layer —— 绑定 Coordinator
        if source.isMineradio {
            MineradioBridgeCoordinator.shared.attach(to: webView)
        }

        // Spec: 保活缓存存入 —— `.remoteURL` / `.mineradio` 源 + `keepsAlive == true` 时存
        if let cachedURL = cachedURL() {
            CustomAreaWebViewCache.shared.storeWebView(webView, for: cachedURL)
        }

        // Spec: network-block-content-rule-list —— 不允许外部网络时，异步获取
        // WKContentRuleList 并添加到 userContentController，再加载页面。
        // WKContentRuleList 在 WebKit 网络层 block 所有 http/https 请求（含 fetch/XHR/资源），
        // 与 navigation delegate + JS 注入三层叠加，JS 完全无法绕过。
        // 允许外部网络时直接加载（无需规则）。
        if source.allowsNetworkAccess {
            loadArea(into: webView, context: context)
        } else {
            Self.loadNetworkBlockRule { ruleList in
                DispatchQueue.main.async {
                    if let ruleList = ruleList {
                        webView.configuration.userContentController.add(ruleList)
                    }
                    // 无论是否获取到规则都加载页面（JS 拦截脚本已注入作为 fallback）
                    loadArea(into: webView, context: context)
                }
            }
        }
        return webView
    }

    /// Spec: 保活复用时重新绑定 Coordinator —— 旧 message handler 指向已释放的旧 Coordinator，
    /// 需先移除再添加新的；navigationDelegate / uiDelegate 也更新为新 Coordinator。
    /// Mineradio 源额外重新绑定 Bridge message handler 并重新 attach `MineradioBridgeCoordinator`。
    private func rebindCoordinator(to webView: WKWebView, context: Context) {
        let controller = webView.configuration.userContentController
        // 移除旧 handler（释放旧 Coordinator）
        controller.removeScriptMessageHandler(forName: Self.hintMessageHandlerName)
        controller.removeScriptMessageHandler(forName: Self.metricsMessageHandlerName)
        controller.removeScriptMessageHandler(forName: Self.collapseMessageHandlerName)
        controller.removeScriptMessageHandler(forName: Self.openInTraeMessageHandlerName)
        if source.isMineradio {
            controller.removeScriptMessageHandler(forName: MineradioBridgeUserScript.apiMessageHandlerName)
            controller.removeScriptMessageHandler(forName: MineradioBridgeUserScript.binaryMessageHandlerName)
            controller.removeScriptMessageHandler(forName: MineradioBridgeUserScript.playbackMessageHandlerName)
        }
        // 添加新 handler
        controller.add(context.coordinator, name: Self.hintMessageHandlerName)
        controller.add(context.coordinator, name: Self.metricsMessageHandlerName)
        controller.add(context.coordinator, name: Self.collapseMessageHandlerName)
        controller.add(context.coordinator, name: Self.openInTraeMessageHandlerName)
        if source.isMineradio {
            controller.add(context.coordinator, name: MineradioBridgeUserScript.apiMessageHandlerName)
            controller.add(context.coordinator, name: MineradioBridgeUserScript.binaryMessageHandlerName)
            controller.add(context.coordinator, name: MineradioBridgeUserScript.playbackMessageHandlerName)
        }
        // 更新 delegate
        webView.navigationDelegate = context.coordinator
        webView.uiDelegate = context.coordinator
        // 同步 Coordinator 状态
        context.coordinator.webView = webView
        context.coordinator.currentAreaID = source.areaID
        context.coordinator.allowsNetworkAccess = source.allowsNetworkAccess
        // Spec: 同步保活标记与缓存键 —— dismantleNSView 据此决定是否移入离屏窗口
        context.coordinator.keepsAlive = keepsAlive
        context.coordinator.cachedURLString = cachedURL()?.absoluteString
        context.coordinator.allowedRemoteDomains = allowedRemoteDomains
        if source.isRemoteSource {
            context.coordinator.isRemoteSource = true
            context.coordinator.isMineradioSource = false
            context.coordinator.isDouyinSource = false
        } else if source.isDouyin {
            context.coordinator.isRemoteSource = false
            context.coordinator.isMineradioSource = false
            context.coordinator.isDouyinSource = true
        } else if source.isMineradio {
            context.coordinator.isRemoteSource = false
            context.coordinator.isMineradioSource = true
            context.coordinator.isDouyinSource = false
            // Spec: mineradio-bridge-compat-layer —— 重新 attach Coordinator
            //（attach 只更新 webView 引用 + 刷新登录态，不重置页面状态）
            MineradioBridgeCoordinator.shared.attach(to: webView)
        } else {
            context.coordinator.isRemoteSource = false
            context.coordinator.isMineradioSource = false
            context.coordinator.isDouyinSource = false
        }
    }

    /// Spec: 保活复用时仅在 URL 变化或未加载时重新 load，避免重置页面状态（音频/滚动/会话）。
    /// 新 Coordinator 无 `lastRemoteURLString` 状态，直接比对 WebView 当前 URL。
    private func loadAreaIfNeeded(into webView: WKWebView, context: Context) {
        switch source {
        case .localArea:
            // 本地源不经过保活缓存（cachedRemoteURL 只返回 .remoteURL），此分支不会命中
            loadArea(into: webView, context: context)
        case .remoteURL(let url):
            if webView.url?.absoluteString != url.absoluteString {
                loadArea(into: webView, context: context)
            } else {
                // URL 一致：同步 Coordinator 状态，避免 updateNSView 误判需要 reload
                context.coordinator.lastRemoteURLString = url.absoluteString
                context.coordinator.lastAreaID = nil
                context.coordinator.lastEntryPointURL = nil
            }
        case .dynamicAgent(let url):
            if webView.url?.absoluteString != url.absoluteString {
                loadArea(into: webView, context: context)
            } else {
                context.coordinator.lastRemoteURLString = url.absoluteString
                context.coordinator.lastAreaID = nil
                context.coordinator.lastEntryPointURL = nil
            }
        case .douyin(let url, _):
            if webView.url == nil {
                loadArea(into: webView, context: context)
            } else {
                // 抖音会在推荐流、登录和详情页间改写 URL；复用 WebView 时保留当前页面与滚动位置。
                context.coordinator.lastRemoteURLString = url.absoluteString
                context.coordinator.lastAreaID = nil
                context.coordinator.lastEntryPointURL = nil
            }
        case .mineradio(let url):
            if webView.url?.absoluteString != url.absoluteString {
                loadArea(into: webView, context: context)
            } else {
                context.coordinator.lastRemoteURLString = url.absoluteString
                context.coordinator.lastAreaID = nil
                context.coordinator.lastEntryPointURL = nil
            }
        }
    }

    func updateNSView(_ nsView: WKWebView, context: Context) {
        guard let webView = context.coordinator.webView else { return }
        // 同步当前 areaID 与网络访问策略（区域/源切换时 JS Bridge 与导航策略需引用最新值）
        context.coordinator.currentAreaID = source.areaID
        context.coordinator.allowsNetworkAccess = source.allowsNetworkAccess
        // Spec: 同步保活标记与缓存键 —— dismantleNSView 据此决定是否移入离屏窗口
        context.coordinator.keepsAlive = keepsAlive
        context.coordinator.cachedURLString = cachedURL()?.absoluteString
        context.coordinator.allowedRemoteDomains = allowedRemoteDomains
        // 同步源类型 —— decidePolicyFor 据此区分跳转策略
        if source.isRemoteSource {
            context.coordinator.isRemoteSource = true
            context.coordinator.isMineradioSource = false
            context.coordinator.isDouyinSource = false
        } else if source.isDouyin {
            context.coordinator.isRemoteSource = false
            context.coordinator.isMineradioSource = false
            context.coordinator.isDouyinSource = true
        } else if source.isMineradio {
            context.coordinator.isRemoteSource = false
            context.coordinator.isMineradioSource = true
            context.coordinator.isDouyinSource = false
        } else {
            context.coordinator.isRemoteSource = false
            context.coordinator.isMineradioSource = false
            context.coordinator.isDouyinSource = false
        }

        // 仅当源标识或入口 URL 变化时重新加载
        switch source {
        case .localArea(let area):
            let needsReload = context.coordinator.lastAreaID != area.id
                || context.coordinator.lastRemoteURLString != nil
                || context.coordinator.lastEntryPointURL?.path != area.entryPointURL.path
            if needsReload {
                loadArea(into: webView, context: context)
            }
        case .remoteURL(let url):
            let urlString = url.absoluteString
            let needsReload = context.coordinator.lastRemoteURLString != urlString
                || context.coordinator.lastAreaID != nil
            if needsReload {
                loadArea(into: webView, context: context)
            }
        case .dynamicAgent(let url):
            let urlString = url.absoluteString
            let needsReload = context.coordinator.lastRemoteURLString != urlString
                || context.coordinator.lastAreaID != nil
            if needsReload {
                loadArea(into: webView, context: context)
            }
        case .douyin(let url, _):
            let needsReload = context.coordinator.lastRemoteURLString != url.absoluteString
                || context.coordinator.lastAreaID != nil
            if needsReload {
                loadArea(into: webView, context: context)
            }
        case .mineradio(let url):
            let urlString = url.absoluteString
            let needsReload = context.coordinator.lastRemoteURLString != urlString
                || context.coordinator.lastAreaID != nil
            if needsReload {
                loadArea(into: webView, context: context)
            }
        }
    }

    /// Spec: 按内容源选择加载方式
    /// - `.localArea` → `loadFileURL(_:allowingReadAccessTo:)` 加载目录入口 HTML
    /// - `.remoteURL` / `.mineradio` → `load(URLRequest(url:))` 加载远程站点
    private func loadArea(into webView: WKWebView, context: Context) {
        switch source {
        case .localArea(let area):
            let url = area.loadableFileURL
            webView.loadFileURL(url, allowingReadAccessTo: area.directoryURL)
            context.coordinator.lastAreaID = area.id
            context.coordinator.lastEntryPointURL = area.entryPointURL
            context.coordinator.lastRemoteURLString = nil
        case .remoteURL(let url):
            webView.load(URLRequest(url: url))
            context.coordinator.lastAreaID = nil
            context.coordinator.lastEntryPointURL = nil
            context.coordinator.lastRemoteURLString = url.absoluteString
        case .dynamicAgent(let url):
            webView.load(URLRequest(url: url))
            context.coordinator.lastAreaID = nil
            context.coordinator.lastEntryPointURL = nil
            context.coordinator.lastRemoteURLString = url.absoluteString
        case .douyin(let url, _):
            webView.load(URLRequest(url: url))
            context.coordinator.lastAreaID = nil
            context.coordinator.lastEntryPointURL = nil
            context.coordinator.lastRemoteURLString = url.absoluteString
        case .mineradio(let url):
            webView.load(URLRequest(url: url))
            context.coordinator.lastAreaID = nil
            context.coordinator.lastEntryPointURL = nil
            context.coordinator.lastRemoteURLString = url.absoluteString
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    /// Spec: SwiftUI 移除宿主视图时调用。当 `keepsAlive` 为 true 时，将 WKWebView 移入
    /// 离屏宿主窗口，使其仍在窗口层级中 —— 否则 macOS 会挂起不在任何 NSWindow 中的
    /// WKWebView 的 JS 执行，导致 mineradio.art 播完一首歌后无法自动播放下一首
    ///（自动切歌逻辑依赖 JS timer/event 回调，JS 挂起后需重新展开页面才恢复）。
    static func dismantleNSView(_ nsView: WKWebView, coordinator: Coordinator) {
        guard coordinator.keepsAlive,
              let urlString = coordinator.cachedURLString,
              let url = URL(string: urlString) else { return }
        // 仅处理仍是缓存实例的 WebView（避免 evict 后操作已释放的 view）
        guard CustomAreaWebViewCache.shared.webView(for: url) === nsView else { return }
        CustomAreaWebViewCache.shared.hostInOffscreenWindow(nsView)
    }

    final class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate, WKScriptMessageHandler {
        weak var webView: WKWebView?
        /// 上次加载的本地区域 ID（UUID）
        var lastAreaID: String?
        /// 上次加载的本地入口 URL（用于检测入口文件变化）
        var lastEntryPointURL: URL?
        /// 上次加载的远程 URL（absoluteString，用于检测远程源变化）
        var lastRemoteURLString: String?
        /// 当前关联的自定义区域 ID —— JS Bridge 回调时用于定位 `CustomAreaHintStore`；
        /// 远程 URL 源为 nil，hint 丢弃
        var currentAreaID: String?
        /// 当前内容源是否允许外部网络访问 —— `decidePolicyFor` 据此放行/拦截 http/https。
        /// 在 makeNSView / updateNSView 中由 source.allowsNetworkAccess 同步。
        var allowsNetworkAccess: Bool = false
        /// 当前内容源是否为远程 URL —— `decidePolicyFor` 据此区分同 host 跳转策略：
        /// `.remoteURL` 源同 host 链接在 WebView 内导航、不同 host 转系统浏览器；
        /// `.localArea` 源所有 http/https 主框架导航一律转系统浏览器。在 makeNSView / updateNSView 中同步。
        var isRemoteSource: Bool = false
        /// 当前内容源是否为 Mineradio —— `decidePolicyFor` 据此放行跨 host 主框架导航
        ///（mineradio.art 可能跳转 OAuth 回调或其他 host）。
        /// Spec: mineradio-bridge-compat-layer
        var isMineradioSource: Bool = false
        /// 当前内容源是否为抖音 —— 允许抖音主站、账号与媒体域名在当前窗口内完成跳转。
        var isDouyinSource: Bool = false
        /// 远程页面被允许留在当前 WebView 内的跨域域名后缀。
        var allowedRemoteDomains: [String] = []
        /// Spec: 保活标记 —— `dismantleNSView` 据此决定是否将 WebView 移入离屏窗口。
        /// 在 makeNSView / updateNSView 中由 keepsAlive 同步。
        var keepsAlive: Bool = false
        /// Spec: 缓存键 URL（absoluteString）—— `dismantleNSView` 据此查找缓存实例。
        /// 仅 `.remoteURL` / `.mineradio` 源有值，`.localArea` 为 nil。
        var cachedURLString: String?

        func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
            // 源标识在 loadArea 中同步，无需在此推导
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            // Spec: 阻止外部链接跳转（由 decidePolicyFor 处理）
        }

        /// Spec: 根据内容源决定导航策略 ——
        /// - 主框架 http/https 导航到不同 host 的外部链接转交系统默认浏览器打开（避免在 WebView 内跳走）；
        /// - `.remoteURL` 源同 host 的主框架导航在 WebView 内继续；
        /// - `.localArea` 源所有 http/https 主框架导航一律转系统浏览器（本地 HTML 不会与外部站点同源）；
        /// - `.mineradio` 源所有 http/https 主框架导航在 WebView 内（允许跨 host，OAuth 回调可能跳转其他 host）；
        /// - 子框架/资源请求（图片/JS/css/iframe 等，非链接点击）按 `allowsNetworkAccess` 决定；
        ///   注意：`fetch` / `XMLHttpRequest` 不经此 delegate，由 `networkBlockScript` 在 JS 层拦截；
        /// - `file` / `trae-flow-local` 始终放行；其他 scheme 一律取消。
        /// Spec: mineradio-bridge-compat-layer
        func webView(
            _ webView: WKWebView,
            decidePolicyFor navigationAction: WKNavigationAction,
            decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
        ) {
            guard let url = navigationAction.request.url else {
                decisionHandler(.cancel)
                return
            }
            let scheme = url.scheme?.lowercased() ?? ""
            let currentURL = webView.url
            // 主框架导航：targetFrame == nil（target="_blank"）或链接点击
            let isMainFrameNavigation = navigationAction.targetFrame == nil
                || navigationAction.navigationType == .linkActivated

            // file / trae-flow-local scheme → 始终放行（本地资源）
            if scheme == "file" || scheme == "trae-flow-local" {
                decisionHandler(.allow)
                return
            }

            // http / https 处理
            if scheme == "http" || scheme == "https" {
                if isMainFrameNavigation {
                    if isMineradioSource {
                        // mineradio 源：跨 host 主框架导航一律放行（OAuth 回调 / 第三方登录可能跳转其他 host）
                        decisionHandler(.allow)
                    } else if isDouyinSource {
                        if isAllowedDouyinHost(url.host) {
                            decisionHandler(.allow)
                        } else {
                            NSWorkspace.shared.open(url)
                            decisionHandler(.cancel)
                        }
                    } else if isRemoteSource {
                        // 普通远程页面仅允许同 host；明确配置的账号/媒体域名也留在弹窗内。
                        if isSameHost(currentURL, url) || isAllowedRemoteHost(url.host) {
                            decisionHandler(.allow)
                        } else {
                            NSWorkspace.shared.open(url)
                            decisionHandler(.cancel)
                        }
                    } else {
                        // 本地区域源：本地 HTML 不会与 http/https 同源，主框架导航一律转系统浏览器
                        NSWorkspace.shared.open(url)
                        decisionHandler(.cancel)
                    }
                } else {
                    // 子框架/资源请求（图片/JS/css/iframe 等，非链接点击）按 allowsNetworkAccess 决定
                    // 注意：fetch / XMLHttpRequest 不经此 delegate，由 networkBlockScript 在 JS 层拦截
                    if allowsNetworkAccess {
                        decisionHandler(.allow)
                    } else {
                        decisionHandler(.cancel)
                    }
                }
                return
            }

            // 其他 scheme（tel/mailto 等）→ 取消
            decisionHandler(.cancel)
        }

        /// Spec: 判断两个 URL 是否同 host —— 用于 `decidePolicyFor` 区分远程源同站跳转与外部链接。
        /// 任一为 nil 或无 host 时返回 false（保守视为不同 host）。
        private func isSameHost(_ url1: URL?, _ url2: URL?) -> Bool {
            guard let h1 = url1?.host, let h2 = url2?.host else { return false }
            return h1 == h2
        }

        private func isAllowedRemoteHost(_ host: String?) -> Bool {
            guard let host = host?.lowercased() else { return false }
            return allowedRemoteDomains.contains { domain in
                let normalized = domain.lowercased()
                return host == normalized || host.hasSuffix(".\(normalized)")
            }
        }

        private func isAllowedDouyinHost(_ host: String?) -> Bool {
            guard let host = host?.lowercased() else { return false }
            let allowedDomains = ["douyin.com", "bytedance.com", "byteimg.com", "douyinvod.com"]
            return allowedDomains.contains { host == $0 || host.hasSuffix(".\($0)") }
        }

        /// Spec: 阻止新窗口打开
        func webView(
            _ webView: WKWebView,
            createWebViewWith configuration: WKWebViewConfiguration,
            for navigationAction: WKNavigationAction,
            windowFeatures: WKWindowFeatures
        ) -> WKWebView? {
            if isDouyinSource,
               let url = navigationAction.request.url,
               isAllowedDouyinHost(url.host) {
                webView.load(navigationAction.request)
            } else if isRemoteSource,
                      let url = navigationAction.request.url,
                      isSameHost(webView.url, url) || isAllowedRemoteHost(url.host) {
                webView.load(navigationAction.request)
            }
            return nil
        }

        /// Spec: 响应网页 `<input type="file">` 点击 —— 默认 WKUIDelegate 不实现此方法时
        /// 文件选择器不会弹出（点击无反应）。Mineradio 背景媒体上传等场景需要此回调。
        /// 根据 `accept` MIME 类型构造 NSOpenPanel 允许的文件类型，用户选择后通过
        /// `completionHandler` 回传 URL 数组；取消则回传空数组（必须调用 completionHandler，
        /// 否则网页端 Promise 永久挂起）。
        func webView(
            _ webView: WKWebView,
            runOpenPanelWith parameters: WKOpenPanelParameters,
            initiatedByFrame frame: WKFrameInfo,
            completionHandler: @escaping ([URL]?) -> Void
        ) {
            let panel = NSOpenPanel()
            panel.canChooseFiles = true
            panel.canChooseDirectories = false
            panel.allowsMultipleSelection = parameters.allowsMultipleSelection

            // Spec: 根据 WKOpenPanelParameters.allowedFileTypes 过滤（macOS 13+ 不再提供该属性，
            // 由网页 accept 属性解析已不可得，这里直接允许所有文件类型，交给用户自行选择）
            panel.allowsOtherFileTypes = true

            panel.beginSheetModal(for: NSApp.keyWindow ?? NSApp.mainWindow ?? webView.window ?? NSWindow()) { response in
                if response == .OK {
                    completionHandler(panel.urls)
                } else {
                    // 必须回传空数组而非 nil，避免网页端 Promise 挂起
                    completionHandler([])
                }
            }
        }

        // MARK: - JS Bridge: traeFlowHint

        /// Spec: 接收自定义 HTML 通过 `window.webkit.messageHandlers.traeFlowHint.postMessage(...)` 推送的提示。
        /// 消息体格式（JSON）：
        /// ```
        /// { "text": "提醒内容", "duration": 3000 }  // duration 可选，毫秒，默认 5000
        /// { "action": "clear" }                     // 清除当前区域所有提示
        /// ```
        /// 也可直接传字符串：`postMessage("提醒内容")`。
        /// 注意：远程 URL 源无 areaID，消息将被丢弃。
        func userContentController(
            _ userContentController: WKUserContentController,
            didReceive message: WKScriptMessage
        ) {
            // Spec: mineradio-bridge-compat-layer —— Bridge API / 二进制消息路由到 MineradioBridgeCoordinator
            if message.name == MineradioBridgeUserScript.apiMessageHandlerName {
                MineradioBridgeCoordinator.shared.handleApiMessage(message)
                return
            }
            if message.name == MineradioBridgeUserScript.binaryMessageHandlerName {
                MineradioBridgeCoordinator.shared.handleBinaryMessage(message)
                return
            }
            // Spec: mineradio-bridge-compat-layer —— 播放状态路由（歌词显示用）
            if message.name == MineradioBridgeUserScript.playbackMessageHandlerName {
                MineradioBridgeCoordinator.shared.handlePlaybackMessage(message)
                return
            }

            // 系统指标查询
            if message.name == CustomAreaWebView.metricsMessageHandlerName {
                handleMetricsRequest()
                return
            }

            // Spec: 收起 Flow 岛展开面板 —— HTML 通过 traeFlowCollapse.postMessage 触发，
            // 由 Coordinator 发出通知，NotchView 监听后调用 notchClose()。
            if message.name == CustomAreaWebView.collapseMessageHandlerName {
                NotificationCenter.default.post(name: .traeFlowCollapseLeftExpanded, object: nil)
                return
            }

            // Spec: 在 TRAE 中打开编辑 —— HTML 通过 traeFlowOpenInTrae.postMessage 触发，
            // 以当前区域目录为工作区在指定 TRAE 变体（默认 TRAE CN）中打开，便于直接编辑 HTML 源文件。
            if message.name == CustomAreaWebView.openInTraeMessageHandlerName {
                handleOpenInTrae(message.body)
                return
            }

            guard message.name == CustomAreaWebView.hintMessageHandlerName else {
                return
            }
            guard let areaID = currentAreaID else {
                NSLog("[traeFlowHint] 收到消息但 currentAreaID 为 nil（可能是远程 URL 源），丢弃：\(message.body)")
                return
            }

            NSLog("[traeFlowHint] 收到消息 areaID=\(areaID) body=\(message.body)")

            if let str = message.body as? String {
                guard !str.isEmpty else { return }
                CustomAreaHintStore.shared.postHint(areaID: areaID, text: str, durationMs: CustomAreaHintStore.defaultDurationMs)
                return
            }

            guard let dict = message.body as? [String: Any] else { return }

            // 清除动作
            if let action = dict["action"] as? String, action == "clear" {
                CustomAreaHintStore.shared.clearHint(for: areaID)
                return
            }

            guard let text = dict["text"] as? String, !text.isEmpty else { return }
            var durationMs = CustomAreaHintStore.defaultDurationMs
            if let d = dict["duration"] as? Int {
                durationMs = d
            } else if let d = dict["duration"] as? Double {
                durationMs = Int(d)
            } else if let d = dict["durationMs"] as? Int {
                durationMs = d
            }
            NSLog("[traeFlowHint] 发布提示 areaID=\(areaID) text=\(text) durationMs=\(durationMs)")
            CustomAreaHintStore.shared.postHint(areaID: areaID, text: text, durationMs: durationMs)
        }

        // MARK: - JS Bridge: traeFlowMetrics

        /// 响应自定义 HTML 通过 `window.webkit.messageHandlers.traeFlowMetrics.postMessage(...)` 发起的系统指标查询。
        /// 采样真实的 CPU / 内存 / 负载数据，通过 `evaluateJavaScript` 回调 `window.receiveMetrics(json)`。
        private func handleMetricsRequest() {
            guard let webView = webView else { return }
            let json = SystemMetricsProvider.shared.sampleAsJSON()
            webView.evaluateJavaScript("if (window.receiveMetrics) { window.receiveMetrics(\(json)); }")
        }

        // MARK: - JS Bridge: traeFlowOpenInTrae

        /// Spec: 响应 `traeFlowOpenInTrae` —— 以当前区域目录为工作区在 TRAE 变体中打开编辑。
        /// 消息体（可选 JSON）：`{ "variant": "trae-cn" }`，`variant` 默认 `"trae-cn"`，
        /// 取值见 `TraeVariant.urlScheme`（trae / trae-cn / trae-work / trae-work-cn），
        /// 未识别值回退到 `trae-cn`。仅 `.localArea` 源有效（远程 URL / mineradio 无本地目录），
        /// 找不到当前区域时静默忽略并打日志。
        private func handleOpenInTrae(_ body: Any) {
            guard let areaID = currentAreaID,
                  let area = CustomAreaStore.shared.areas.first(where: { $0.id == areaID }) else {
                NSLog("[traeFlowOpenInTrae] 找不到当前区域（currentAreaID=\(currentAreaID ?? "nil")），忽略")
                return
            }
            var variant: TraeVariant = .traeCN
            if let dict = body as? [String: Any], let v = dict["variant"] as? String {
                switch v {
                case "trae": variant = .trae
                case "trae-cn": variant = .traeCN
                case "trae-work": variant = .traeWork
                case "trae-work-cn": variant = .traeWorkCN
                default: break
                }
            }
            NSLog("[traeFlowOpenInTrae] 在 \(variant.displayName) 中打开编辑：\(area.directoryURL.path)")
            TraeSessionLauncher.openWorkspace(variant, directoryURL: area.directoryURL)
        }
    }
}

/// Spec: 安全策略 —— 禁止外部网络请求
/// 简单占位 scheme handler；本地资源由 loadFileURL(allowingReadAccessTo:) 处理
private final class LocalFileSchemeHandler: NSObject, WKURLSchemeHandler {
    func webView(_ webView: WKWebView, start urlSchemeTask: WKURLSchemeTask) {
        urlSchemeTask.didFinish()
    }

    func webView(_ webView: WKWebView, stop urlSchemeTask: WKURLSchemeTask) {
        // no-op
    }
}
