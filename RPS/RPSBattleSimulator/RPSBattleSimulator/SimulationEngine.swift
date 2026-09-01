import Foundation

/// Pure-function simulation engine. All methods are static.
/// Same inputs always produce the same outputs (deterministic).
struct SimulationEngine {
    
    // MARK: - Spawn
    
    static func spawnFresh(settings: SimulationSettings) -> SimulationState {
        var state = SimulationState.empty(settings: settings)
        switch settings.spawnMode {
        case .random:
            spawnRandom(state: &state, settings: settings)
        case .corners:
            spawnCorners(state: &state, settings: settings)
        case .click:
            break  // starts empty; entities added via click-to-place
        }
        return state
    }
    
    /// Creates a simulation from an explicit entity layout (e.g. a click-to-place battle).
    static func spawnFromEntities(entities: [Entity], settings: SimulationSettings) -> SimulationState {
        var state = SimulationState.empty(settings: settings)
        state.entities = entities.map { e in
            var copy = e
            copy.x = min(max(copy.x, 0), settings.arenaWidth)
            copy.y = min(max(copy.y, 0), settings.arenaHeight)
            return copy
        }
        state.nextEntityId = UInt64(entities.count)
        return state
    }
    
    static func spawnRandom(state: inout SimulationState, settings: SimulationSettings) {
        let W = settings.arenaWidth
        let H = settings.arenaHeight
        let r = settings.iconRadius
        state.entities = []
        state.nextEntityId = 0
        for type in EntityType.allCases {
            let count: Int
            switch type {
            case .rock:     count = settings.rockCount
            case .paper:    count = settings.paperCount
            case .scissors: count = settings.scissorsCount
            }
            for _ in 0..<count {
                let x = state.rng.range(r + 4, W - r - 4)
                let y = state.rng.range(r + 4, H - r - 4)
                state.entities.append(makeEntity(type: type, x: x, y: y, state: &state, settings: settings))
            }
        }
    }
    
    static func spawnCorners(state: inout SimulationState, settings: SimulationSettings) {
        let W = settings.arenaWidth
        let H = settings.arenaHeight
        state.entities = []
        state.nextEntityId = 0
        // rock -> top-left region, scissors -> middle-right, paper -> bottom
        let regions: [(EntityType, Double, Double, Double, Double)] = [
            (.rock,     0.04, 0.55, 0.05, 0.35),
            (.scissors, 0.45, 0.96, 0.35, 0.65),
            (.paper,    0.05, 0.65, 0.65, 0.95),
        ]
        for (type, x0, x1, y0, y1) in regions {
            let count: Int
            switch type {
            case .rock:     count = settings.rockCount
            case .paper:    count = settings.paperCount
            case .scissors: count = settings.scissorsCount
            }
            for _ in 0..<count {
                let x = state.rng.range(x0 * W, x1 * W)
                let y = state.rng.range(y0 * H, y1 * H)
                state.entities.append(makeEntity(type: type, x: x, y: y, state: &state, settings: settings))
            }
        }
    }
    
    private static func makeEntity(type: EntityType, x: Double, y: Double,
                                    state: inout SimulationState, settings: SimulationSettings) -> Entity {
        let angle = state.rng.range(0, .pi * 2)
        let spd = state.rng.range(1.2, 2.2)
        let r = settings.iconRadius
        let id = state.nextEntityId
        state.nextEntityId += 1
        return Entity(
            id: id,
            type: type,
            x: min(max(x, r + 2), settings.arenaWidth - r - 2),
            y: min(max(y, r + 2), settings.arenaHeight - r - 2),
            vx: cos(angle) * spd,
            vy: sin(angle) * spd
        )
    }
    
    /// Maximum number of entities permitted to keep collision detection performant.
    static let maxEntities = 500
    
    static func addEntitiesAtPoint(x: Double, y: Double, type: EntityType,
                                    count: Int, state: inout SimulationState, settings: SimulationSettings) {
        // Cap total entities to avoid O(n^2) collision cost freezing the app.
        let remaining = max(0, maxEntities - state.entities.count)
        let toAdd = min(count, remaining)
        for _ in 0..<toAdd {
            let ox = state.rng.range(-30, 30)
            let oy = state.rng.range(-30, 30)
            state.entities.append(makeEntity(type: type, x: x + ox, y: y + oy, state: &state, settings: settings))
        }
    }
    
