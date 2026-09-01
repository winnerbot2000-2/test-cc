import Foundation
import AppKit
import UniformTypeIdentifiers

/// A saved battle configuration that can be exported and imported.
struct BattlePreset: Codable {
    var name: String
    var settings: SimulationSettings
    var createdAt: Date
    var version: Int = BattlePreset.currentVersion

    static let fileExtension = "rpsbattle"
    static let currentVersion = 1
}

enum PresetError: LocalizedError {
    case unsupportedVersion(Int)
    case invalidData(String)

    var errorDescription: String? {
        switch self {
        case .unsupportedVersion(let v):
            return "This preset was created with a newer version (\(v)) and can't be opened."
        case .invalidData(let m):
            return "This preset file is invalid: \(m)"
        }
    }
}

/// Manages saving and loading battle presets as JSON files.
struct PresetManager {

    static func save(preset: BattlePreset, to url: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(preset)
        try data.write(to: url, options: .atomicWrite)
    }

    /// Loads and validates a preset, clamping values to safe ranges.
    static func load(from url: URL) throws -> BattlePreset {
        let data = try Data(contentsOf: url)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let preset = try decoder.decode(BattlePreset.self, from: data)
        if preset.version > BattlePreset.currentVersion {
            throw PresetError.unsupportedVersion(preset.version)
        }
        var p = preset
        p.settings = preset.settings.validated()
        return p
    }

    /// Shows a save dialog and saves the preset, throwing on failure.
    static func saveWithDialog(preset: BattlePreset) throws {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "\(preset.name).\(BattlePreset.fileExtension)"
        panel.title = "Save Battle Preset"
        if panel.runModal() == .OK, let url = panel.url {
            try save(preset: preset, to: url)
        }
    }

    /// Shows an open dialog and loads a preset, throwing on failure.
    static func loadWithDialog() throws -> BattlePreset {
        let panel = NSOpenPanel()
        panel.title = "Load Battle Preset"
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else {
            throw CocoaError(.userCancelled)
        }
        return try load(from: url)
    }
}
