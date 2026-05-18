import Foundation
import os

/// Datos de un meter individual, tal como los escribe statusline-indicator.sh.
struct MeterData: Codable, Equatable {
    let usedPercentage: Double
    let resetsAtUnix: Double

    enum CodingKeys: String, CodingKey {
        case usedPercentage = "used_percentage"
        case resetsAtUnix = "resets_at_unix"
    }
}

/// Estructura completa de ~/.claude/indicator.json.
struct IndicatorFile: Codable {
    let updatedAt: String
    let primaryMeter: String?
    let rateLimits: [String: MeterData]

    enum CodingKeys: String, CodingKey {
        case updatedAt = "updated_at"
        case primaryMeter = "primary_meter"
        case rateLimits = "rate_limits"
    }
}

/// Observa ~/.claude/indicator.json y empuja los cambios al IndicatorModel.
///
/// El script de statusLine reemplaza el archivo con un `mv` atomico, asi que
/// el inodo cambia en cada escritura. Observar el archivo directamente
/// perderia los reemplazos: por eso se observa el directorio padre y se
/// re-lee el archivo en cada evento.
@MainActor
final class RateLimitFileWatcher {

    /// ~/.claude/indicator.json
    static let fileURL: URL = FileManager.default
        .homeDirectoryForCurrentUser
        .appendingPathComponent(".claude/indicator.json")

    private weak var model: IndicatorModel?
    private var source: DispatchSourceFileSystemObject?
    private let log = Logger(subsystem: "local.claude-indicator", category: "watcher")

    init(model: IndicatorModel) {
        self.model = model
    }

    deinit {
        source?.cancel()
    }

    /// Lee el archivo una vez y arranca el watcher del directorio padre.
    func start() {
        readAndApply()
        startWatchingDirectory()
    }

    func stop() {
        source?.cancel()
        source = nil
    }

    private func startWatchingDirectory() {
        let directory = Self.fileURL.deletingLastPathComponent()
        let fd = open(directory.path, O_EVTONLY)
        guard fd >= 0 else {
            log.error("no se pudo abrir el directorio para observar")
            return
        }

        let src = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: [.write, .rename, .extend],
            queue: .main
        )
        src.setEventHandler { [weak self] in
            Task { @MainActor in self?.readAndApply() }
        }
        src.setCancelHandler {
            close(fd)
        }
        source = src
        src.resume()
    }

    private func readAndApply() {
        guard let model else { return }
        guard let data = try? Data(contentsOf: Self.fileURL) else { return }
        guard let file = try? JSONDecoder().decode(IndicatorFile.self, from: data) else {
            log.error("indicator.json no se pudo decodificar")
            return
        }
        model.applyStatusLineData(file)
    }
}
