import CoreGraphics
import CoreText
import CoreVideo
import AppKit
import Foundation

/// Renders a single deterministic 1080x1920 video frame into a CGContext.
/// Used exclusively by VideoExporter for MP4 generation.
/// Pure Core Graphics + Core Text (thread-safe, high performance).
struct VideoFrameRenderer {
    
    // Export canvas dimensions (fixed - never changes)
    static let exportWidth: CGFloat = 1080
    static let exportHeight: CGFloat = 1920
    static let headerHeight: CGFloat = 260
    static let margin: CGFloat = 40
    
    // Header emoji/count font sizes
    static let headerEmojiSize: CGFloat = 92
    static let headerCountSize: CGFloat = 66
    static let percentBarHeight: CGFloat = 18
    static let percentBarY: CGFloat = 200
    
    // MARK: - Main render entry point
    
    static func renderFrame(
        state: SimulationState,
        settings: SimulationSettings,
        theme: Theme,
        context: CGContext,
        countdownValue: Int? = nil,
        introProgress: Double = 0.0,
        time: Double = 0.0,
        trailDots: [(type: EntityType, x: Double, y: Double, alpha: CGFloat)] = []
    ) {
        let W = exportWidth
        let H = exportHeight
        
        // Flip to a top-left origin so that video pixels (stored top-down) are
        // not rendered upside down. CGContext defaults to a bottom-left origin.
        context.saveGState()
        context.translateBy(x: 0, y: H)
        context.scaleBy(x: 1, y: -1)
        
        // Background
        context.setFillColor(theme.arenaCG)
        context.fill(CGRect(x: 0, y: 0, width: W, height: H))
        
        // Draw header
        drawHeader(state: state, theme: theme, context: context)
        
        // Draw arena
        drawArena(state: state, settings: settings, theme: theme, context: context, trailDots: trailDots)
        
        // Draw countdown overlay (over arena, not header)
        if let n = countdownValue {
            drawCountdown(n, context: context)
        }
        
        // Draw winner banner if applicable
        if state.winnerDeclared, let winner = state.winner {
            drawWinnerBanner(winner: winner, settings: settings, context: context, time: time)
        }
        
        // Draw confetti (over everything in arena area)
        if !state.confetti.isEmpty {
            drawConfetti(state: state, settings: settings, theme: theme, context: context)
        }
        
        // Draw branding
        if settings.brandingEnabled && !settings.brandingText.isEmpty {
            drawBranding(settings: settings, context: context)
        }
        
        // Intro overlay
        if introProgress > 0 {
            context.setFillColor(CGColor(srgbRed: 0, green: 0, blue: 0, alpha: introProgress))
            context.fill(CGRect(x: 0, y: 0, width: W, height: H))
        }
        
        context.restoreGState()
    }
    
    // MARK: - Header
    
    private static func drawHeader(state: SimulationState, theme: Theme, context: CGContext) {
        let W = exportWidth
        let colW = W / 3
        let headerMidY = headerHeight / 2 - 10
        
        let counts = [state.rockCount, state.paperCount, state.scissorsCount]
        let emojis = [EntityType.rock.emoji, EntityType.paper.emoji, EntityType.scissors.emoji]
        let total = state.totalCount
        
        for (i, (emoji, count)) in zip(emojis, counts).enumerated() {
            let cx = colW * CGFloat(i) + colW / 2
            
            // Emoji
            drawText(
                emoji,
                at: CGPoint(x: cx - 55, y: headerMidY),
                fontSize: headerEmojiSize,
                color: CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1),
                context: context,
                alignment: .center,
                isEmoji: true
            )
            
            // Count number
            drawText(
                "\(count)",
                at: CGPoint(x: cx + 45, y: headerMidY),
                fontSize: headerCountSize,
                color: theme.textCG,
                context: context,
                alignment: .left,
                isEmoji: false
            )
        }
        
        // Percentage bar
        let barX = margin
        let barY = percentBarY
        let barW = W - margin * 2
        let barH = percentBarHeight
        
