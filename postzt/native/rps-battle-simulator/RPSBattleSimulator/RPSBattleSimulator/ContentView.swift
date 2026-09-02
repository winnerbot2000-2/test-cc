import SwiftUI

struct ContentView: View {
    @EnvironmentObject var appState: AppState
    @State private var settingsPanelVisible = true
    
    var body: some View {
        VStack(spacing: 0) {
            // Persistent toolbar at top
            PersistentToolbar(settingsPanelVisible: $settingsPanelVisible)
                .environmentObject(appState)
            
            Divider()
            
            // Scoreboard & percentage bar above arena
            ScoreboardHeader()
                .environmentObject(appState)
                .padding(.top, 8)
                .padding(.horizontal, 16)
            
            // Main content: arena + optional settings panel
            HStack(spacing: 0) {
                // Arena (always visible)
                ArenaContainerView()
                    .environmentObject(appState)
                    .padding(12)
                    .frame(minWidth: 320)
                
                if settingsPanelVisible {
                    Divider()
                    SettingsPanel()
                        .environmentObject(appState)
                        .frame(width: 320)
                }
            }
        }
        .background(Color(appState.themeManager.current.bg1CG))
        .sheet(isPresented: $appState.showingExportProgress) {
            ExportProgressView()
                .environmentObject(appState)
        }
        .sheet(isPresented: $appState.showingBatchExport) {
            BatchExportView()
                .environmentObject(appState)
        }
    }
}

// MARK: - Scoreboard Header

struct ScoreboardHeader: View {
    @EnvironmentObject var appState: AppState
    
    var body: some View {
        VStack(spacing: 6) {
            // Live counts
            HStack(spacing: 24) {
                scoreItem(emoji: "🪨", count: appState.simState.rockCount)
                scoreItem(emoji: "📄", count: appState.simState.paperCount)
                scoreItem(emoji: "✂️", count: appState.simState.scissorsCount)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 6)
            .background(Color.black.opacity(0.25))
            .cornerRadius(12)
            
            // Percentage bar
            let total = appState.simState.totalCount
            let rockW = total > 0 ? CGFloat(appState.simState.rockCount) / CGFloat(total) : 0
            let paperW = total > 0 ? CGFloat(appState.simState.paperCount) / CGFloat(total) : 0
            let scissorsW = total > 0 ? CGFloat(appState.simState.scissorsCount) / CGFloat(total) : 0
            let theme = appState.themeManager.current
            
            GeometryReader { geo in
                HStack(spacing: 0) {
                    Rectangle()
                        .fill(theme.rockBar)
                        .frame(width: geo.size.width * rockW)
                    Rectangle()
                        .fill(theme.paperBar)
                        .frame(width: geo.size.width * paperW)
                    Rectangle()
                        .fill(theme.scissorsBar)
                        .frame(width: geo.size.width * scissorsW)
                }
            }
            .frame(maxWidth: 380)
            .frame(height: 8)
            .cornerRadius(4)
            .background(Color.black.opacity(0.3))
        }
    }
    
    @ViewBuilder
    private func scoreItem(emoji: String, count: Int) -> some View {
        HStack(spacing: 6) {
            Text(emoji).font(.system(size: 18))
            Text("\(count)")
                .font(.system(size: 18, weight: .bold).monospacedDigit())
                .foregroundColor(Color(appState.themeManager.current.textCG))
        }
    }
}

// MARK: - Persistent Toolbar

struct PersistentToolbar: View {
    @EnvironmentObject var appState: AppState
    @Binding var settingsPanelVisible: Bool
    
    var body: some View {
        HStack(spacing: 12) {
            // Play/Pause
            Button(action: { appState.togglePlayPause() }) {
                Label(
                    appState.isRunning ? "Pause" : "Play",
                    systemImage: appState.isRunning ? "pause.fill" : "play.fill"
                )
                .frame(minWidth: 70)
            }
            .buttonStyle(.bordered)
            .tint(Color(appState.themeManager.current.accentCG))
            .keyboardShortcut(" ", modifiers: [])
            
            // Restart
            Button(action: { appState.restart() }) {
                Label("Restart", systemImage: "arrow.counterclockwise")
            }
            .buttonStyle(.bordered)
            .keyboardShortcut("r", modifiers: .command)
            
            Divider().frame(height: 20)
            
            // Seed display
            HStack(spacing: 4) {
                Text("Seed:").font(.caption).opacity(0.7)
                Text("\(appState.settings.seed)").font(.caption.monospacedDigit()).opacity(0.9)
            }
            
            Spacer()
            
            // Export Video
            Button(action: { appState.exportSingleVideo() }) {
                Label("● Record / Export", systemImage: "video.fill")
            }
            .buttonStyle(.borderedProminent)
            .tint(.red)
            .keyboardShortcut("e", modifiers: .command)
            
            // Batch Export
            Button(action: { appState.showingBatchExport = true }) {
                Label("Batch Export", systemImage: "square.stack.3d.up")
            }
            .buttonStyle(.bordered)
            
            Divider().frame(height: 20)
            
            // Toggle Settings
            Button(action: { settingsPanelVisible.toggle() }) {
                Image(systemName: "sidebar.right")
            }
            .buttonStyle(.bordered)
            .help(settingsPanelVisible ? "Hide Settings" : "Show Settings")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(Color(appState.themeManager.current.panelCG))
    }
}
