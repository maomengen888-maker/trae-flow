import SwiftUI

/// AI 入口直接展示 DeepSeek 官方 Harness。
struct DynamicAIAgentView: View {
    var body: some View {
        DeepSeekHarnessView()
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.09), lineWidth: 1)
            }
            .onAppear {
                DeepSeekHarnessManager.shared.start()
            }
    }
}
