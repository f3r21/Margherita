import Foundation
import Combine
import ServiceManagement
import UserNotifications

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
        static let isNotificationsEnabled = "isNotificationsEnabled"
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
            
            if dataSource == .manual {
                if percent == 0 && oldValue > 0 {
                    sendQuotaExceededNotificationManual()
                } else if percent > 0 && oldValue == 0 {
                    sendQuotaResetNotification()
                }
            }
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

    /// Evalúa si los datos tienen más de 12 horas de antigüedad
    var isDataStale: Bool {
        guard let updatedAt = updatedAt else { return false }
        return Date().timeIntervalSince(updatedAt) > 12 * 3600
    }

    /// Estado de instalación del hook de Claude Code.
    @Published var isHookInstalled: Bool = false

    /// Estado de presencia de jq en la Mac.
    @Published var isJqInstalled: Bool = false

    /// Estado de Launch at Login en macOS
    @Published var isLaunchAtLoginEnabled: Bool = false {
        didSet {
            toggleLaunchAtLogin(enabled: isLaunchAtLoginEnabled)
        }
    }

    /// Estado de notificaciones habilitadas
    @Published var isNotificationsEnabled: Bool = false {
        didSet {
            UserDefaults.standard.set(isNotificationsEnabled, forKey: Key.isNotificationsEnabled)
            if isNotificationsEnabled {
                requestNotificationPermissions()
            }
        }
    }

    // MARK: - Actualizaciones de la App
    @Published var isUpdateAvailable: Bool = false
    @Published var latestVersionString: String = ""
    @Published var latestVersionURL: String = ""

    static let settingsURL: URL = FileManager.default
        .homeDirectoryForCurrentUser
        .appendingPathComponent(".claude/settings.json")

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
        self.isNotificationsEnabled = d.bool(forKey: Key.isNotificationsEnabled)
        self.isLaunchAtLoginEnabled = SMAppService.mainApp.status == .enabled

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

        checkJqInstallation()
        checkHookInstallation()
        checkUpdates()
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
        let oldPercent = percent

        if newPercent <= 0 {
            if oldPercent > 0 {
                hitZeroAt = Date()
                sendQuotaExceededNotification(for: meter)
            }
        } else {
            hitZeroAt = nil
            if oldPercent == 0 {
                sendQuotaResetNotification()
            }
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

    // MARK: - Instalación de Hooks y jq

    func checkJqInstallation() {
        let paths = ["/opt/homebrew/bin/jq", "/usr/local/bin/jq", "/usr/bin/jq", "/bin/jq"]
        isJqInstalled = paths.contains { FileManager.default.fileExists(atPath: $0) }
    }

    func checkHookInstallation() {
        guard FileManager.default.fileExists(atPath: Self.settingsURL.path),
              let data = try? Data(contentsOf: Self.settingsURL),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let statusLine = json["statusLine"] as? [String: Any],
              let command = statusLine["command"] as? String else {
            isHookInstalled = false
            return
        }
        isHookInstalled = command.contains("statusline-indicator.sh")
    }

    func installHook() {
        let folder = Self.settingsURL.deletingLastPathComponent()
        if !FileManager.default.fileExists(atPath: folder.path) {
            try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        }

        var json: [String: Any] = [:]
        if FileManager.default.fileExists(atPath: Self.settingsURL.path),
           let data = try? Data(contentsOf: Self.settingsURL),
           let existing = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            json = existing
        }

        // Obtener ruta del script dentro del bundle
        let scriptPath: String
        if let bundledPath = Bundle.main.path(forResource: "statusline-indicator.sh", ofType: nil) {
            scriptPath = bundledPath
        } else {
            // Fallback si corre fuera de bundle (por ejemplo en desarrollo)
            scriptPath = "/Applications/Margherita.app/Contents/Resources/statusline-indicator.sh"
        }

        json["statusLine"] = [
            "type": "command",
            "command": scriptPath
        ]

        do {
            let data = try JSONSerialization.data(withJSONObject: json, options: [.prettyPrinted, .withoutEscapingSlashes])
            try data.write(to: Self.settingsURL)
            isHookInstalled = true
        } catch {
            print("Error al escribir settings.json: \(error)")
        }
    }

    func uninstallHook() {
        guard FileManager.default.fileExists(atPath: Self.settingsURL.path),
              let data = try? Data(contentsOf: Self.settingsURL),
              var json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return
        }

        json.removeValue(forKey: "statusLine")

        do {
            let data = try JSONSerialization.data(withJSONObject: json, options: [.prettyPrinted, .withoutEscapingSlashes])
            try data.write(to: Self.settingsURL)
            isHookInstalled = false
        } catch {
            print("Error al escribir settings.json: \(error)")
        }
    }

    // MARK: - Integración con macOS (Notificaciones y Login)

    private func toggleLaunchAtLogin(enabled: Bool) {
        let service = SMAppService.mainApp
        do {
            if enabled {
                if service.status != .enabled {
                    try service.register()
                }
            } else {
                if service.status == .enabled {
                    try service.unregister()
                }
            }
        } catch {
            print("Error al cambiar Launch at Login (SMAppService): \(error.localizedDescription)")
        }
    }

    private func requestNotificationPermissions() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { granted, error in
            if let error = error {
                print("Error al solicitar permisos de notificación: \(error)")
            }
        }
    }

    private func sendQuotaExceededNotification(for meter: MeterData) {
        guard isNotificationsEnabled else { return }
        
        let resetsAt = Date(timeIntervalSince1970: meter.resetsAtUnix)
        let seconds = resetsAt.timeIntervalSince(Date())
        let timeText: String
        
        if seconds <= 0 {
            timeText = Localizer.shared.tr("soon")
        } else if seconds < 3600 {
            let mins = Int(seconds / 60)
            timeText = Localizer.shared.tr("minutes", mins)
        } else if seconds < 24 * 3600 {
            let hours = Int(seconds / 3600)
            timeText = Localizer.shared.tr("hours", hours)
        } else {
            let days = Int(seconds / (24 * 3600))
            timeText = Localizer.shared.tr("days", days)
        }

        let content = UNMutableNotificationContent()
        content.title = Localizer.shared.tr("quota_exceeded_title")
        content.body = Localizer.shared.tr("quota_exceeded_body", meterLabel(primaryMeter), timeText)
        content.sound = .default

        let request = UNNotificationRequest(identifier: "Margherita.QuotaExceeded", content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }

    private func sendQuotaExceededNotificationManual() {
        guard isNotificationsEnabled else { return }

        let content = UNMutableNotificationContent()
        content.title = Localizer.shared.tr("quota_exceeded_test_title")
        content.body = Localizer.shared.tr("quota_exceeded_test_body")
        content.sound = .default

        let request = UNNotificationRequest(identifier: "Margherita.QuotaExceeded", content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }

    private func sendQuotaResetNotification() {
        guard isNotificationsEnabled else { return }

        let content = UNMutableNotificationContent()
        content.title = Localizer.shared.tr("quota_reset_title")
        content.body = Localizer.shared.tr("quota_reset_body")
        content.sound = .default

        let request = UNNotificationRequest(identifier: "Margherita.QuotaReset", content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }

    private func meterLabel(_ key: String) -> String {
        return Localizer.shared.tr(key)
    }

    // MARK: - Actualizaciones Automáticas
    func checkUpdates() {
        guard let url = URL(string: "https://api.github.com/repos/f3r21/Margherita/releases/latest") else { return }
        var request = URLRequest(url: url)
        request.setValue("Margherita/\(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.1.0") (Macintosh; macOS)", forHTTPHeaderField: "User-Agent")
        
        URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            guard let data = data, error == nil else { return }
            
            struct Release: Codable {
                let tag_name: String
                let html_url: String
            }
            
            do {
                let release = try JSONDecoder().decode(Release.self, from: data)
                let latestVersion = release.tag_name.trimmingCharacters(in: CharacterSet(charactersIn: "vV"))
                let currentVersion = (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.1.0")
                    .trimmingCharacters(in: CharacterSet(charactersIn: "vV"))
                
                if latestVersion.compare(currentVersion, options: .numeric) == .orderedDescending {
                    Task { @MainActor [weak self] in
                        guard let self = self else { return }
                        self.latestVersionString = release.tag_name
                        self.latestVersionURL = release.html_url
                        self.isUpdateAvailable = true
                        
                        if self.isNotificationsEnabled {
                            let content = UNMutableNotificationContent()
                            content.title = Localizer.shared.tr("update_available_title")
                            content.body = Localizer.shared.tr("update_available_body", release.tag_name)
                            content.sound = .default
                            let req = UNNotificationRequest(identifier: "Margherita.UpdateAvailable", content: content, trigger: nil)
                            UNUserNotificationCenter.current().add(req)
                        }
                    }
                }
            } catch {
                print("Error decodificando releases de GitHub: \(error)")
            }
        }.resume()
    }
}
