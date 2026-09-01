import SwiftUI
import CoreGraphics

struct Theme {
    let name: ThemeName
    // Raw CG colors for use in video rendering and SwiftUI
    let bg1CG: CGColor
    let bg2CG: CGColor
    let arenaCG: CGColor
    let accentCG: CGColor
    let panelCG: CGColor
    let textCG: CGColor
    let rockBarCG: CGColor    // #8b8fa3
    let paperBarCG: CGColor   // #e8b874
    let scissorsBarCG: CGColor // #ff5c7a
    
    // SwiftUI colors
    var bg1: Color { Color(bg1CG) }
    var bg2: Color { Color(bg2CG) }
    var arena: Color { Color(arenaCG) }
    var accent: Color { Color(accentCG) }
    var panel: Color { Color(panelCG) }
    var text: Color { Color(textCG) }
    var rockBar: Color { Color(rockBarCG) }
    var paperBar: Color { Color(paperBarCG) }
    var scissorsBar: Color { Color(scissorsBarCG) }
}

final class ThemeManager: ObservableObject {
    @Published var current: Theme = ThemeManager.theme(for: .default)
    
    func apply(_ name: ThemeName) {
        current = ThemeManager.theme(for: name)
    }
    
    static func theme(for name: ThemeName) -> Theme {
        switch name {
        case .default:
            return Theme(
                name: .default,
                bg1CG: cgColor(0x3548c4),
                bg2CG: cgColor(0x1a1e4d),
                arenaCG: cgColor(0x3a4bd1),
                accentCG: cgColor(0xff3d81),
                panelCG: cgColor(0x1d2050),
                textCG: CGColor(srgbRed: 0.949, green: 0.949, blue: 0.973, alpha: 1),
                rockBarCG: cgColor(0x8b8fa3),
                paperBarCG: cgColor(0xe8b874),
                scissorsBarCG: cgColor(0xff5c7a)
            )
        case .pastel:
            return Theme(
                name: .pastel,
                bg1CG: cgColor(0xffd6e8),
                bg2CG: cgColor(0xc9e4ff),
                arenaCG: cgColor(0xffe9f3),
                accentCG: cgColor(0xff6f9c),
                panelCG: cgColor(0xfff0f6),
                textCG: cgColor(0x5b3a52),
                rockBarCG: cgColor(0x8b8fa3),
                paperBarCG: cgColor(0xe8b874),
                scissorsBarCG: cgColor(0xff5c7a)
            )
        case .neon:
            return Theme(
                name: .neon,
                bg1CG: cgColor(0x1b0033),
                bg2CG: CGColor(srgbRed: 0, green: 0, blue: 0, alpha: 1),
                arenaCG: cgColor(0x0d0221),
                accentCG: cgColor(0x39ff14),
                panelCG: cgColor(0x120c26),
                textCG: cgColor(0x39ff14),
                rockBarCG: cgColor(0x8b8fa3),
                paperBarCG: cgColor(0xe8b874),
                scissorsBarCG: cgColor(0xff5c7a)
            )
        case .dark:
            return Theme(
                name: .dark,
                bg1CG: cgColor(0x2a2a2a),
                bg2CG: CGColor(srgbRed: 0, green: 0, blue: 0, alpha: 1),
                arenaCG: cgColor(0x161616),
                accentCG: cgColor(0xe63946),
                panelCG: cgColor(0x111111),
                textCG: CGColor(srgbRed: 0.918, green: 0.918, blue: 0.918, alpha: 1),
                rockBarCG: cgColor(0x8b8fa3),
                paperBarCG: cgColor(0xe8b874),
                scissorsBarCG: cgColor(0xff5c7a)
            )
        }
    }
    
    static func cgColor(_ hex: UInt32) -> CGColor {
        let r = Double((hex >> 16) & 0xFF) / 255.0
        let g = Double((hex >> 8) & 0xFF) / 255.0
        let b = Double(hex & 0xFF) / 255.0
        return CGColor(srgbRed: r, green: g, blue: b, alpha: 1.0)
    }
}
