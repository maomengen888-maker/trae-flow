import SwiftUI

enum DynamicAIAgentConfiguration {
    static let chatURL = URL(string: "https://udify.app/chat/WnWHNh7WYxeSa2UN")!
}

/// Dynamic 主面板内的 Dify Agent。复用远程 WebView，并在页面切换时保留会话状态。
struct DynamicAIAgentView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "sparkles")
                    .foregroundStyle(.cyan)

                Text("Dynamic AI")
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)

                Text("Dify Agent")
                    .font(.system(size: 10, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(0.55))

                Spacer()

                Circle()
                    .fill(Color.green)
                    .frame(width: 7, height: 7)
                Text("在线")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.white.opacity(0.65))
            }
            .padding(.horizontal, 4)

            CustomAreaWebView(
                source: .dynamicAgent(DynamicAIAgentConfiguration.chatURL),
                keepsAlive: true
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(red: 0.035, green: 0.055, blue: 0.09))
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(Color.cyan.opacity(0.18), lineWidth: 1)
            )
        }
        .padding(.horizontal, 2)
        .padding(.bottom, 2)
    }
}
