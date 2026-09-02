import Foundation
import CoreGraphics

// MARK: - Entity Types

enum EntityType: Int, CaseIterable, Codable, Hashable {
    case rock = 0
    case paper = 1
    case scissors = 2
    
    var emoji: String {
        switch self {
        case .rock: return "🪨"
        case .paper: return "📄"
        case .scissors: return "✂️"
        }
    }
    
    var name: String {
        switch self {
        case .rock: return "Rock"
        case .paper: return "Paper"
        case .scissors: return "Scissors"
        }
    }
    
    // What this type beats
    var beats: EntityType {
        switch self {
        case .rock: return .scissors
        case .scissors: return .paper
        case .paper: return .rock
        }
    }
    
    var colorIndex: Int { rawValue }
}

enum SpawnMode: String, CaseIterable, Codable {
    case random
    case corners
    case click
    
    var displayName: String {
        switch self {
        case .random: return "Random"
        case .corners: return "Corners"
        case .click: return "Click to Place"
        }
    }
}

enum ThemeName: String, CaseIterable, Codable {
    case `default`
    case pastel
    case neon
    case dark
    
    var displayName: String {
        switch self {
        case .default: return "Default"
        case .pastel: return "Pastel"
        case .neon: return "Neon"
        case .dark: return "Dark"
        }
    }
}

// MARK: - Simulation Entities

struct Entity: Identifiable, Codable {
    var id: UInt64
    var type: EntityType
    var x: Double
    var y: Double
    var vx: Double
    var vy: Double
}

struct ConfettiParticle {
    var x: Double
    var y: Double
    var vx: Double
    var vy: Double
    var size: Double
    var rot: Double
    var rotSpeed: Double
    var colorIndex: Int
}

let CONFETTI_COLORS: [CGColor] = [
    CGColor(srgbRed: 1.0,   green: 0.239, blue: 0.506, alpha: 1), // #ff3d81
    CGColor(srgbRed: 1.0,   green: 0.824, blue: 0.247, alpha: 1), // #ffd23f
    CGColor(srgbRed: 0.239, green: 0.839, blue: 1.0,   alpha: 1), // #3dd6ff
    CGColor(srgbRed: 0.482, green: 1.0,   blue: 0.420, alpha: 1), // #7bff6b
    CGColor(srgbRed: 1.0,   green: 0.561, blue: 0.239, alpha: 1), // #ff8f3d
    CGColor(srgbRed: 0.769, green: 0.420, blue: 1.0,   alpha: 1), // #c46bff
    CGColor(srgbRed: 1.0,   green: 1.0,   blue: 1.0,   alpha: 1), // #ffffff
]

// MARK: - Camera State

struct CameraState {
    var cx: Double
    var cy: Double
    var scale: Double
    
    static func initial(arenaWidth: Double, arenaHeight: Double) -> CameraState {
        CameraState(cx: arenaWidth / 2, cy: arenaHeight / 2, scale: 1.0)
    }
}

// MARK: - Simulation State

struct SimulationState {
    var entities: [Entity]
    var confetti: [ConfettiParticle]
    var rng: SeededRNG
    var time: Double
    var winnerDeclared: Bool
    var winner: EntityType?
    var camera: CameraState
    var animSpeedFactor: Double
    var pendingConversions: Int
    var nextEntityId: UInt64
    
    var rockCount: Int { entities.filter { $0.type == .rock }.count }
    var paperCount: Int { entities.filter { $0.type == .paper }.count }
    var scissorsCount: Int { entities.filter { $0.type == .scissors }.count }
    var totalCount: Int { entities.count }
    
    static func empty(settings: SimulationSettings) -> SimulationState {
        let cam = CameraState.initial(arenaWidth: settings.arenaWidth, arenaHeight: settings.arenaHeight)
        return SimulationState(
            entities: [],
            confetti: [],
            rng: SeededRNG(seed: settings.seed),
            time: 0,
            winnerDeclared: false,
            winner: nil,
            camera: cam,
            animSpeedFactor: 1.0,
            pendingConversions: 0,
            nextEntityId: 0
        )
    }
}

// MARK: - Export Types

enum ExportFPS: Int, CaseIterable, Codable {
    case fps30 = 30
    case fps60 = 60
    
    var displayName: String {
        "\(rawValue) FPS"
    }
}

enum MaxDuration: Codable, Equatable, Hashable {
    case preset15
    case preset30
    case preset60
    case preset90
    case custom(Double)
    
    var seconds: Double {
        switch self {
        case .preset15: return 15
        case .preset30: return 30
        case .preset60: return 60
        case .preset90: return 90
        case .custom(let s): return s
        }
    }
    
    var displayName: String {
        switch self {
        case .preset15: return "15 sec"
        case .preset30: return "30 sec"
        case .preset60: return "60 sec"
        case .preset90: return "90 sec"
        case .custom(let s): return "\(Int(s)) sec"
        }
    }
    
    static var allPresets: [MaxDuration] { [.preset15, .preset30, .preset60, .preset90] }
    
    enum CodingKeys: String, CodingKey { case type, seconds }
    
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let t = try c.decode(String.self, forKey: .type)
        switch t {
        case "15": self = .preset15
        case "30": self = .preset30
        case "60": self = .preset60
        case "90": self = .preset90
        default:
            let s = try c.decode(Double.self, forKey: .seconds)
            self = .custom(s)
        }
    }
    
    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .preset15: try c.encode("15", forKey: .type)
        case .preset30: try c.encode("30", forKey: .type)
        case .preset60: try c.encode("60", forKey: .type)
        case .preset90: try c.encode("90", forKey: .type)
        case .custom(let s):
            try c.encode("custom", forKey: .type)
            try c.encode(s, forKey: .seconds)
        }
    }
}

enum BatchSeedMode: String, CaseIterable, Codable {
    case sequential
    case random
    var displayName: String { rawValue.capitalized }
}

struct BatchConfig {
    var count: Int = 10
    var seedMode: BatchSeedMode = .sequential
    var startingSeed: UInt32 = 1
    var randomizeSettings: Bool = false
}

struct BatchFailure: Identifiable, Equatable {
    var id: Int { index }
    var index: Int        // 1-based video number
    var filename: String
    var error: String
}

struct ExportProgress {
    var isExporting: Bool = false
    var isCancelled: Bool = false
    var currentFrame: Int = 0
    var totalFrames: Int = 0
    var message: String = ""
    var outputURL: URL? = nil
    var error: String? = nil
    
    var fraction: Double {
        totalFrames > 0 ? Double(currentFrame) / Double(totalFrames) : 0
    }
}

struct BatchProgress {
    var isRunning: Bool = false
    var isCancelled: Bool = false
    var currentVideo: Int = 0
    var totalVideos: Int = 0
    var currentSeed: UInt32 = 0
    var currentFilename: String = ""
    var currentFrameFraction: Double = 0
    var completedURLs: [URL] = []
    var failedIndices: [Int] = []
    var failures: [BatchFailure] = []
    var error: String? = nil
    var batchFolder: URL? = nil
    var manifestURL: URL? = nil
    
    var overallFraction: Double {
        guard totalVideos > 0 else { return 0 }
        let completed = Double(max(0, currentVideo - 1))
        return (completed + currentFrameFraction) / Double(totalVideos)
    }
}
