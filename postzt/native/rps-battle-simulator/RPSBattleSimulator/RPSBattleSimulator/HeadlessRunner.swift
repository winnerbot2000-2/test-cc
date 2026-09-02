import Foundation
import AVFoundation

/// Headless CLI export path.
///
/// TryPost invokes this as a subprocess with a JSON file describing a
/// `SimulationSettings` value and an output path. The JSON-file approach is used
/// (rather than stdin) because it is the most reliable hand-off from PHP: the
/// caller writes a small temp file and passes its path, avoiding any pipe
/// buffering or shell-escaping concerns.
///
/// Usage:
///   RPSBattleSimulator --headless --settings /tmp/settings.json --output /tmp/battle.mp4
///
/// Exit codes: 0 on success (MP4 written), 1 on any failure (with a message on stderr).
enum HeadlessRunner {

    static func run(arguments: [String]) -> Int32 {
        guard let settingsPath = value(for: "--settings", in: arguments) else {
            return fail("Missing --settings <path>")
        }
        guard let outputPath = value(for: "--output", in: arguments) else {
            return fail("Missing --output <path>")
        }

        let settings: SimulationSettings
        if settingsPath == "-" {
            do {
                let data = FileHandle.standardInput.readDataToEndOfFile()
                settings = try Self.decodeSettings(data)
            } catch {
                return fail("Could not decode SimulationSettings from stdin: \(error.localizedDescription)")
            }
        } else {
            do {
                let data = try Data(contentsOf: URL(fileURLWithPath: settingsPath))
                settings = try Self.decodeSettings(data)
            } catch {
                return fail("Could not decode SimulationSettings from \(settingsPath): \(error.localizedDescription)")
            }
        }

        let outputURL = URL(fileURLWithPath: outputPath)
        let theme = ThemeManager.theme(for: settings.theme)
        let job = ExportJob(
            settings: settings,
            theme: theme,
            outputURL: outputURL,
            videoIndex: 1
        )

        let exporter = VideoExporter()
        var failure: Error? = nil
        let semaphore = DispatchSemaphore(value: 0)

        Task {
            do {
                try await exporter.export(job: job) { _ in }
            } catch {
                failure = error
            }
            semaphore.signal()
        }
        semaphore.wait()

        if let failure {
            return fail("Export failed: \(failure.localizedDescription)")
        }

        guard FileManager.default.fileExists(atPath: outputURL.path) else {
            return fail("Export reported success but no file was written to \(outputPath)")
        }

        return 0
    }

    // MARK: - Helpers

    /// Decodes a `SimulationSettings` value from JSON, merging the incoming
    /// payload over the struct's built-in defaults. Callers only need to send
    /// the fields they wish to override; everything else falls back to the
    /// defaults already declared on `SimulationSettings`.
    private static func decodeSettings(_ data: Data) throws -> SimulationSettings {
        let defaultData = try JSONEncoder().encode(SimulationSettings())
        guard var merged = try JSONSerialization.jsonObject(with: defaultData) as? [String: Any] else {
            throw VideoExportError.writeFailed(NSError(domain: "HeadlessRunner", code: -1, userInfo: [NSLocalizedDescriptionKey: "Could not build default settings."]))
        }
        guard let incoming = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw VideoExportError.writeFailed(NSError(domain: "HeadlessRunner", code: -2, userInfo: [NSLocalizedDescriptionKey: "Settings JSON must be a JSON object."]))
        }
        for (key, value) in incoming {
            merged[key] = value
        }
        let mergedData = try JSONSerialization.data(withJSONObject: merged)
        return try JSONDecoder().decode(SimulationSettings.self, from: mergedData).validated()
    }

    private static func value(for flag: String, in arguments: [String]) -> String? {
        guard let idx = arguments.firstIndex(of: flag), idx + 1 < arguments.count else { return nil }
        return arguments[idx + 1]
    }

    @discardableResult
    private static func fail(_ message: String) -> Int32 {
        FileHandle.standardError.write(("RPSBattleSimulator: " + message + "\n").data(using: .utf8)!)
        return 1
    }
}
