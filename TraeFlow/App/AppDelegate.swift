import AppKit
import SwiftUI

@MainActor
class AppDelegate: NSObject, NSApplicationDelegate {
    private var windowManager: WindowManager?
    private var screenObserver: ScreenObserver?
    private let launchConfiguration = AppLaunchConfiguration()
    private let startupSessionMonitor = SessionMonitor()
    private let globalShortcutManager = GlobalShortcutManager.shared

    func applicationDidFinishLaunching(_ notification: Notification) {
        if launchConfiguration.shouldEnforceSingleInstance && !ensureSingleInstance() {
            NSApplication.shared.terminate(nil)
            return
        }

        // Touch the settings store early so the bridge runtime config is on disk
        // before any hook fires.
        _ = AppSettings.shared
        _ = LeftFeatureStore.shared
        _ = DynamicScreenshotManager.shared

        // 正常启动时默认回到 Flow Island 形态，避免测试/开发残留把 surfaceMode 设为 floatingPet。
        if !launchConfiguration.isRunningTests {
            AppSettings.surfaceMode = .notch
        }

        if !launchConfiguration.isRunningTests {
            UpdateManager.shared.start()
            UserIdleAutoProtection.shared.start()
        }

        if launchConfiguration.shouldInstallIntegrations {
            HookInstaller.installIfNeeded(
                markPresentationOnboardingPending: {},
                markHookInstallOnboardingPending: {}
            )
        }

        NSApplication.shared.setActivationPolicy(
            launchConfiguration.isRunningTests
                ? launchConfiguration.activationPolicy
                : (AppSettings.shared.showDockIcon ? .regular : .accessory)
        )

        let launchFlow = AppLaunchFlow(
            configuration: launchConfiguration,
            presentationModeOnboardingPending: AppSettings.presentationModeOnboardingPending
        )

        if launchFlow.shouldStartMonitoringImmediately {
            // Keep hook and app-server ingestion alive even when first-run onboarding
            // defers the initial Island window.
            startupSessionMonitor.startMonitoring()
        }

        // 先注册屏幕观察器，确保启动早期的屏幕参数变化也能触发重试。
        if launchConfiguration.shouldObserveScreens {
            screenObserver = ScreenObserver { [weak self] in
                self?.handleScreenChange()
            }
        }

        if launchFlow.shouldCreateInitialIslandWindow {
            startWindowManagerIfNeeded()
            // 显式激活应用，确保 Flow 岛窗口在启动时即可见。
            // nonactivatingPanel 在应用未激活时可能不会被 window server 立即渲染，
            // 即使调用了 orderFrontRegardless。激活后再次刷新全屏状态，保证
            // Flow 岛不会因启动时的误判而被隐藏。
            NSApplication.shared.activate(ignoringOtherApps: true)
            windowManager?.presentationCoordinator?.viewModel.refreshFullscreenPresentationState()
            windowManager?.presentationCoordinator?.requestDockedWindowVisibilityRefresh()

            // 部分多屏环境下 NSScreen.screens 在 applicationDidFinishLaunching 时尚未稳定，
            // 延迟重试一次，确保 Flow 岛在正确的屏幕上显示。
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
                self?.startWindowManagerIfNeeded()
                self?.windowManager?.presentationCoordinator?.requestDockedWindowVisibilityRefresh()
                LeftFeatureStore.shared.setExpandedActiveFeature(id: LeftFeature.appManagerID)
                self?.windowManager?.presentationCoordinator?.viewModel.presentCustomExpanded(reason: .boot)
            }
        }

        globalShortcutManager.start()

        // Dynamic 仅展示产品核心三页，不再注入 TRAE 自定义演示入口。

        // Spec: 延迟启动 MediaRemote Now Playing 轮询 —— 避免应用启动时
        // `MRMediaRemoteRegisterForNowPlayingNotifications` 的 arm64↔arm64e PAC 崩溃。
        // 仅当音乐功能或 Mineradio 功能已启用时启动（Mineradio 需要 MediaRemote 驱动歌词 progression）。
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            let features = LeftFeatureStore.shared.features
            let musicEnabled = features.contains { $0.kind == .music && $0.isEnabled }
            let mineradioEnabled = features.contains {
                if case .mineradio = $0.kind, $0.isEnabled { return true }
                return false
            }
            NSLog("[AppDelegate] 音乐功能启用状态: \(musicEnabled) mineradio=\(mineradioEnabled) (features.count=\(features.count))")
            if musicEnabled || mineradioEnabled {
                NowPlayingProvider.shared.start()
            }
            // Spec: mineradio-bridge-compat-layer —— 即使未展开过 Mineradio，也启动 NowPlaying 订阅
            // 以便 MediaRemote 检测到 Mineradio 播放时立即更新 playback 状态（歌词 progression 需要）
            if mineradioEnabled {
                MineradioBridgeCoordinator.shared.startNowPlayingSubscription()
            }
        }

    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        startWindowManagerIfNeeded()
        LeftFeatureStore.shared.setExpandedActiveFeature(id: LeftFeature.appManagerID)
        windowManager?.presentationCoordinator?.viewModel.presentCustomExpanded(reason: .click)
        windowManager?.presentationCoordinator?.requestDockedWindowVisibilityRefresh()
        return true
    }

    @MainActor
    private func handleScreenChange() {
        startWindowManagerIfNeeded()
    }

    @MainActor
    private func startWindowManagerIfNeeded() {
        if windowManager == nil {
            windowManager = WindowManager()
        }
        _ = windowManager?.setupNotchWindow()
    }

    func applicationWillTerminate(_ notification: Notification) {
        screenObserver = nil
        UserIdleAutoProtection.shared.stop()
        startupSessionMonitor.stopMonitoring()
    }
    private func ensureSingleInstance() -> Bool {
        let bundleID = Bundle.main.bundleIdentifier ?? "ai.dynamic.app"
        let runningApps = NSWorkspace.shared.runningApplications.filter {
            $0.bundleIdentifier == bundleID
        }

        if runningApps.count > 1 {
            if let existingApp = runningApps.first(where: { $0.processIdentifier != getpid() }) {
                existingApp.activate()
            }
            return false
        }

        return true
    }
}
