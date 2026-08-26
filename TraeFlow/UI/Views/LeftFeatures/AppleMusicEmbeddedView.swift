import SwiftUI

/// macOS 不允许第三方应用托管另一个原生 App 的窗口，因此在 Dynamic 内加载
/// Apple Music 官方网页。它提供官方资料库、搜索、登录与播放界面，同时保持在弹窗内。
struct AppleMusicEmbeddedView: View {
    private static let entryURL = URL(string: "https://music.apple.com/cn/browse")!

    var body: some View {
        CustomAreaWebView(
            source: .remoteURL(Self.entryURL),
            keepsAlive: true,
            allowedRemoteDomains: ["apple.com"],
            enablesRemoteMediaPlayback: true
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}