    // MARK: - Physics Tick
    
    /// Advance simulation by one logical tick.
    /// dt is the physics timestep (1.0 = one reference tick at 60Hz-equivalent).
    static func tick(state: inout SimulationState, settings: SimulationSettings, dt: Double = 1.0) {
        guard !state.entities.isEmpty else { return }
        
        state.pendingConversions = 0
        
        let W = settings.arenaWidth
        let H = settings.arenaHeight
        let r = settings.iconRadius
        let jitter = settings.wobble
        
        // Update finale speed factor
        let finaleActive = settings.finaleEnabled &&
                           state.entities.count > 0 &&
                           state.entities.count <= settings.finaleThreshold
        let targetSpeedFactor = finaleActive ? 0.35 : 1.0
        let lerpFactor = 0.06 * dt
        state.animSpeedFactor += (targetSpeedFactor - state.animSpeedFactor) * lerpFactor
        let effSpeed = settings.speed * state.animSpeedFactor * dt
        
        let minSp = settings.minSpeed
        let maxSp = settings.maxSpeed
        
        // Move entities
        for i in state.entities.indices {
            var e = state.entities[i]
            
            // Jitter
            e.vx += state.rng.range(-jitter, jitter) * 0.4
            e.vy += state.rng.range(-jitter, jitter) * 0.4
            
            // Speed clamp
            let sp = (e.vx * e.vx + e.vy * e.vy).squareRoot()
            if sp > maxSp {
                e.vx = e.vx / sp * maxSp
                e.vy = e.vy / sp * maxSp
            } else if sp < minSp && sp > 0 {
                e.vx = e.vx / sp * minSp
                e.vy = e.vy / sp * minSp
            } else if sp == 0 {
                // Give a random kick if stuck
                let ang = state.rng.range(0, .pi * 2)
                e.vx = cos(ang) * minSp
                e.vy = sin(ang) * minSp
            }
            
            // Move
            e.x += e.vx * effSpeed
            e.y += e.vy * effSpeed
            
            // Wall bounce
            if e.x < r { e.x = r; e.vx = abs(e.vx) }
            if e.x > W - r { e.x = W - r; e.vx = -abs(e.vx) }
            if e.y < r { e.y = r; e.vy = abs(e.vy) }
            if e.y > H - r { e.y = H - r; e.vy = -abs(e.vy) }
            
            state.entities[i] = e
        }
        
        // Entity-entity collision + conversion
        let minDist = r * 2 * 0.85
        let bounce = settings.bounceStrength
        let n = state.entities.count
        
        for i in 0..<n {
            for j in (i+1)..<n {
                let ax = state.entities[i].x, ay = state.entities[i].y
                let bx = state.entities[j].x, by = state.entities[j].y
                let dx = bx - ax, dy = by - ay
                let distSq = dx*dx + dy*dy
                let minDistSq = minDist * minDist
                
                if distSq < minDistSq && distSq > 0 {
                    let dist = distSq.squareRoot()
                    let overlap: Double = (minDist - dist) / 2.0
                    let nx: Double = dx / dist, ny: Double = dy / dist
                    
                    // Separate
                    state.entities[i].x -= nx * overlap
                    state.entities[i].y -= ny * overlap
                    state.entities[j].x += nx * overlap
                    state.entities[j].y += ny * overlap
                    
                    // Clamp back in bounds after separation
                    state.entities[i].x = min(max(state.entities[i].x, r), W - r)
                    state.entities[i].y = min(max(state.entities[i].y, r), H - r)
                    state.entities[j].x = min(max(state.entities[j].x, r), W - r)
                    state.entities[j].y = min(max(state.entities[j].y, r), H - r)
                    
                    // Convert
                    let typeA = state.entities[i].type
                    let typeB = state.entities[j].type
                    if typeA != typeB {
                        if typeA.beats == typeB {
                            state.entities[j].type = typeA
                            state.pendingConversions += 1
                        } else if typeB.beats == typeA {
                            state.entities[i].type = typeB
                            state.pendingConversions += 1
                        }
                    }
                    
                    // Bounce impulse
                    state.entities[i].vx -= nx * bounce
                    state.entities[i].vy -= ny * bounce
                    state.entities[j].vx += nx * bounce
                    state.entities[j].vy += ny * bounce
                }
            }
        }
        
        // Update camera
        updateCamera(state: &state, settings: settings, dt: dt)
        
        // Update time
        state.time += dt
        
        // Check winner (only if not already declared)
        if !state.winnerDeclared {
            checkWinner(state: &state)
        }
    }
    
