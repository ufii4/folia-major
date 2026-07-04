import SwiftUI

/// Folia's theme model, ported from src/App.tsx:77-96 and
/// shared/themeSanitizer.mjs. Colors are the exact upstream defaults —
/// "Midnight" (dark) and "Daylight" (light). Per-song AI themes (Gemini
/// pipeline in worker/generate-theme.ts) can layer on top later via the
/// server; the struct is already shaped for it.
public struct FoliaTheme: Equatable, Sendable {
    public var background: Color
    public var primary: Color
    public var secondary: Color
    public var accent: Color

    // App.tsx "Midnight": #09090b / #f4f4f5 / #71717a / accent #f4f4f5
    public static let midnight = FoliaTheme(
        background: Color(hex: 0x09090B),
        primary: Color(hex: 0xF4F4F5),
        secondary: Color(hex: 0x71717A),
        accent: Color(hex: 0xF4F4F5)
    )

    // App.tsx "Daylight": #f5f5f4 / #1c1917 / #44403c / accent #ea580c
    public static let daylight = FoliaTheme(
        background: Color(hex: 0xF5F5F4),
        primary: Color(hex: 0x1C1917),
        secondary: Color(hex: 0x44403C),
        accent: Color(hex: 0xEA580C)
    )

    public static func system(_ scheme: ColorScheme) -> FoliaTheme {
        scheme == .dark ? .midnight : .daylight
    }
}

public extension Color {
    init(hex: UInt32) {
        self.init(
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255
        )
    }
}

/// FluidBackground port (src/components/.../FluidBackground.tsx):
///   radial-gradient(circle at 20% 20%, accent×0x55, transparent 42%)
///   radial-gradient(circle at 80% 28%, secondary×0x50, transparent 44%)
///   radial-gradient(circle at 50% 78%, primary×0x28, transparent 52%)
/// over theme.backgroundColor, with a slow ambient drift.
public struct FluidBackground: View {
    let theme: FoliaTheme

    public init(theme: FoliaTheme) { self.theme = theme }

    public var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 20.0)) { ctx in
            let t = ctx.date.timeIntervalSinceReferenceDate / 14
            Canvas { context, size in
                context.fill(Path(CGRect(origin: .zero, size: size)),
                             with: .color(theme.background))
                let drift = { (phase: Double, amp: Double) -> CGSize in
                    CGSize(width: cos(t + phase) * amp, height: sin(t * 0.8 + phase) * amp)
                }
                blob(&context, size, at: CGPoint(x: 0.20, y: 0.20),
                     offset: drift(0, 26), radius: 0.42,
                     color: theme.accent.opacity(0x55 / 255.0))
                blob(&context, size, at: CGPoint(x: 0.80, y: 0.28),
                     offset: drift(2.1, 32), radius: 0.44,
                     color: theme.secondary.opacity(0x50 / 255.0))
                blob(&context, size, at: CGPoint(x: 0.50, y: 0.78),
                     offset: drift(4.2, 22), radius: 0.52,
                     color: theme.primary.opacity(0x28 / 255.0))
            }
        }
        .ignoresSafeArea()
    }

    private func blob(_ context: inout GraphicsContext, _ size: CGSize,
                      at anchor: CGPoint, offset: CGSize, radius: CGFloat,
                      color: Color) {
        let r = max(size.width, size.height) * radius
        let center = CGPoint(x: size.width * anchor.x + offset.width,
                             y: size.height * anchor.y + offset.height)
        let rect = CGRect(x: center.x - r, y: center.y - r, width: r * 2, height: r * 2)
        context.fill(
            Path(ellipseIn: rect),
            with: .radialGradient(
                Gradient(colors: [color, color.opacity(0)]),
                center: center, startRadius: 0, endRadius: r
            )
        )
    }
}
