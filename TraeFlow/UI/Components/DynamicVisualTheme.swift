import SwiftUI

/// 灵动岛主界面的统一视觉令牌。
///
/// 第三方网页保留自身主题；所有原生外壳、卡片、选中态和输入区域统一复用此处，
/// 避免各页面分别硬编码颜色后再次出现风格漂移。
enum DynamicVisualTheme {
    static let canvas = Color(red: 0.008, green: 0.010, blue: 0.016)
    static let card = Color(red: 0.075, green: 0.082, blue: 0.098)
    static let elevatedCard = Color(red: 0.102, green: 0.108, blue: 0.126)
    static let cyan = Color(red: 0.20, green: 0.88, blue: 0.96)
    static let violet = Color(red: 0.57, green: 0.36, blue: 0.98)
    static let orange = Color(red: 1.00, green: 0.49, blue: 0.19)

    static let outerRadius: CGFloat = 26
    static let panelRadius: CGFloat = 22
    static let cardRadius: CGFloat = 18

    static var neonGradient: LinearGradient {
        LinearGradient(
            colors: [cyan.opacity(0.72), violet.opacity(0.68), cyan.opacity(0.48)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    static var canvasGradient: LinearGradient {
        LinearGradient(
            colors: [canvas, Color(red: 0.018, green: 0.020, blue: 0.030), canvas],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
}

private struct DynamicSurfaceModifier: ViewModifier {
    let radius: CGFloat
    let focused: Bool
    let elevated: Bool
    let neonBorder: Bool

    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .fill(elevated ? DynamicVisualTheme.elevatedCard : DynamicVisualTheme.card)
            )
            .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(borderStyle, lineWidth: borderWidth)
            }
            .shadow(
                color: focused
                    ? DynamicVisualTheme.orange.opacity(0.16)
                    : (neonBorder ? DynamicVisualTheme.violet.opacity(0.10) : .clear),
                radius: focused ? 12 : (neonBorder ? 9 : 0),
                y: 4
            )
    }

    private var borderStyle: AnyShapeStyle {
        if focused {
            return AnyShapeStyle(DynamicVisualTheme.orange.opacity(0.96))
        }
        if neonBorder {
            return AnyShapeStyle(DynamicVisualTheme.neonGradient)
        }
        return AnyShapeStyle(Color.white.opacity(0.07))
    }

    private var borderWidth: CGFloat {
        focused ? 1.6 : (neonBorder ? 0.9 : 0.65)
    }
}

extension View {
    func dynamicSurface(
        radius: CGFloat = DynamicVisualTheme.cardRadius,
        focused: Bool = false,
        elevated: Bool = false,
        neonBorder: Bool = false
    ) -> some View {
        modifier(DynamicSurfaceModifier(
            radius: radius,
            focused: focused,
            elevated: elevated,
            neonBorder: neonBorder
        ))
    }
}
