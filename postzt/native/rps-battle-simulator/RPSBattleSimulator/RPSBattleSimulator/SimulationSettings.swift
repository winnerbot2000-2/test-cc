import Foundation

/// How the winner is presented on screen / in exported video.
enum WinnerDisplayStyle: String, CaseIterable, Codable {
    case banner        // small pill near the top (original look)
    case center        // large text centered in the frame
    case neonRainbow   // huge all-caps neon rainbow, blinking (brainrot mode)
    
    var displayName: String {
        switch self {
        case .banner: return "Banner"
        case .center: return "Center"
        case .neonRainbow: return "Neon Rainbow"
        }
    }
}

/// All configurable parameters for the simulation.
/// Codable for preset save/load. Same settings + seed = same simulation.
struct SimulationSettings: Codable, Equatable {
    
    // MARK: - Entity counts (for random/corners modes)
    var rockCount: Int = 30
    var paperCount: Int = 30
    var scissorsCount: Int = 30
    
    // MARK: - Spawn
    var spawnMode: SpawnMode = .random
    var activeClickType: EntityType = .rock
    var iconsPerClick: Int = 6
    
    // MARK: - Seed
    var seed: UInt32 = 1
    
    // MARK: - Arena (logical simulation space in points)
    var arenaWidth: Double = 380
    var arenaHeight: Double = 560
    
    // MARK: - Physics behavior
    var speed: Double = 1.2         // speed multiplier
    var iconSize: Double = 24       // font size in points
    var wobble: Double = 0.15       // random jitter strength
    var bounceStrength: Double = 0.6
    var minSpeed: Double = 0.9
    var maxSpeed: Double = 3.2
    
    // MARK: - Visual
    var trailsEnabled: Bool = false
    var theme: ThemeName = .default
    
    // MARK: - Audio
    var soundEnabled: Bool = false
    
    // MARK: - Finale
    var finaleEnabled: Bool = true
    var finaleThreshold: Int = 15
    
    // MARK: - Export / Recording
    var countdownEnabled: Bool = true
    var autoStopOnWinner: Bool = true
    var exportFPS: ExportFPS = .fps30
    var maxDuration: MaxDuration = .preset60
    var winnerHoldSeconds: Double = 2.0
    
    // MARK: - Short-form content
    var introEnabled: Bool = false
    var introDurationSeconds: Double = 1.5
    var customWinnerText: String = ""  // empty = auto: "🪨 Rock Wins!"
    var winnerDisplayStyle: WinnerDisplayStyle = .banner
    var brandingEnabled: Bool = false
    var brandingText: String = ""
    var brandingOpacity: Double = 0.7
    
    // MARK: - File output
    var filenamePrefix: String = "RPS_Battle"
    
    // Computed: icon radius
    var iconRadius: Double { iconSize * 0.5 }
    
    // Auto winner text for given winner
    func winnerDisplayText(for winner: EntityType) -> String {
        if !customWinnerText.isEmpty { return customWinnerText }
        return "\(winner.emoji) \(winner.name) Wins!"
    }
    
    /// Returns a copy with all values clamped to the ranges the UI enforces.
    /// Used when importing presets to protect against malformed data.
    func validated() -> SimulationSettings {
        var s = self
        s.rockCount = min(max(rockCount, 0), 240)
        s.paperCount = min(max(paperCount, 0), 240)
        s.scissorsCount = min(max(scissorsCount, 0), 240)
        s.iconsPerClick = min(max(iconsPerClick, 1), 50)
        s.arenaWidth = min(max(arenaWidth, 120), 1200)
        s.arenaHeight = min(max(arenaHeight, 120), 2400)
        s.speed = min(max(speed, 0.1), 10)
        s.iconSize = min(max(iconSize, 8), 120)
        s.wobble = min(max(wobble, 0), 2)
        s.bounceStrength = min(max(bounceStrength, 0.05), 4)
        s.minSpeed = min(max(minSpeed, 0.05), s.maxSpeed)
        s.maxSpeed = max(maxSpeed, s.minSpeed)
        s.finaleThreshold = min(max(finaleThreshold, 2), 100)
        s.winnerHoldSeconds = min(max(winnerHoldSeconds, 0.1), 30)
        s.introDurationSeconds = min(max(introDurationSeconds, 0.1), 30)
        s.brandingOpacity = min(max(brandingOpacity, 0.05), 1)
        if case .custom(let d) = s.maxDuration, d < 0.5 {
            s.maxDuration = .custom(0.5)
        }
        return s
    }
}
