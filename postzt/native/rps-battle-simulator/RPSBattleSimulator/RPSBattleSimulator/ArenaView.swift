import SwiftUI
import AppKit

/// Interactive simulation arena container view.
struct ArenaContainerView: View {
    @EnvironmentObject var appState: AppState
    
    var body: some View {
        GeometryReader { geo in
            ArenaViewWithSize(viewSize: geo.size)
                .environmentObject(appState)
        }
    }
}

/// Interactive simulation arena rendered via SwiftUI Canvas with accurate geometry mapping.
struct ArenaViewWithSize: View {
    @EnvironmentObject var appState: AppState
    let viewSize: CGSize
    
    var body: some View {
        TimelineView(.animation) { timeline in
            Canvas { context, size in
                drawArena(context: context, size: size)
            }
            .background(Color(appState.themeManager.current.arenaCG))
            .cornerRadius(12)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(Color(appState.themeManager.current.accentCG), lineWidth: 3)
            )
            .overlay {
                if appState.simState.winnerDeclared, let winner = appState.simState.winner {
                    winnerOverlayView(winner: winner)
                        .allowsHitTesting(false)
                }
            }
            .overlay {
                if appState.showingCountdown, let n = appState.countdown {
                    countdownOverlayView(n: n)
                }
            }
            .onChange(of: timeline.date) { newDate in
                appState.stepSimulation(currentDate: newDate)
            }
            .contentShape(Rectangle())
            .gesture(
                SpatialTapGesture()
                    .onEnded { value in
                        guard appState.settings.spawnMode == .click else { return }
                        let simPt = viewToSim(viewPoint: value.location, viewSize: viewSize)
                        appState.placeEntities(at: simPt)
                    }
            )
        }
    }
    
    private func viewToSim(viewPoint: CGPoint, viewSize: CGSize) -> CGPoint {
        let settings = appState.settings
        let simW = settings.arenaWidth
        let simH = settings.arenaHeight
        let W = Double(viewSize.width > 0 ? viewSize.width : 380)
        let H = Double(viewSize.height > 0 ? viewSize.height : 560)
        
        let scale = min(W / simW, H / simH)
        let offsetX = (W - simW * scale) / 2
        let offsetY = (H - simH * scale) / 2
        
        let simX = (Double(viewPoint.x) - offsetX) / scale
        let simY = (Double(viewPoint.y) - offsetY) / scale
        
        return CGPoint(x: simX, y: simY)
    }
    
    private func drawArena(context: GraphicsContext, size: CGSize) {
        let state = appState.simState
        let settings = appState.settings
        let theme = appState.themeManager.current
        
        let W = size.width
        let H = size.height
        
        // Background
        if settings.trailsEnabled {
            context.fill(
                Path(CGRect(x: 0, y: 0, width: W, height: H)),
                with: .color(Color(theme.arenaCG).opacity(0.88))
            )
        } else {
            context.fill(
                Path(CGRect(x: 0, y: 0, width: W, height: H)),
                with: .color(Color(theme.arenaCG))
            )
        }
        
        // Calculate camera transform
        let simW = CGFloat(settings.arenaWidth)
        let simH = CGFloat(settings.arenaHeight)
        let uniformScale = min(W / simW, H / simH)
        
        let cam = state.camera
        let camScale = CGFloat(cam.scale) * uniformScale
        let camOffX = W / 2 - CGFloat(cam.cx) * camScale
        let camOffY = H / 2 - CGFloat(cam.cy) * camScale
        
        // Draw entities with camera transform
        var camContext = context
        camContext.translateBy(x: camOffX, y: camOffY)
        camContext.scaleBy(x: camScale, y: camScale)
        
        let fontSize = CGFloat(settings.iconSize)
        
        for entity in state.entities {
            let x = CGFloat(entity.x)
            let y = CGFloat(entity.y)
            camContext.draw(
                Text(entity.type.emoji).font(.system(size: fontSize)),
                at: CGPoint(x: x, y: y)
            )
        }
        
        // Draw confetti (in canvas space)
        let offsetX = (W - simW * uniformScale) / 2
        let offsetY = (H - simH * uniformScale) / 2
        
        for p in state.confetti {
            let px = offsetX + CGFloat(p.x) * uniformScale
            let py = offsetY + CGFloat(p.y) * uniformScale
            let sz = CGFloat(p.size) * uniformScale
            
            var confCtx = context
            confCtx.translateBy(x: px, y: py)
            confCtx.rotate(by: Angle(degrees: p.rot))
            confCtx.fill(
                Path(CGRect(x: -sz/2, y: -sz*0.3, width: sz, height: sz*0.6)),
                with: .color(Color(CONFETTI_COLORS[p.colorIndex % CONFETTI_COLORS.count]))
            )
        }
    }
    
    @ViewBuilder
    private func winnerOverlayView(winner: EntityType) -> some View {
        let text = appState.settings.winnerDisplayText(for: winner)
        switch appState.settings.winnerDisplayStyle {
        case .banner:
            Text(text)
                .font(.system(size: 18, weight: .heavy))
                .foregroundColor(.white)
                .padding(.horizontal, 20)
                .padding(.vertical, 8)
                .background(Color.black.opacity(0.55))
                .cornerRadius(20)
                .frame(maxHeight: .infinity, alignment: .top)
                .padding(.top, 12)
        case .center:
            Text(text)
                .font(.system(size: 40, weight: .heavy))
                .foregroundColor(.white)
                .padding(.horizontal, 24)
                .padding(.vertical, 14)
                .background(Color.black.opacity(0.65))
                .cornerRadius(24)
        case .neonRainbow:
            NeonRainbowWinnerText(text: text.uppercased())
        }
    }
    
    @ViewBuilder
    private func countdownOverlayView(n: Int) -> some View {
        ZStack {
            Color.black.opacity(0.5)
            Text("\(n)")
                .font(.system(size: 96, weight: .heavy))
                .foregroundColor(.white)
        }
        .allowsHitTesting(false)
    }
}

/// Animated neon rainbow blinking text for the interactive preview.
struct NeonRainbowWinnerText: View {
    let text: String
    
    var body: some View {
        TimelineView(.animation) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate
            let hue = (t * 0.5).truncatingRemainder(dividingBy: 1.0)
            let blink = abs(sin(t * .pi * 4.0))
            let alpha = 0.45 + 0.55 * blink
            
            ZStack {
                Text(text)
                    .font(.system(size: 52, weight: .black))
                    .foregroundColor(Color(hue: hue, saturation: 1.0, brightness: 1.0).opacity(alpha * 0.55))
                    .offset(x: -5)
                Text(text)
                    .font(.system(size: 52, weight: .black))
                    .foregroundColor(Color(hue: (hue + 0.66).truncatingRemainder(dividingBy: 1.0), saturation: 1.0, brightness: 1.0).opacity(alpha * 0.55))
                    .offset(x: 5)
                Text(text)
                    .font(.system(size: 52, weight: .black))
                    .foregroundColor(Color(hue: (hue + 0.33).truncatingRemainder(dividingBy: 1.0), saturation: 1.0, brightness: 1.0).opacity(alpha * 0.55))
                    .offset(y: -4)
                Text(text)
                    .font(.system(size: 52, weight: .black))
                    .foregroundColor(Color(hue: hue, saturation: 0.35, brightness: 1.0).opacity(alpha))
            }
            .multilineTextAlignment(.center)
            .shadow(color: Color(hue: hue, saturation: 1.0, brightness: 1.0).opacity(0.8), radius: 12)
        }
    }
}
