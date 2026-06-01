import CoreGraphics
import Foundation

/// Geometría pura del indicador, compartida por `IconRenderer` (AppKit,
/// Y-arriba) y por `IndicatorPreview` (SwiftUI Canvas, Y-abajo). Centraliza la
/// aritmética que antes estaba duplicada en ambos renderizadores —recuento de
/// segmentos, vértices del polígono y barrido del wedge— para que no puedan
/// desincronizarse al editar uno y olvidar el otro.
enum IndicatorGeometry {

    /// Alpha del estado "esperando reset" (sensación de gris).
    static let resetAlpha: CGFloat = 0.55

    /// Alpha del trazo del placeholder punteado.
    static let placeholderAlpha: CGFloat = 0.6

    static func clampPercent(_ v: Double) -> Double { min(100.0, max(0.0, v)) }

    /// Barrido del wedge del círculo en grados (AppKit) y radianes (Canvas).
    static func sweepDegrees(forPercent percent: Double) -> Double {
        clampPercent(percent) / 100.0 * 360.0
    }
    static func sweepRadians(forPercent percent: Double) -> Double {
        clampPercent(percent) / 100.0 * 2.0 * .pi
    }

    /// Nº de segmentos "disponibles" a pintar en estado 1: se rellenan los
    /// índices `[usedSegments ..< k]` (los primeros quedan vacíos = consumido).
    static func usedSegments(sides k: Int, percent: Double) -> Int {
        let used = 100.0 - clampPercent(percent)
        return Int((Double(k) * used / 100.0).rounded())
    }

    /// Nº de segmentos a pintar para el progreso de reset en estado 2: se
    /// rellenan los índices `[k - resetSegments ..< k]`.
    static func resetSegments(sides k: Int, resetProgress: Double) -> Int {
        Int((Double(k) * clampPercent(resetProgress) / 100.0).rounded())
    }

    /// Vértices de un polígono regular empezando en las 12 en punto.
    /// `yUp` = sistema AppKit (`NSImage(flipped: false)`); `false` = Canvas
    /// (Y-abajo). Ambas convenciones producen el mismo polígono visual con el
    /// mismo orden de índices, de modo que los rangos de segmentos coinciden.
    static func polygonVertices(center: CGPoint, radius: CGFloat, sides: Int, yUp: Bool) -> [CGPoint] {
        let k = max(3, sides)
        let base = yUp ? Double.pi / 2.0 : -Double.pi / 2.0
        let step = 2.0 * .pi / Double(k)
        return (0..<k).map { i in
            let a = yUp ? base + Double(i) * step : base - Double(i) * step
            return CGPoint(x: center.x + radius * CGFloat(cos(a)),
                           y: center.y + radius * CGFloat(sin(a)))
        }
    }
}
