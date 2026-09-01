import Foundation

/// Mulberry32 seeded pseudorandom number generator.
/// Matches the JavaScript mulberry32() implementation in the reference HTML for seed reproducibility.
struct SeededRNG: Codable {
    private var state: UInt32
    
    init(seed: UInt32) {
        self.state = seed
    }
    
    /// Returns next random Double in [0, 1)
    mutating func next() -> Double {
        state &+= 0x6D2B79F5
        var t = state
        t = (t ^ (t >> 15)) &* (t | 1)
        t ^= t &+ ((t ^ (t >> 7)) &* (t | 61))
        t ^= (t >> 14)
        return Double(t) / 4294967296.0
    }
    
    /// Returns random Double in [lo, hi)
    mutating func range(_ lo: Double, _ hi: Double) -> Double {
        return next() * (hi - lo) + lo
    }
    
    /// Returns random Int in [lo, hi)
    mutating func rangeInt(_ lo: Int, _ hi: Int) -> Int {
        guard hi > lo else { return lo }
        return lo + Int(next() * Double(hi - lo))
    }
    
    /// Returns random element from array
    mutating func pick<T>(from array: [T]) -> T {
        let idx = rangeInt(0, array.count)
        return array[idx]
    }
}
