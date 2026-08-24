//
//  NotchWindow.swift
//  TraeFlow
//
//  Transparent window that overlays the notch area.
//  Mouse-event ignoring is managed dynamically by NotchWindowController
//  based on real-time mouse position — when the cursor is inside the
//  Flow Island content area, ignoresMouseEvents is set to false so
//  SwiftUI buttons can respond; when the cursor is outside, it is set
//  to true so clicks pass through to windows behind the panel.
//

import AppKit

// Use NSPanel subclass for non-activating behavior
class NotchPanel: NSPanel {
    static let compactLevel = NSWindow.Level(rawValue: 151)
    static let expandedLevel = NSWindow.Level.floating

    override init(
        contentRect: NSRect,
        styleMask style: NSWindow.StyleMask,
        backing backingStoreType: NSWindow.BackingStoreType,
        defer flag: Bool
    ) {
        super.init(
            contentRect: contentRect,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        // Floating panel behavior
        isFloatingPanel = true
        // 展开后包含 Dify WebView 等文本输入控件，必须允许面板成为 key window，
        // 否则中文输入法只有拼音组合文本而不会显示候选窗口。
        becomesKeyOnlyIfNeeded = false

        // Transparent configuration
        isOpaque = false
        titleVisibility = .hidden
        titlebarAppearsTransparent = true
        backgroundColor = .clear
        hasShadow = false

        // CRITICAL: Prevent window from moving during space switches
        isMovable = false

        // Window behavior - stays on all spaces, above menu bar
        collectionBehavior = [
            .fullScreenAuxiliary,
            .stationary,
            .canJoinAllSpaces,
            .ignoresCycle
        ]

        // Spec: window-level-vs-menubar-hiders —— 窗口层级需高于 iBar / Bartender / Ice 等
        // 菜单栏图标隐藏类应用的遮罩窗口，否则它们的 overlay 会先拦截鼠标点击，导致
        // Flow 岛无法点击展开/切换功能。这类应用的遮罩窗口通常位于 `.popUpMenu` (101) 附近，
        // 因此把 Flow 岛抬到 `.popUpMenu + 50` (151)，盖过绝大多数 menu bar hider 的 overlay，
        // 同时仍低于 `.screenSaver` (1000)，避免压到系统屏保/锁屏界面。
        level = Self.compactLevel

        // Enable tooltips even when app is inactive (needed for panel windows)
        allowsToolTipsWhenApplicationIsInactive = true

        // Default: ignore all mouse events.
        // NotchWindowController dynamically toggles this to false when
        // the mouse is inside the actual content area and the panel is opened.
        ignoresMouseEvents = true

        isReleasedWhenClosed = true
        acceptsMouseMovedEvents = false
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    override func sendEvent(_ event: NSEvent) {
        if event.type == .leftMouseDown, !ignoresMouseEvents {
            // nonactivatingPanel 默认不会切换前台应用；显式激活后，WKWebView 才能
            // 完整接收 NSTextInputClient 的中文候选与选择事件。
            NSApp.activate(ignoringOtherApps: true)
            makeKey()
        }
        super.sendEvent(event)
    }
}
