import Foundation
import Combine

enum IndicatorShape: String, CaseIterable, Identifiable {
    case circle
    case polygon
    var id: String { rawValue }
}

/// Origen de los datos que alimentan el indicador.
enum DataSource: String {
    /// Valores controlados por los sliders del popover (modo pruebas).
    case manual
    /// Valores derivados de ~/.claude/indicator.json (datos reales de Claude Code).
    case statusLine
}

@MainActor
final class IndicatorModel: ObservableObject {

    static let polygonSidesRange: ClosedRange<Int> = 3...10
    static let defaultPrimaryMeter = "seven_day"

    private static let isoFormatter = ISO8601DateFormatter()

    private enum Key {
        static let percent = "percent"
        static let resetProgress = "resetProgress"
        static let shape = "shape"
        static let polygonSides = "polygonSides"
        static let dataSource = "dataSource"
        static let primaryMeter = "primaryMeter"
        static let hitZeroAt = "hitZeroAt"
    }

    // MARK: - Entradas de render

    /// Disponibilidad actual de Claude, 0...100. Cuando es exactamente 0,
    /// el indicador entra en estado 2 (esperando reset). En modo statusLine
    /// este valor es derivado: lo escribe `recompute()`.
    @Published var percent: Double {
        didSet {
            let clamped = min(100.0, max(0.0, percent))
            if clamped != percent {
                percent = clamped
                return
            }
            UserDefaults.standard.set(percent, forKey: Key.percent)
        }
    }

    /// Progreso hacia el reset cuando ya no hay disponibilidad, 0...100.
    /// 0 = se acaba de agotar el uso. 100 = el reset esta a punto de ocurrir.
    @Published var resetProgress: Double {
        didSet {
            let clamped = min(100.0, max(0.0, resetProgress))
            if clamped != resetProgress {
                resetProgress = clamped
                return
            }
            UserDefaults.standard.set(resetProgress, forKey: Key.resetProgress)
        }
    }

    @Published var shape: IndicatorShape {
        didSet { UserDefaults.standard.set(shape.rawValue, forKey: Key.shape) }
    }

    @Published var polygonSides: Int {
        didSet {
            let r = Self.polygonSidesRange
            let clamped = min(r.upperBound, max(r.lowerBound, polygonSides))
            if clamped != polygonSides {
                polygonSides = clamped
                return
            }
            UserDefaults.standard.set(polygonSides, forKey: Key.polygonSides)
        }
    }

    // MARK: - Origen de datos

    /// De donde salen percent / resetProgress.
    @Published var dataSource: DataSource {
        didSet {
            UserDefaults.standard.set(dataSource.rawValue, forKey: Key.dataSource)
            if dataSource == .statusLine { recompute() }
        }
    }

    /// Meter que alimenta el icono cuando dataSource == .statusLine.
    @Published var primaryMeter: String {
        didSet {
            UserDefaults.standard.set(primaryMeter, forKey: Key.primaryMeter)
            recompute()
        }
    }

    /// Ultimos meters leidos del archivo. Transitorio, no se persiste.
    @Published private(set) var meters: [String: MeterData] = [:]

    /// Momento de la ultima escritura del archivo. Transitorio.
    @Published private(set) var updatedAt: Date?

    /// Instante en que `percent` toco 0 por ultima vez. Persistido para poder
    /// calcular el progreso de reset entre arranques de la app.
    private var hitZeroAt: Date? {
        didSet {
            let d = UserDefaults.standard
            if let t = hitZeroAt {
                d.set(t.timeIntervalSince1970, forKey: Key.hitZeroAt)
            } else {
                d.removeObject(forKey: Key.hitZeroAt)
            }
        }
    }

    private var watcher: RateLimitFileWatcher?
    private var resetTicker: Timer?

    init() {
        let d = UserDefaults.standard
        self.percent = (d.object(forKey: Key.percent) as? Double) ?? 100.0
        self.resetProgress = (d.object(forKey: Key.resetProgress) as? Double) ?? 0.0
        let shapeRaw = d.string(forKey: Key.shape) ?? IndicatorShape.circle.rawValue
        self.shape = IndicatorShape(rawValue: shapeRaw) ?? .circle
        self.polygonSides = (d.object(forKey: Key.polygonSides) as? Int) ?? 6
        self.primaryMeter = d.string(forKey: Key.primaryMeter) ?? Self.defaultPrimaryMeter

        if let raw = d.string(forKey: Key.dataSource),
           let stored = DataSource(rawValue: raw) {
            self.dataSource = stored
        } else {
            // Primer arranque: usar statusLine si el archivo ya existe.
            let exists = FileManager.default.fileExists(
                atPath: RateLimitFileWatcher.fileURL.path
            )
            self.dataSource = exists ? .statusLine : .manual
        }

        if let t = d.object(forKey: Key.hitZeroAt) as? Double {
            self.hitZeroAt = Date(timeIntervalSince1970: t)
        }

        // El watcher lee el archivo de inmediato y, si dataSource es
        // .statusLine, dispara el primer recompute() via applyStatusLineData.
        let fileWatcher = RateLimitFileWatcher(model: self)
        self.watcher = fileWatcher
        fileWatcher.start()

        // Mientras percent == 0, refrescar resetProgress aunque el archivo no
        // cambie: el progreso depende del reloj del sistema.
        self.resetTicker = Timer.scheduledTimer(
            withTimeInterval: 60, repeats: true
        ) { [weak self] _ in
            Task { @MainActor in self?.tickResetProgress() }
        }
    }

    // MARK: - Modo statusLine

    /// Aplica un payload recien leido del archivo. Llamado por el watcher.
    func applyStatusLineData(_ file: IndicatorFile) {
        meters = file.rateLimits
        updatedAt = Self.isoFormatter.date(from: file.updatedAt)
        if dataSource == .statusLine { recompute() }
    }

    /// Recalcula percent / resetProgress desde el meter primario.
    /// Solo tiene efecto en modo statusLine.
    func recompute() {
        guard dataSource == .statusLine else { return }
        guard let meter = meters[primaryMeter] else { return }

        let used = min(100.0, max(0.0, meter.usedPercentage))
        let newPercent = 100.0 - used

        if newPercent <= 0 {
            // Transicion real disponible -> agotado: anclar el inicio del reset.
            if percent > 0 { hitZeroAt = Date() }
        } else {
            hitZeroAt = nil
        }

        percent = newPercent
        resetProgress = newPercent <= 0 ? resetProgressValue(for: meter) : 0
    }

    private func tickResetProgress() {
        guard dataSource == .statusLine, percent == 0 else { return }
        recompute()
    }

    /// Progreso 0...100 entre el momento en que se agoto el uso y el reset.
    private func resetProgressValue(for meter: MeterData) -> Double {
        let resetsAt = Date(timeIntervalSince1970: meter.resetsAtUnix)
        // Sin ancla (app abierta ya estando en 0): asumir que el agotamiento
        // ocurrio una ventana completa antes del reset.
        let anchor = hitZeroAt
            ?? resetsAt.addingTimeInterval(-Self.windowSeconds(for: primaryMeter))
        let total = resetsAt.timeIntervalSince(anchor)
        guard total > 0 else { return 0 }
        let elapsed = Date().timeIntervalSince(anchor)
        return min(100.0, max(0.0, elapsed / total * 100.0))
    }

    private static func windowSeconds(for meter: String) -> TimeInterval {
        switch meter {
        case "seven_day": return 7 * 24 * 3600
        case "five_hour": return 5 * 3600
        default: return 5 * 3600
        }
    }
}
