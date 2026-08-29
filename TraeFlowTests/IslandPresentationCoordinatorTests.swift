import AppKit
import XCTest
@testable import TRAE_FLOW

@MainActor
final class IslandPresentationCoordinatorTests: XCTestCase {
    private var originalSurfaceMode: IslandSurfaceMode!

    override func setUp() {
        super.setUp()
        originalSurfaceMode = AppSettings.surfaceMode
    }

    override func tearDown() {
        AppSettings.surfaceMode = originalSurfaceMode
        super.tearDown()
    }

    func testRedockDetachedRecreatesDockedWindow() throws {
        AppSettings.surfaceMode = .notch
        let screen = try XCTUnwrap(NSScreen.main)
        let coordinator = IslandPresentationCoordinator(screen: screen)

        // init 时已经创建了一次 docked window。
        XCTAssertEqual(coordinator.dockedWindowRecreationCount, 1)
        XCTAssertEqual(coordinator.viewModel.presentationMode, .docked)

        // 模拟宠物分离到桌面。
        coordinator.beginDetachment(from: IslandDetachmentRequest(
            source: .closed,
            dragStartScreenLocation: CGPoint(x: 100, y: 100),
            currentScreenLocation: CGPoint(x: 100, y: 150)
        ))
        XCTAssertEqual(coordinator.viewModel.presentationMode, .detached)

        // 宠物拖回 Flow 岛。
        coordinator.redockDetached()

        // 当前窗口策略在拖回时重建 docked 窗口，刷新事件与几何状态。
        XCTAssertEqual(coordinator.dockedWindowRecreationCount, 2)
        XCTAssertEqual(coordinator.viewModel.presentationMode, .docked)
        XCTAssertNotNil(coordinator.dockedWindowControllerForTesting)
    }

    func testRepeatedDetachAndRedockRecreatesOncePerCycle() throws {
        AppSettings.surfaceMode = .notch
        let screen = try XCTUnwrap(NSScreen.main)
        let coordinator = IslandPresentationCoordinator(screen: screen)

        XCTAssertEqual(coordinator.dockedWindowRecreationCount, 1)

        for _ in 0..<3 {
            coordinator.beginDetachment(from: IslandDetachmentRequest(
                source: .closed,
                dragStartScreenLocation: CGPoint(x: 100, y: 100),
                currentScreenLocation: CGPoint(x: 100, y: 150)
            ))
            XCTAssertEqual(coordinator.viewModel.presentationMode, .detached)

            coordinator.redockDetached()
            XCTAssertEqual(coordinator.viewModel.presentationMode, .docked)
        }

        // 初始化一次，随后每次 redock 各重建一次。
        XCTAssertEqual(coordinator.dockedWindowRecreationCount, 4)
        XCTAssertNotNil(coordinator.dockedWindowControllerForTesting)
    }
}