        // Background
        context.setFillColor(CGColor(srgbRed: 0, green: 0, blue: 0, alpha: 0.3))
        let barRect = CGRect(x: barX, y: barY, width: barW, height: barH)
        context.addPath(CGPath(roundedRect: barRect, cornerWidth: 8, cornerHeight: 8, transform: nil))
        context.fillPath()
        
        // Segments
        if total > 0 {
            let segments: [(CGColor, Int)] = [
                (theme.rockBarCG, state.rockCount),
                (theme.paperBarCG, state.paperCount),
                (theme.scissorsBarCG, state.scissorsCount),
            ]
            var x = barX
            for (color, cnt) in segments {
                let w = barW * CGFloat(cnt) / CGFloat(total)
                if w > 0 {
                    context.setFillColor(color)
                    context.fill(CGRect(x: x, y: barY, width: w, height: barH))
                    x += w
                }
            }
        }
    }
    
    // MARK: - Arena
    
    private static func drawArena(
        state: SimulationState,
        settings: SimulationSettings,
        theme: Theme,
        context: CGContext,
        trailDots: [(type: EntityType, x: Double, y: Double, alpha: CGFloat)]
    ) {
        let W = exportWidth
        let H = exportHeight
        
        let areaX = margin
        let areaY = headerHeight + margin
        let areaW = W - margin * 2
        let areaH = H - headerHeight - margin * 2
        
        let simW = CGFloat(settings.arenaWidth)
        let simH = CGFloat(settings.arenaHeight)
        let scale = min(areaW / simW, areaH / simH)
        let drawW = simW * scale
        let drawH = simH * scale
        let drawX = areaX + (areaW - drawW) / 2
        let drawY = areaY + (areaH - drawH) / 2
        
        let arenaRect = CGRect(x: drawX, y: drawY, width: drawW, height: drawH)
        
        context.setFillColor(theme.arenaCG)
        context.fill(arenaRect)
        
        context.saveGState()
        context.addRect(arenaRect)
        context.clip()
        
        let cam = state.camera
        let camCX = CGFloat(cam.cx)
        let camCY = CGFloat(cam.cy)
        let camScale = CGFloat(cam.scale)
        
        context.translateBy(x: drawX + drawW / 2, y: drawY + drawH / 2)
        context.scaleBy(x: camScale * scale, y: camScale * scale)
        context.translateBy(x: -camCX, y: -camCY)
        
        let fontSize = CGFloat(settings.iconSize)
        
        // Motion trails: faded emoji at recent positions (drawn beneath entities).
        if !trailDots.isEmpty {
            for dot in trailDots {
                context.saveGState()
                context.setAlpha(dot.alpha)
                drawText(
                    dot.type.emoji,
                    at: CGPoint(x: CGFloat(dot.x), y: CGFloat(dot.y)),
                    fontSize: fontSize,
                    color: CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1),
                    context: context,
                    alignment: .center,
                    isEmoji: true
                )
                context.restoreGState()
            }
        }
        
        for entity in state.entities {
            drawText(
                entity.type.emoji,
                at: CGPoint(x: CGFloat(entity.x), y: CGFloat(entity.y)),
                fontSize: fontSize,
                color: CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1),
                context: context,
                alignment: .center,
                isEmoji: true
            )
        }
        
        context.restoreGState()
        
        context.setStrokeColor(theme.accentCG)
        context.setLineWidth(6)
        context.stroke(arenaRect)
    }
    
    // MARK: - Confetti
    
    private static func drawConfetti(
        state: SimulationState,
        settings: SimulationSettings,
        theme: Theme,
        context: CGContext
    ) {
        let areaX = margin
        let areaY = headerHeight + margin
        let areaW = exportWidth - margin * 2
        let areaH = exportHeight - headerHeight - margin * 2
        
        let simW = CGFloat(settings.arenaWidth)
        let simH = CGFloat(settings.arenaHeight)
        let scale = min(areaW / simW, areaH / simH)
        let drawW = simW * scale
        let drawH = simH * scale
        let drawX = areaX + (areaW - drawW) / 2
        let drawY = areaY + (areaH - drawH) / 2
        
        for p in state.confetti {
            let px = drawX + CGFloat(p.x) * scale + (drawW - simW * scale) / 2
            let py = drawY + CGFloat(p.y) * scale + (drawH - simH * scale) / 2
            let sz = CGFloat(p.size) * scale
            
            context.saveGState()
            context.translateBy(x: px, y: py)
            context.rotate(by: CGFloat(p.rot) * .pi / 180)
            context.setFillColor(CONFETTI_COLORS[p.colorIndex % CONFETTI_COLORS.count])
            context.fill(CGRect(x: -sz/2, y: -sz*0.3, width: sz, height: sz*0.6))
            context.restoreGState()
        }
    }
    
    // MARK: - Winner Banner
    
    private static func drawWinnerBanner(winner: EntityType, settings: SimulationSettings, context: CGContext, time: Double = 0.0) {
        let text = settings.winnerDisplayText(for: winner)
        switch settings.winnerDisplayStyle {
        case .banner:
            drawBannerStyle(text: text, context: context)
        case .center:
            drawCenterStyle(text: text, context: context)
        case .neonRainbow:
            drawNeonRainbow(text: text.uppercased(), context: context, time: time)
        }
    }
    
    /// Original look: compact dark pill near the top of the arena.
    private static func drawBannerStyle(text: String, context: CGContext) {
        let W = exportWidth
        let bannerY: CGFloat = headerHeight + margin + 30
        
        let maxTextW = W - margin * 2 - 80
        let fontSize = fittedFontSize(text, baseFontSize: 52, maxWidth: maxTextW, isEmoji: false)
        let padX: CGFloat = 40, padY: CGFloat = 20
        let textW = textWidth(text, fontSize: fontSize, isEmoji: false)
        let pillW = min(textW + padX * 2, W - margin * 2)
        let pillH = fontSize + padY * 2
        let pillX = (W - pillW) / 2
        
        context.setFillColor(CGColor(srgbRed: 0, green: 0, blue: 0, alpha: 0.7))
        let pillRect = CGRect(x: pillX, y: bannerY, width: pillW, height: pillH)
        context.addPath(CGPath(roundedRect: pillRect, cornerWidth: 30, cornerHeight: 30, transform: nil))
        context.fillPath()
        
        drawText(
            text,
            at: CGPoint(x: W / 2, y: bannerY + pillH / 2),
            fontSize: fontSize,
            color: CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1),
            context: context,
            alignment: .center,
            isEmoji: false
        )
    }
    
    /// Larger text centered in the middle of the frame.
    private static func drawCenterStyle(text: String, context: CGContext) {
        let W = exportWidth
        let H = exportHeight
        let center = CGPoint(x: W / 2, y: H / 2)
        
        let maxTextW = W - margin * 2 - 96
        let fontSize = fittedFontSize(text, baseFontSize: 120, maxWidth: maxTextW, isEmoji: false)
        let padX: CGFloat = 48, padY: CGFloat = 32
        let textW = textWidth(text, fontSize: fontSize, isEmoji: false)
        let pillW = min(textW + padX * 2, W - margin * 2)
        let pillH = fontSize + padY * 2
        let pillX = (W - pillW) / 2
        let pillY = center.y - pillH / 2
        
        context.setFillColor(CGColor(srgbRed: 0, green: 0, blue: 0, alpha: 0.72))
        let pillRect = CGRect(x: pillX, y: pillY, width: pillW, height: pillH)
        context.addPath(CGPath(roundedRect: pillRect, cornerWidth: 44, cornerHeight: 44, transform: nil))
        context.fillPath()
        
        drawText(
            text,
            at: center,
            fontSize: fontSize,
            color: CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1),
            context: context,
            alignment: .center,
            isEmoji: false
        )
    }
    
    /// Huge all-caps neon rainbow with chromatic aberration and blinking.
    private static func drawNeonRainbow(text: String, context: CGContext, time: Double) {
        let W = exportWidth
        let H = exportHeight
        let center = CGPoint(x: W / 2, y: H / 2)
        let maxTextW = W - margin * 2 - 40
        let fontSize = fittedFontSize(text, baseFontSize: 140, maxWidth: maxTextW, isEmoji: false)
        
        // Blink at ~4 Hz
        let blink = abs(sin(time * .pi * 4.0))
        let alpha: CGFloat = 0.45 + 0.55 * CGFloat(blink)
        
        // Cycling hue
        let hue = (time * 0.5).truncatingRemainder(dividingBy: 1.0)
        
        // Chromatic aberration: red/green/blue split copies behind the main text
        drawText(text, at: CGPoint(x: center.x - 14, y: center.y), fontSize: fontSize,
                 color: Self.hsv(hue + 0.0, 1.0, 1.0, alpha * 0.55), context: context, alignment: .center)
        drawText(text, at: CGPoint(x: center.x + 14, y: center.y), fontSize: fontSize,
                 color: Self.hsv(hue + 0.66, 1.0, 1.0, alpha * 0.55), context: context, alignment: .center)
        drawText(text, at: CGPoint(x: center.x, y: center.y - 10), fontSize: fontSize,
                 color: Self.hsv(hue + 0.33, 1.0, 1.0, alpha * 0.55), context: context, alignment: .center)
        drawText(text, at: CGPoint(x: center.x, y: center.y + 10), fontSize: fontSize,
                 color: Self.hsv(hue + 0.33, 1.0, 1.0, alpha * 0.55), context: context, alignment: .center)
        
        // Bright main copy
        drawText(text, at: center, fontSize: fontSize,
                 color: Self.hsv(hue, 0.35, 1.0, alpha), context: context, alignment: .center)
    }
    
    /// HSV -> CGColor helper for rainbow effects.
    private static func hsv(_ h: Double, _ s: Double, _ v: Double, _ a: CGFloat) -> CGColor {
        let hh = (h - floor(h)) * 6.0
        let i = Int(hh) % 6
        let f = hh - floor(hh)
        let p = v * (1 - s)
        let q = v * (1 - f * s)
        let t = v * (1 - (1 - f) * s)
        let (r, g, b): (Double, Double, Double)
        switch i {
        case 0: (r, g, b) = (v, t, p)
        case 1: (r, g, b) = (q, v, p)
        case 2: (r, g, b) = (p, v, t)
        case 3: (r, g, b) = (p, q, v)
        case 4: (r, g, b) = (t, p, v)
        default: (r, g, b) = (v, p, q)
        }
        return CGColor(srgbRed: r, green: g, blue: b, alpha: a)
    }
    
    // MARK: - Countdown
    
    private static func drawCountdown(_ n: Int, context: CGContext) {
        let W = exportWidth
        let H = exportHeight
        
        context.setFillColor(CGColor(srgbRed: 0, green: 0, blue: 0, alpha: 0.5))
        context.fill(CGRect(x: 0, y: headerHeight, width: W, height: H - headerHeight))
        
        drawText(
            "\(n)",
            at: CGPoint(x: W / 2, y: (H + headerHeight) / 2),
            fontSize: 240,
            color: CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1),
            context: context,
            alignment: .center,
            isEmoji: false
        )
    }
    
    // MARK: - Branding
    
    private static func drawBranding(settings: SimulationSettings, context: CGContext) {
        guard !settings.brandingText.isEmpty else { return }
        let W = exportWidth
        let H = exportHeight
        let alpha = settings.brandingOpacity
        let color = CGColor(srgbRed: 1, green: 1, blue: 1, alpha: alpha)
        
        let fontSize = fittedFontSize(settings.brandingText, baseFontSize: 36, maxWidth: W - margin * 2, isEmoji: false)
        
        drawText(
            settings.brandingText,
            at: CGPoint(x: W - margin, y: H - margin),
            fontSize: fontSize,
            color: color,
            context: context,
            alignment: .right,
            isEmoji: false
        )
    }
    
    // MARK: - Core Text Drawing Helper
    
    /// Measures the rendered width of a string at a given font size.
    private static func textWidth(_ text: String, fontSize: CGFloat, isEmoji: Bool) -> CGFloat {
        let fontName = isEmoji ? "Apple Color Emoji" : "Helvetica-Bold"
        let font = CTFontCreateWithName(fontName as CFString, fontSize, nil)
        let attrs: [CFString: Any] = [kCTFontAttributeName: font]
        guard let attrStr = CFAttributedStringCreate(kCFAllocatorDefault, text as CFString, attrs as CFDictionary) else { return 0 }
        let line = CTLineCreateWithAttributedString(attrStr)
        return CTLineGetBoundsWithOptions(line, .useOpticalBounds).width
    }
    
    /// Returns a font size reduced so the text fits within maxWidth.
    private static func fittedFontSize(_ text: String, baseFontSize: CGFloat, maxWidth: CGFloat, isEmoji: Bool) -> CGFloat {
        var size = baseFontSize
        while size > 12 && textWidth(text, fontSize: size, isEmoji: isEmoji) > maxWidth {
            size -= 4
        }
        return size
    }
    
    static func drawText(
        _ text: String,
        at point: CGPoint,
        fontSize: CGFloat,
        color: CGColor,
        context: CGContext,
        alignment: TextAlignment = .center,
        isEmoji: Bool = false
    ) {
        let fontName = isEmoji ? "Apple Color Emoji" : "Helvetica-Bold"
        let font = CTFontCreateWithName(fontName as CFString, fontSize, nil)
        
        let attrs: [CFString: Any] = [
            kCTFontAttributeName: font,
            kCTForegroundColorAttributeName: color
        ]
        
        guard let attrStr = CFAttributedStringCreate(kCFAllocatorDefault, text as CFString, attrs as CFDictionary) else { return }
        let line = CTLineCreateWithAttributedString(attrStr)
        let bounds = CTLineGetBoundsWithOptions(line, .useOpticalBounds)
        
        var drawX = point.x
        if alignment == .center {
            drawX -= bounds.width / 2
        } else if alignment == .right {
            drawX -= bounds.width
        }
        let drawY = point.y - bounds.height / 2
        
        context.saveGState()
        context.textMatrix = CGAffineTransform(scaleX: 1.0, y: -1.0)
        context.textPosition = CGPoint(x: drawX, y: drawY + bounds.height)
        CTLineDraw(line, context)
        context.restoreGState()
    }
    
    enum TextAlignment {
        case left, center, right
    }
    
    // MARK: - CVPixelBuffer creation helper
    
    static func renderToPixelBuffer(
        state: SimulationState,
        settings: SimulationSettings,
        theme: Theme,
        pixelBufferPool: CVPixelBufferPool,
        countdownValue: Int? = nil,
        introProgress: Double = 0.0,
        time: Double = 0.0
    ) -> CVPixelBuffer? {
        var pixelBuffer: CVPixelBuffer?
        let status = CVPixelBufferPoolCreatePixelBuffer(nil, pixelBufferPool, &pixelBuffer)
        guard status == kCVReturnSuccess, let pb = pixelBuffer else { return nil }
        
        CVPixelBufferLockBaseAddress(pb, [])
        defer { CVPixelBufferUnlockBaseAddress(pb, []) }
        
        guard let baseAddr = CVPixelBufferGetBaseAddress(pb) else { return nil }
        let bytesPerRow = CVPixelBufferGetBytesPerRow(pb)
        let width = CVPixelBufferGetWidth(pb)
        let height = CVPixelBufferGetHeight(pb)
        
        guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
              let ctx = CGContext(
                data: baseAddr,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: bytesPerRow,
                space: colorSpace,
                bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
              ) else { return nil }
        
        renderFrame(
            state: state,
            settings: settings,
            theme: theme,
            context: ctx,
            countdownValue: countdownValue,
            introProgress: introProgress,
            time: time
        )
        
        return pb
    }
}
