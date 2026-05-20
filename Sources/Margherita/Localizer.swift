import Foundation

enum Language: String {
    case spanish = "es"
    case english = "en"
}

struct Localizer {
    static let shared = Localizer()
    
    let language: Language
    
    init() {
        // Detectar idioma del sistema
        let localeLang = Locale.current.language.languageCode?.identifier ?? "en"
        if localeLang.hasPrefix("es") {
            self.language = .spanish
        } else {
            self.language = .english
        }
    }
    
    func tr(_ key: String, _ args: CVarArg...) -> String {
        let format = translations[key]?[language] ?? key
        if args.isEmpty {
            return format
        }
        return String(format: format, arguments: args)
    }
    
    private let translations: [String: [Language: String]] = [
        "waiting_data": [.spanish: "Esperando datos iniciales", .english: "Waiting for initial data"],
        "waiting_data_desc": [.spanish: "Realiza una pregunta en tu terminal con Claude Code para activar el indicador.", .english: "Ask a question in your terminal with Claude Code to activate the indicator."],
        "stale_data": [.spanish: "Datos desactualizados", .english: "Stale data"],
        "stale_data_desc": [.spanish: "No se han recibido actualizaciones en las últimas 12 horas. Consulta a Claude Code para refrescar.", .english: "No updates received in the last 12 hours. Consult Claude Code to refresh."],
        "source_claude": [.spanish: "Fuente: Claude Code (%@)", .english: "Source: Claude Code (%@)"],
        "source_manual": [.spanish: "Fuente: Manual (pruebas)", .english: "Source: Manual (testing)"],
        "jq_missing": [.spanish: "Dependencia 'jq' faltante", .english: "Missing dependency 'jq'"],
        "jq_missing_desc": [.spanish: "Requerido para procesar datos de Claude Code. Instálalo con 'brew install jq'.", .english: "Required to process Claude Code data. Install it with 'brew install jq'."],
        "claude_integration": [.spanish: "Integración Claude Code", .english: "Claude Code Integration"],
        "linked": [.spanish: "Vinculado", .english: "Linked"],
        "not_linked": [.spanish: "No vinculado", .english: "Not linked"],
        "unlink": [.spanish: "Desvincular", .english: "Unlink"],
        "link": [.spanish: "Vincular", .english: "Link"],
        "meter": [.spanish: "Meter", .english: "Meter"],
        "shape": [.spanish: "Figura", .english: "Shape"],
        "sides": [.spanish: "Lados", .english: "Sides"],
        "circle": [.spanish: "Círculo", .english: "Circle"],
        "polygon": [.spanish: "Polígono", .english: "Polygon"],
        "system_prefs": [.spanish: "Preferencias de Sistema", .english: "System Preferences"],
        "launch_at_login": [.spanish: "Iniciar al encender la Mac", .english: "Start at login"],
        "notifications_enable": [.spanish: "Notificar al agotar o restablecer cuota", .english: "Notify when quota is exceeded or reset"],
        "manual_slider": [.spanish: "Usar slider manual (pruebas)", .english: "Use manual slider (testing)"],
        "quit": [.spanish: "Salir", .english: "Quit"],
        "availability": [.spanish: "Disponibilidad", .english: "Availability"],
        "reset_progress": [.spanish: "Progreso reset", .english: "Reset progress"],
        "seven_day": [.spanish: "7 días", .english: "7 days"],
        "five_hour": [.spanish: "5 horas", .english: "5 hours"],
        "soon": [.spanish: "breve", .english: "soon"],
        "minutes": [.spanish: "%d minuto(s)", .english: "%d minute(s)"],
        "hours": [.spanish: "%d hora(s)", .english: "%d hour(s)"],
        "days": [.spanish: "%d día(s)", .english: "%d day(s)"],
        "quota_exceeded_title": [.spanish: "Límite de Claude alcanzado ⏳", .english: "Claude limit reached ⏳"],
        "quota_exceeded_body": [.spanish: "Has consumido el 100% de tu cuota (%@). Se restablecerá en %@.", .english: "You have consumed 100% of your quota (%@). It will reset in %@."],
        "quota_exceeded_test_title": [.spanish: "Límite de Claude alcanzado (Prueba) ⏳", .english: "Claude limit reached (Test) ⏳"],
        "quota_exceeded_test_body": [.spanish: "Has consumido el 100% de tu cuota de prueba. Esta es una notificación de prueba en modo manual.", .english: "You have consumed 100% of your test quota. This is a manual test notification."],
        "quota_reset_title": [.spanish: "Cuota de Claude restablecida ✅", .english: "Claude quota reset ✅"],
        "quota_reset_body": [.spanish: "Tu saldo de uso de Claude se ha restablecido por completo. ¡Ya puedes continuar programando!", .english: "Your Claude usage balance has been fully reset. You can now resume coding!"],
        "update_available_title": [.spanish: "Actualización disponible 🚀", .english: "Update available 🚀"],
        "update_available_body": [.spanish: "Una nueva versión (%@) está disponible. Haz clic para actualizar Margherita.", .english: "A new version (%@) is available. Click to update Margherita."]
    ]
}