    // MARK: - Winner Detection
    
    static func checkWinner(state: inout SimulationState) {
        let total = state.entities.count
        guard total > 0 else { return }
        
        let rockCount = state.entities.filter { $0.type == .rock }.count
        let paperCount = state.entities.filter { $0.type == .paper }.count
        let scissorsCount = state.entities.filter { $0.type == .scissors }.count
        
        let alive = [(EntityType.rock, rockCount), (EntityType.paper, paperCount), (EntityType.scissors, scissorsCount)]
            .filter { $0.1 > 0 }
        
        if alive.count == 1 {
            state.winnerDeclared = true
            state.winner = alive[0].0
        }
    }
    
    // MARK: - Camera
    
    static func updateCamera(state: inout SimulationState, settings: SimulationSettings, dt: Double = 1.0) {
        let W = settings.arenaWidth
        let H = settings.arenaHeight
        let r = settings.iconRadius
        let lerpK = 0.05 * dt
        
        let finaleActive = settings.finaleEnabled &&
                           state.entities.count > 0 &&
                           state.entities.count <= settings.finaleThreshold
        
        var targetCX = W / 2
        var targetCY = H / 2
        var targetScale = 1.0
        
        if finaleActive {
            var minX = Double.infinity, minY = Double.infinity
            var maxX = -Double.infinity, maxY = -Double.infinity
            for e in state.entities {
                minX = min(minX, e.x); maxX = max(maxX, e.x)
                minY = min(minY, e.y); maxY = max(maxY, e.y)
            }
            targetCX = (minX + maxX) / 2
            targetCY = (minY + maxY) / 2
            let spanX = max(maxX - minX, r * 4) + r * 8
            let spanY = max(maxY - minY, r * 4) + r * 8
            let s = min(W / spanX, H / spanY)
            targetScale = min(max(s, 1.0), 3.2)
        }
        
        state.camera.cx += (targetCX - state.camera.cx) * lerpK
        state.camera.cy += (targetCY - state.camera.cy) * lerpK
        state.camera.scale += (targetScale - state.camera.scale) * lerpK
    }
    
    // MARK: - Confetti
    
    static func spawnConfetti(state: inout SimulationState, settings: SimulationSettings) {
        let W = settings.arenaWidth
        let H = settings.arenaHeight
        state.confetti = []
        for _ in 0..<160 {
            let colorIdx = state.rng.rangeInt(0, CONFETTI_COLORS.count)
            state.confetti.append(ConfettiParticle(
                x: state.rng.range(0, W),
                y: state.rng.range(-H * 0.4, -10),
                vx: state.rng.range(-1.4, 1.4),
                vy: state.rng.range(2.0, 4.5),
                size: state.rng.range(5, 10),
                rot: state.rng.range(0, 360),
                rotSpeed: state.rng.range(-8, 8),
                colorIndex: colorIdx
            ))
        }
    }
    
    static func updateConfetti(state: inout SimulationState, settings: SimulationSettings, dt: Double = 1.0) {
        let H = settings.arenaHeight
        for i in state.confetti.indices {
            state.confetti[i].vy += 0.05 * dt
            state.confetti[i].x += state.confetti[i].vx * dt
            state.confetti[i].y += state.confetti[i].vy * dt
            state.confetti[i].rot += state.confetti[i].rotSpeed * dt
        }
        state.confetti.removeAll { $0.y > H + 30 }
    }
    
    // MARK: - Arena Resize
    
    static func clampEntities(state: inout SimulationState, settings: SimulationSettings) {
        let W = settings.arenaWidth
        let H = settings.arenaHeight
        let r = settings.iconRadius
        for i in state.entities.indices {
            state.entities[i].x = min(max(state.entities[i].x, r + 2), W - r - 2)
            state.entities[i].y = min(max(state.entities[i].y, r + 2), H - r - 2)
        }
    }
}
