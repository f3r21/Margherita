import AppKit
import Foundation

/// Renderiza el indicador como NSImage **template** para usar en MenuBarExtra.
///
/// Al ser template (`isTemplate = true`), macOS lee el icono como un mask
/// de alpha y lo tinta dinamicamente con el color de foreground apropiado
/// segun lo que haya detras de cada pixel (wallpaper + dark/light mode +
/// translucidez de la menu bar). Eso es lo que hace que los iconos del
/// sistema (CPU, RAM, GPU, bateria, etc.) se vuelvan blancos sobre fondo
/// oscuro y negros sobre fondo claro sin que la app haga nada.
///
/// Convencion del template: dibujamos todo en negro con distinto alpha.
/// El color hex no importa, solo el canal alpha:
///   - alpha 1.0 -> tint a maxima intensidad
///   - alpha 0.55 -> tint translucido (sensacion de "gris")
///   - alpha 0.0 (no dibujar) -> transparente, se ve el fondo
///
/// Dos estados:
///
/// Estado 1 (`percent > 0`): wedge **opaco** desde las 12 en sentido
/// **horario** cubriendo `(percent / 100) * 360 grados`. La parte "consumida"
/// (CCW desde 12) queda transparente y deja ver el fondo.
///
/// Estado 2 (`percent == 0`, `resetProgress > 0`): wedge **translucido** desde
/// las 12 en sentido **horario** cubriendo `(resetProgress / 100) * 360 grados`.
/// Cuando resetProgress = 0 el icono no pinta nada (queda solo el hotspot
/// invisible del status item).
enum IconRenderer {

    /// Tamano del icono en puntos. macOS escala a 2x en retina.
    static let pointSize = NSSize(width: 18, height: 18)

    static func render(
        percent: Double,
        resetProgress: Double,
        shape: IndicatorShape,
        polygonSides: Int,
        isPlaceholder: Bool = false,
        size: NSSize = pointSize
    ) -> NSImage {
        let image = NSImage(size: size, flipped: false) { rect in
            drawIndicator(
                in: rect,
                percent: percent,
                resetProgress: resetProgress,
                shape: shape,
                polygonSides: polygonSides,
                isPlaceholder: isPlaceholder
            )
            return true
        }
        image.isTemplate = true
        return image
    }

    private static func drawIndicator(
        in rect: NSRect,
        percent: Double,
        resetProgress: Double,
        shape: IndicatorShape,
        polygonSides: Int,
        isPlaceholder: Bool
    ) {
        let center = NSPoint(x: rect.midX, y: rect.midY)
        let radius = min(rect.width, rect.height) / 2.0 - 1.0
        let pct = min(100.0, max(0.0, percent))
        let reset = min(100.0, max(0.0, resetProgress))

        if isPlaceholder {
            drawPlaceholder(center: center, radius: radius, shape: shape, polygonSides: polygonSides)
            return
        }

        switch shape {
        case .circle:
            drawCircle(center: center, radius: radius, percent: pct, resetProgress: reset)
        case .polygon:
            drawPolygon(center: center, radius: radius,
                        k: max(3, polygonSides),
                        percent: pct, resetProgress: reset)
        }
    }

    private static func drawPlaceholder(
        center: NSPoint, radius: CGFloat,
        shape: IndicatorShape, polygonSides: Int
    ) {
        let path: NSBezierPath
        switch shape {
        case .circle:
            path = NSBezierPath(ovalIn: NSRect(
                x: center.x - radius, y: center.y - radius,
                width: radius * 2, height: radius * 2
            ))
        case .polygon:
            let verts = IndicatorGeometry.polygonVertices(
                center: center, radius: radius, sides: polygonSides, yUp: true
            )
            path = NSBezierPath()
            path.move(to: verts[0])
            for i in 1..<verts.count {
                path.line(to: verts[i])
            }
            path.close()
        }

        path.lineWidth = 1.0
        let pattern: [CGFloat] = [2.0, 2.0]
        path.setLineDash(pattern, count: 2, phase: 0.0)
        NSColor.black.withAlphaComponent(IndicatorGeometry.placeholderAlpha).setStroke()
        path.stroke()
    }

    // MARK: - Circulo (sin segmentos)

    private static func drawCircle(
        center: NSPoint, radius: CGFloat,
        percent: Double, resetProgress: Double
    ) {
        if percent > 0 {
            fillWedgeCW(center: center, radius: radius,
                        sweepDeg: IndicatorGeometry.sweepDegrees(forPercent: percent),
                        alpha: 1.0)
        } else if resetProgress > 0 {
            fillWedgeCW(center: center, radius: radius,
                        sweepDeg: IndicatorGeometry.sweepDegrees(forPercent: resetProgress),
                        alpha: IndicatorGeometry.resetAlpha)
        }
    }

    /// Pinta un pie slice desde las 12 en sentido horario por `sweepDeg`
    /// grados, en negro con el alpha dado. NSImage(flipped:false) usa
    /// Y-arriba: 12 en punto = 90 grados; horario visual = decrementar.
    private static func fillWedgeCW(
        center: NSPoint, radius: CGFloat,
        sweepDeg: Double, alpha: CGFloat
    ) {
        NSColor.black.withAlphaComponent(alpha).setFill()

        if sweepDeg >= 360 {
            NSBezierPath(ovalIn: NSRect(
                x: center.x - radius, y: center.y - radius,
                width: radius * 2, height: radius * 2
            )).fill()
            return
        }

        let path = NSBezierPath()
        path.move(to: center)
        path.appendArc(
            withCenter: center, radius: radius,
            startAngle: 90.0,
            endAngle: 90.0 - sweepDeg,
            clockwise: true
        )
        path.close()
        path.fill()
    }

    // MARK: - Poligono (K segmentos)
    //
    // Vertices ordenados CCW desde las 12 en Y-arriba (angulo creciente
    // desde pi/2). Con esa enumeracion:
    //
    // - El consumo en estado 1 ocupa los primeros `usedN` segmentos
    //   [0..<usedN] (que avanzan CCW desde 12). Esos NO se pintan
    //   (quedan transparentes). El resto [usedN..<K] se pinta opaco.
    //
    // - El gris en estado 2 ocupa los ultimos `grayN` segmentos
    //   [K-grayN..<K] (que avanzan CW desde 12 por como wrappea el
    //   indice). Se pintan con alpha resetAlpha; los demas quedan
    //   transparentes.

    private static func drawPolygon(
        center: NSPoint, radius: CGFloat, k: Int,
        percent: Double, resetProgress: Double
    ) {
        let vertices = IndicatorGeometry.polygonVertices(
            center: center, radius: radius, sides: k, yUp: true
        )

        func fillSegment(_ i: Int, alpha: CGFloat) {
            let path = NSBezierPath()
            path.move(to: center)
            path.line(to: vertices[i])
            path.line(to: vertices[(i + 1) % k])
            path.close()
            NSColor.black.withAlphaComponent(alpha).setFill()
            path.fill()
        }

        if percent > 0 {
            let usedN = IndicatorGeometry.usedSegments(sides: k, percent: percent)
            for i in usedN..<k {
                fillSegment(i, alpha: 1.0)
            }
        } else if resetProgress > 0 {
            let grayN = IndicatorGeometry.resetSegments(sides: k, resetProgress: resetProgress)
            for i in (k - grayN)..<k {
                fillSegment(i, alpha: IndicatorGeometry.resetAlpha)
            }
        }
    }
}
