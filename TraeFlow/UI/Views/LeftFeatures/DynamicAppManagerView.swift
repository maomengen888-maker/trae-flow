import AppKit
import SwiftUI

struct DynamicAppManagerView: View {
    @ObservedObject private var store = InstalledApplicationStore.shared
    @ObservedObject private var screenshotManager = DynamicScreenshotManager.shared
    @State private var pendingHideApplication: InstalledApplication?

    private let columns = [
        GridItem(.adaptive(minimum: 92, maximum: 128), spacing: 18, alignment: .top)
    ]

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.025, green: 0.045, blue: 0.085),
                    Color(red: 0.035, green: 0.075, blue: 0.13),
                    Color(red: 0.025, green: 0.04, blue: 0.08)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            VStack(spacing: 0) {
                if store.applications.isEmpty {
                    VStack(spacing: 10) {
                        Image(systemName: "square.grid.3x3")
                            .font(.system(size: 32, weight: .light))
                            .foregroundStyle(.cyan.opacity(0.8))
                        Text("没有可显示的 APP")
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ScrollView {
                        LazyVGrid(columns: columns, alignment: .leading, spacing: 20) {
                            ForEach(store.applications) { application in
                                appTile(application)
                            }
                        }
                        .padding(22)
                    }
                    .scrollIndicators(.hidden)
                }

                screenshotToolbar
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .confirmationDialog(
            pendingHideApplication.map { "从 Dynamic 隐藏“\($0.name)”？" } ?? "隐藏 APP？",
            isPresented: Binding(
                get: { pendingHideApplication != nil },
                set: { if !$0 { pendingHideApplication = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("从列表隐藏", role: .destructive) {
                if let application = pendingHideApplication {
                    store.hide(application)
                }
                pendingHideApplication = nil
            }
            Button("取消", role: .cancel) {
                pendingHideApplication = nil
            }
        } message: {
            Text("不会卸载或删除真实 App 文件。")
        }
        .onAppear { store.refresh() }
    }

    private var screenshotToolbar: some View {
        HStack(spacing: 10) {
            Button {
                screenshotManager.captureInteractive()
            } label: {
                HStack(spacing: 6) {
                    if screenshotManager.isCapturing {
                        ProgressView().controlSize(.small)
                    } else {
                        Image(systemName: "viewfinder")
                    }
                    Text(screenshotManager.isCapturing ? "正在截图" : "截图")
                }
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .padding(.horizontal, 12)
                .frame(height: 32)
            }
            .buttonStyle(.borderedProminent)
            .tint(.cyan)
            .disabled(screenshotManager.isCapturing)

            Text("⌃ ⇧ S")
                .font(.system(size: 9, weight: .medium, design: .monospaced))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 8)
                .frame(height: 24)
                .background(Color.white.opacity(0.05), in: Capsule())

            if let image = screenshotManager.latestImage {
                Divider().frame(height: 30)

                Image(nsImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 48, height: 30)
                    .clipShape(RoundedRectangle(cornerRadius: 5))
                    .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(Color.cyan.opacity(0.25)))

                Button {
                    screenshotManager.togglePinned()
                } label: {
                    Label(
                        screenshotManager.isPinned ? "取消置顶" : "固定置顶",
                        systemImage: screenshotManager.isPinned ? "pin.slash.fill" : "pin.fill"
                    )
                    .font(.system(size: 10, weight: .medium))
                }
                .buttonStyle(.bordered)
                .tint(.cyan)

                Button {
                    screenshotManager.revealLatestScreenshot()
                } label: {
                    Image(systemName: "folder")
                }
                .buttonStyle(.plain)
                .help("在 Finder 中查看截图")
            }

            if let errorMessage = screenshotManager.errorMessage {
                Text(errorMessage)
                    .font(.system(size: 9))
                    .foregroundStyle(.orange)
            }

            Spacer()
            Text("可选择区域、窗口或全屏，按 Esc 取消")
                .font(.system(size: 9))
                .foregroundStyle(.secondary.opacity(0.8))
        }
        .padding(.horizontal, 14)
        .frame(height: 54)
        .background(.ultraThinMaterial)
        .overlay(alignment: .top) {
            Rectangle().fill(Color.cyan.opacity(0.12)).frame(height: 1)
        }
    }

    private func appTile(_ application: InstalledApplication) -> some View {
        VStack(spacing: 9) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: application.url.path))
                .resizable()
                .interpolation(.high)
                .frame(width: 58, height: 58)
                .shadow(color: .cyan.opacity(0.16), radius: 10, y: 5)

            Text(application.name)
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .foregroundStyle(.white.opacity(0.9))
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(maxWidth: .infinity)
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 8)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 13, style: .continuous)
                .fill(Color.white.opacity(0.035))
                .overlay {
                    RoundedRectangle(cornerRadius: 13, style: .continuous)
                        .strokeBorder(Color.cyan.opacity(0.11), lineWidth: 1)
                }
        )
        .contentShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
        .onTapGesture(count: 2) {
            store.open(application)
        }
        .onLongPressGesture(minimumDuration: 0.7) {
            pendingHideApplication = application
        }
        .help("双击打开 · 长按隐藏")
    }
}
