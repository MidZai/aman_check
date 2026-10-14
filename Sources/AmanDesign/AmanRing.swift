import SwiftUI
import AmanCore

/// Géométrie de l'anneau d'Aman Disk, dans un espace 100 × 100 (AmanRing.swift).
public enum AmanRingGeometry {
    public static let radius: CGFloat = 26
    public static let lineWidth: CGFloat = 10

    /// Angle balayé : longueur = p × 2π × 26 − 10 (compense les extrémités arrondies) ; cercle complet à 100 %.
    public static func sweep(fraction: Double) -> CGFloat {
        let f = CGFloat(max(0, min(1, fraction)))
        if f >= 1 { return 2 * .pi }
        return max(0.001, f * 2 * .pi * radius - lineWidth) / radius
    }

    /// Goutte : `M50 37 C50 37 43.5 45.5 43.5 50 A6.5 6.5 0 0 0 56.5 50 C56.5 45.5 50 37 50 37 Z`.
    public static func dropPath(in rect: CGRect) -> CGPath {
        let s = min(rect.width, rect.height) / 100
        func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: rect.minX + x * s, y: rect.minY + y * s) }
        let path = CGMutablePath()
        path.move(to: p(50, 37))
        path.addCurve(to: p(43.5, 50), control1: p(50, 37), control2: p(43.5, 45.5))
        path.addArc(center: p(50, 50), radius: 6.5 * s, startAngle: .pi, endAngle: 0, clockwise: true)
        path.addCurve(to: p(50, 37), control1: p(56.5, 45.5), control2: p(50, 37))
        path.closeSubpath()
        return path
    }
}

/// Anneau de jauge d'Aman Disk (HealthRingView) : fond encre, piste, arc, centre.
/// `fraction == nil` : valeur inconnue, aucun arc (jamais un pourcentage inventé).
public struct AmanRing: View {
    public enum Center {
        case drop
        case symbol(String)
    }

    let fraction: Double?
    let color: Color
    let center: Center

    @State private var progress: Double = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(fraction: Double?, color: Color = AmanPalette.water, center: Center = .drop) {
        self.fraction = fraction
        self.color = color
        self.center = center
    }

    /// Couleur d'Aman Disk selon le statut : eau (bon), orange, rouge.
    public static func color(for status: CheckStatus) -> Color {
        switch status {
        case .watch: return AmanPalette.orange
        case .problem: return AmanPalette.red
        default: return AmanPalette.water
        }
    }

    public var body: some View {
        GeometryReader { geo in
            let side = min(geo.size.width, geo.size.height)
            let scale = side / 100
            ZStack {
                Circle().fill(AmanPalette.ink)
                Circle()
                    .inset(by: (50 - AmanRingGeometry.radius) * scale)
                    .stroke(Color.white.opacity(0.16), lineWidth: AmanRingGeometry.lineWidth * scale)
                if fraction != nil {
                    RingArc(fraction: progress)
                        .stroke(color, style: StrokeStyle(lineWidth: AmanRingGeometry.lineWidth * scale, lineCap: .round))
                }
                switch center {
                case .drop:
                    Path(AmanRingGeometry.dropPath(in: CGRect(x: 0, y: 0, width: side, height: side)))
                        .fill(Color.white)
                case .symbol(let name):
                    Image(systemName: name)
                        .font(.system(size: 20 * scale, weight: .semibold))
                        .foregroundStyle(.white)
                }
            }
            .frame(width: side, height: side)
        }
        .aspectRatio(1, contentMode: .fit)
        .onAppear { animate() }
        .onChange(of: fraction) { _ in animate() }
        .accessibilityHidden(true)
        .environment(\.layoutDirection, .leftToRight)
    }

    private func animate() {
        let target = fraction ?? 0
        if reduceMotion { progress = target } else { withAnimation(.easeOut(duration: 0.6)) { progress = target } }
    }
}

/// Arc partant de midi, sens horaire, avec la règle de longueur de l'icône.
private struct RingArc: Shape {
    var fraction: Double

    var animatableData: Double {
        get { fraction }
        set { fraction = newValue }
    }

    func path(in rect: CGRect) -> Path {
        guard fraction > 0 else { return Path() }
        let side = min(rect.width, rect.height)
        let scale = side / 100
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let sweep = AmanRingGeometry.sweep(fraction: fraction)
        var path = Path()
        path.addArc(center: center, radius: AmanRingGeometry.radius * scale, startAngle: .radians(-.pi / 2),
                    endAngle: .radians(-.pi / 2 + Double(sweep)), clockwise: false)
        return path
    }
}
