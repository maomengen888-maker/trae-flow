# 源码同步验证记录 · 2026-09-28

环境：Apple Silicon（arm64），macOS 26.6.2，Xcode 27.0（27A266a）。

## 构建

主应用 Debug 构建通过，使用 `CODE_SIGNING_ALLOWED=NO`。本次同步修复了 Xcode 27 下 SwiftPM 产物目录变化导致的 Bridge 嵌入失败，改为使用 `swift build --show-bin-path` 获取实际目录。

```bash
xcodebuild -project TraeFlow.xcodeproj -scheme TraeFlow \
  -configuration Debug -destination 'platform=macOS,arch=arm64' \
  -derivedDataPath build/DerivedData CODE_SIGNING_ALLOWED=NO build
```

## 定向单元测试

共执行 **69** 项：**48 通过，21 失败，0 跳过**。本次未运行完整回归或 UI 自动化测试，也未完成交互验收。

| 测试类 | 通过 | 失败 |
| --- | ---: | ---: |
| DynamicAICompanionStoreTests | 7 | 0 |
| DynamicDifyChatStoreTests | 4 | 0 |
| NotchViewControllerTransparencyTests | 2 | 0 |
| TelemetryServiceTests | 6 | 0 |
| NotchViewModelTests | 29 | 21 |

遥测测试替身调整为 MainActor 隔离并在接收记录时切回 MainActor，以适配当前工具链；生产遥测行为未改动。

```bash
xcodebuild -project TraeFlow.xcodeproj -scheme TraeFlow \
  -configuration Debug -destination 'platform=macOS,arch=arm64' \
  -derivedDataPath build/DerivedData CODE_SIGNING_ALLOWED=NO test \
  -only-testing:TraeFlowTests/DynamicAICompanionStoreTests \
  -only-testing:TraeFlowTests/DynamicDifyChatStoreTests \
  -only-testing:TraeFlowTests/NotchViewModelTests \
  -only-testing:TraeFlowTests/NotchViewControllerTransparencyTests \
  -only-testing:TraeFlowTests/TelemetryServiceTests
```

## 待处理的失败

失败集中在 `NotchViewModelTests` 的页面路由、尺寸、全屏显示和空闲状态断言。当前实现与测试期望存在差异，仍需逐项判断应修复行为还是更新规格；未通过修改断言掩盖失败。本次上传保留这些失败，并不表示所有功能已验证通过。

- `testBeginDetachedPresentationStartsInCompactInstancesMode()`：`XCTAssertEqual failed: ("customExpanded") is not equal to ("instances")`
- `testClickedSessionListUsesRoomierWidthThanCompactClosedNotch()`：`XCTAssertEqual failed: ("760.0") is not equal to ("520.0")`
- `testClosedHeightUsesDetectedSystemNotchHeight()`：`XCTAssertEqual failed: ("(380.0, 38.0)") is not equal to ("(266.0, 38.0)")`
- `testClosedWidthExpandsBeyondWiderDetectedSystemNotch()`：`XCTAssertEqual failed: ("380.0") is not equal to ("266.0")`
- `testClosingDetailViewResetsToSessionListForNextManualOpen()`：`XCTAssertEqual failed: ("customExpanded") is not equal to ("instances")`
- `testDeferredHoverOpenDoesNotOverrideActiveNotificationPresentation()`：`XCTAssertEqual failed: ("customExpanded") is not equal to ("instances")`
- `testDockedDetachmentLongPressNarrowsConfiguredClosedWidthOnPhysicalNotch()`：`XCTAssertEqualWithAccuracy failed: ("324.0") is not equal to ("218.12") +/- ("0.01")`
- `testFullscreenBrowserHidesWindowPresentationEvenOnPhysicalNotch()`：`XCTAssertTrue failed`
- `testIdleAutoHideTracksVisibleSessionActivity()`：`XCTAssertTrue failed`
- `testMinimumNotchModuleWidthSupportsIconOnlyPhysicalDisplayClosedWidth()`：`XCTAssertEqual failed: ("(70.0, 38.0)") is not equal to ("(64.0, 38.0)")`
- `testPhysicalNotchFullscreenStateIgnoresTransientWindowAnimationGap()`：`XCTAssertTrue failed`
- `testPhysicalNotchFullscreenStateRespectsHideInFullscreenDisabled()`：`XCTAssertTrue failed`
- `testPhysicalNotchFullscreenStateWaitsForStableExitSignal()`：`XCTAssertTrue failed`
- `testPresentNotificationAttentionClearsChatSoApprovalCardCanRouteFirst()`：`XCTAssertEqual failed: ("customExpanded") is not equal to ("instances")`
- `testPresentSessionListClearsSavedChatAndOpensManualList()`：`XCTAssertEqual failed: ("customExpanded") is not equal to ("instances")`
- `testPublishedNotchModuleWidthValueAppliesWithoutWaitingForProviderRefresh()`：`XCTAssertEqual failed: ("760.0") is not equal to ("520.0")`
- `testQuietBackgroundHidesClosedDockedPresentationButPreservesOpenedPanel()`：`XCTAssertTrue failed`
- `testRedockAfterDetachedRestoresClosedDockedStateAndResetsDetailSelection()`：`XCTAssertEqual failed: ("customExpanded") is not equal to ("instances")`
- `testScreenGeometryUpdateRefreshesClosedSizeAndPanelLimits()`：`XCTAssertEqual failed: ("760.0") is not equal to ("520.0")`
- `testToggleChatClosesWhenSameSessionIsAlreadyVisible()`：`XCTAssertEqual failed: ("customExpanded") is not equal to ("instances")`
- `testToggleSessionListClosesManualListWhenAlreadyOpen()`：`XCTAssertEqual failed: ("customExpanded") is not equal to ("instances")`

## 其他核对

- Markdown 本地链接、Git diff 空白检查通过。
- 发布 workflow 的 YAML 与 shell 语法检查、Sparkle 公私钥缺省／成对配置条件检查通过；未实际执行 GitHub Actions 打包。
- 本次仅同步源码与文档，未创建版本标签或签名／公证发行包。
