import Foundation
import Combine
import ServiceManagement
import UserNotifications
import os

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
        static let primaryMeter = "primaryMeter"
        static let hitZeroAt = "hitZeroAt"
        static let isNotificationsEnabled = "isNotificationsEnabled"
        static let showPercentInMenuBar = "showPercentInMenuBar"
        static let skippedVersion = "skippedVersion"
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

    /// Mostrar el porcentaje como texto junto al icono en la barra de menú.
    @Published var showPercentInMenuBar: Bool {
        didSet { UserDefaults.standard.set(showPercentInMenuBar, forKey: Key.showPercentInMenuBar) }
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

    /// De donde salen percent / resetProgress. No se persiste: el modo manual
    /// nunca debe sobrevivir a un reinicio (ver init).
    @Published var dataSource: DataSource {
        didSet {
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

    /// Indica si el observador de ~/.claude está activo. Si `open()` falla, el
    /// indicador se congela: lo exponemos para avisar en el popover.
    @Published var isWatcherActive: Bool = true

    /// Último error de instalación/desinstalación del hook (mensaje localizado),
    /// para mostrarlo en el popover. nil cuando todo va bien.
    @Published var hookError: String?

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
    @Published var latestVersionNotes: String = ""
    /// Versión que el usuario decidió omitir; no se vuelve a anunciar.
    @Published private(set) var skippedVersion: String

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
    private let log = Logger(subsystem: "local.margherita", category: "model")

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
        self.showPercentInMenuBar = d.bool(forKey: Key.showPercentInMenuBar)
        self.skippedVersion = d.string(forKey: Key.skippedVersion) ?? ""

        // El modo manual es solo para pruebas en vivo y nunca persiste:
        // arrancar siempre en statusLine para que un estado de datos falsos no
        // sobreviva a un reinicio. Sin datos aún se muestra el banner de espera.
        self.dataSource = .statusLine

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
            guard let self else { return }
            Task { @MainActor in self.tickResetProgress() }
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

    /// Meter que realmente alimenta el icono: el elegido por el usuario si está
    /// presente en el último payload; si no, `seven_day`, y si tampoco, el
    /// primero disponible. Evita que el icono se quede congelado en el
    /// placeholder cuando el plan del usuario no expone `seven_day`.
    var effectiveMeterKey: String? {
        if meters[primaryMeter] != nil { return primaryMeter }
        if meters[Self.defaultPrimaryMeter] != nil { return Self.defaultPrimaryMeter }
        return meters.keys.sorted().first
    }

    // MARK: - Texto y accesibilidad

    /// Duración localizada hasta `date`, usando la unidad mayor (min/horas/días).
    /// Fuente única reutilizada por notificaciones, cuenta atrás del popover y
    /// la etiqueta de VoiceOver.
    static func humanDuration(until date: Date, now: Date = Date()) -> String {
        let seconds = date.timeIntervalSince(now)
        if seconds < 60 { return Localizer.shared.tr("soon") }
        if seconds < 3600 { return Localizer.shared.tr("minutes", Int(seconds / 60)) }
        if seconds < 24 * 3600 { return Localizer.shared.tr("hours", Int(seconds / 3600)) }
        return Localizer.shared.tr("days", Int(seconds / (24 * 3600)))
    }

    /// Tiempo restante hasta el reset del meter activo (p. ej. "3 hora(s)"),
    /// o nil si no hay datos. Usado en el estado agotado.
    var resetETAText: String? {
        guard let key = effectiveMeterKey, let meter = meters[key] else { return nil }
        return Self.humanDuration(until: Date(timeIntervalSince1970: meter.resetsAtUnix))
    }

    /// Texto compacto para la barra de menú ("62%"), o nil si está oculto o aún
    /// no hay datos (en ese caso se muestra solo el icono de placeholder).
    var menuBarText: String? {
        guard showPercentInMenuBar else { return nil }
        if dataSource == .statusLine && updatedAt == nil { return nil }
        return "\(Int(percent.rounded()))%"
    }

    /// Etiqueta de VoiceOver para el icono de la barra de menú: verbaliza el
    /// estado completo (esperando / disponibilidad / agotado + ETA).
    var menuBarAccessibilityLabel: String {
        if dataSource == .statusLine && updatedAt == nil {
            return Localizer.shared.tr("a11y_waiting")
        }
        if percent > 0 {
            return Localizer.shared.tr("a11y_available", Int(percent.rounded()))
        }
        if let eta = resetETAText {
            return Localizer.shared.tr("a11y_exhausted", eta)
        }
        return Localizer.shared.tr("a11y_exhausted_no_eta")
    }

    /// Recalcula percent / resetProgress desde el meter primario.
    /// Solo tiene efecto en modo statusLine.
    func recompute() {
        guard dataSource == .statusLine else { return }
        guard let key = effectiveMeterKey, let meter = meters[key] else { return }

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
        resetProgress = newPercent <= 0 ? resetProgressValue(for: meter, key: key) : 0
    }

    private func tickResetProgress() {
        guard dataSource == .statusLine, percent == 0 else { return }
        recompute()
    }

    /// Progreso 0...100 entre el momento en que se agoto el uso y el reset.
    private func resetProgressValue(for meter: MeterData, key: String) -> Double {
        let resetsAt = Date(timeIntervalSince1970: meter.resetsAtUnix)
        // Sin ancla (app abierta ya estando en 0): asumir que el agotamiento
        // ocurrio una ventana completa antes del reset.
        let anchor = hitZeroAt
            ?? resetsAt.addingTimeInterval(-Self.windowSeconds(for: key))
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
        // Camino rápido: ubicaciones comunes (Homebrew, sistema, MacPorts, nix, asdf).
        let home = NSHomeDirectory()
        let commonPaths = [
            "/opt/homebrew/bin/jq", "/usr/local/bin/jq", "/usr/bin/jq", "/bin/jq",
            "/opt/local/bin/jq",                       // MacPorts
            "\(home)/.nix-profile/bin/jq",             // nix
            "\(home)/.asdf/shims/jq",                  // asdf
        ]
        if commonPaths.contains(where: { FileManager.default.fileExists(atPath: $0) }) {
            isJqInstalled = true
            return
        }
        // Fallback: resolver jq a través del PATH del shell de login del usuario
        // (como ejecuta Claude Code el hook). Se hace en segundo plano: cargar
        // los rc del shell puede tardar y no debe bloquear el hilo principal.
        Task.detached { [weak self] in
            let found = IndicatorModel.resolvesViaLoginShell("jq")
            guard let self else { return }
            await self.setJqInstalled(found)
        }
    }

    private func setJqInstalled(_ value: Bool) { isJqInstalled = value }

    /// `true` si `command -v <name>` resuelve algo en un shell de login del usuario.
    /// `nonisolated static` para poder correr fuera del hilo principal.
    nonisolated private static func resolvesViaLoginShell(_ name: String) -> Bool {
        // Solo aceptar nombres de binario simples; además se citan en comillas
        // simples al pasarlos al shell. Defensa frente a futuros llamadores.
        guard name.range(of: "^[A-Za-z0-9._-]+$", options: .regularExpression) != nil else {
            return false
        }
        let shell = ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: shell)
        proc.arguments = ["-lc", "command -v '\(name)'"]
        let pipe = Pipe()
        proc.standardOutput = pipe
        proc.standardError = Pipe()
        do {
            try proc.run()
            proc.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: data, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return proc.terminationStatus == 0 && !output.isEmpty
        } catch {
            Logger(subsystem: "local.margherita", category: "jq")
                .error("No se pudo resolver \(name, privacy: .public) vía shell: \(error.localizedDescription, privacy: .public)")
            return false
        }
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

    private enum SettingsError: LocalizedError {
        case notAnObject
        var errorDescription: String? { "settings.json no es un objeto JSON válido" }
    }

    /// Lee ~/.claude/settings.json de forma segura.
    /// - `.success(nil)`  → el archivo no existe (arrancar desde un objeto vacío).
    /// - `.success(dict)` → existe y parsea.
    /// - `.failure`       → existe pero NO se puede leer/parsear: NUNCA debemos
    ///   sobrescribirlo, contiene la configuración del usuario (otros hooks,
    ///   model, env…). Sobrescribir aquí era una pérdida de datos total.
    private func readSettings() -> Result<[String: Any]?, Error> {
        guard FileManager.default.fileExists(atPath: Self.settingsURL.path) else {
            return .success(nil)
        }
        do {
            let data = try Data(contentsOf: Self.settingsURL)
            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                return .failure(SettingsError.notAnObject)
            }
            return .success(json)
        } catch {
            return .failure(error)
        }
    }

    /// Escribe settings.json de forma atómica (temp + replaceItemAt), igual que
    /// el script hace `mv`. Evita dejar el archivo truncado si la app muere a
    /// media escritura — un settings.json corrupto rompe Claude Code entero.
    private func writeSettings(_ json: [String: Any]) throws {
        let data = try JSONSerialization.data(
            withJSONObject: json, options: [.prettyPrinted, .withoutEscapingSlashes]
        )
        let dir = Self.settingsURL.deletingLastPathComponent()
        let tmp = dir.appendingPathComponent(".settings.json.\(UUID().uuidString).tmp")
        // Si replaceItemAt/moveItem falla, no dejar el temp huérfano.
        defer { try? FileManager.default.removeItem(at: tmp) }
        try data.write(to: tmp)
        if FileManager.default.fileExists(atPath: Self.settingsURL.path) {
            _ = try FileManager.default.replaceItemAt(Self.settingsURL, withItemAt: tmp)
        } else {
            try FileManager.default.moveItem(at: tmp, to: Self.settingsURL)
        }
    }

    func installHook() {
        let folder = Self.settingsURL.deletingLastPathComponent()
        if !FileManager.default.fileExists(atPath: folder.path) {
            try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        }

        var json: [String: Any]
        switch readSettings() {
        case .success(let existing):
            json = existing ?? [:]
        case .failure(let error):
            log.error("No se instala el hook: settings.json ilegible: \(error.localizedDescription, privacy: .public)")
            hookError = Localizer.shared.tr("hook_error_unreadable")
            return
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
            try writeSettings(json)
            isHookInstalled = true
            hookError = nil
        } catch {
            log.error("Error al escribir settings.json: \(error.localizedDescription, privacy: .public)")
            hookError = Localizer.shared.tr("hook_error_write")
        }
    }

    func uninstallHook() {
        var json: [String: Any]
        switch readSettings() {
        case .success(let existing):
            guard let existing = existing else {
                // No hay archivo: nada que desinstalar.
                isHookInstalled = false
                return
            }
            json = existing
        case .failure(let error):
            log.error("No se desinstala el hook: settings.json ilegible: \(error.localizedDescription, privacy: .public)")
            hookError = Localizer.shared.tr("hook_error_unreadable")
            return
        }

        json.removeValue(forKey: "statusLine")

        do {
            try writeSettings(json)
            isHookInstalled = false
            hookError = nil
        } catch {
            log.error("Error al escribir settings.json: \(error.localizedDescription, privacy: .public)")
            hookError = Localizer.shared.tr("hook_error_write")
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

        let timeText = Self.humanDuration(until: Date(timeIntervalSince1970: meter.resetsAtUnix))

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
        return Localizer.shared.meterLabel(key)
    }

    // MARK: - Actualizaciones Automáticas
    func checkUpdates() {
        // No tocar la red durante los tests.
        guard ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil else { return }
        guard let url = URL(string: "https://api.github.com/repos/f3r21/Margherita/releases/latest") else { return }
        var request = URLRequest(url: url)
        request.timeoutInterval = 10
        request.setValue("Margherita/\(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.1.0") (Macintosh; macOS)", forHTTPHeaderField: "User-Agent")

        URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            guard let data = data, error == nil else { return }
            // GitHub limita las llamadas anónimas (60/h → 403): sin este guard
            // se decodificaría el cuerpo de error como basura silenciosa.
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { return }

            struct Release: Codable {
                let tag_name: String
                let html_url: String
                let body: String?
            }

            do {
                let release = try JSONDecoder().decode(Release.self, from: data)
                let latestVersion = release.tag_name.trimmingCharacters(in: CharacterSet(charactersIn: "vV"))
                let currentVersion = (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.1.0")
                    .trimmingCharacters(in: CharacterSet(charactersIn: "vV"))

                guard latestVersion.compare(currentVersion, options: .numeric) == .orderedDescending else { return }

                Task { @MainActor [weak self] in
                    guard let self = self else { return }
                    // Respetar la versión que el usuario decidió omitir.
                    guard release.tag_name != self.skippedVersion else { return }
                    self.latestVersionString = release.tag_name
                    self.latestVersionURL = release.html_url
                    self.latestVersionNotes = (release.body ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
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
            } catch {
                Logger(subsystem: "local.margherita", category: "updates")
                    .error("Error decodificando releases de GitHub: \(error.localizedDescription, privacy: .public)")
            }
        }.resume()
    }

    /// Omite la versión anunciada actualmente: no se vuelve a mostrar el banner
    /// hasta que aparezca una versión más reciente.
    func skipCurrentUpdate() {
        guard !latestVersionString.isEmpty else { return }
        skippedVersion = latestVersionString
        UserDefaults.standard.set(skippedVersion, forKey: Key.skippedVersion)
        isUpdateAvailable = false
        latestVersionString = ""
        latestVersionURL = ""
        latestVersionNotes = ""
    }
}
