import SwiftUI
import AppKit

struct RPSBattleSimulatorApp: App {
    
    @StateObject private var appState = AppState()
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(appState)
                .frame(minWidth: 720, minHeight: 520)
        }
        .windowStyle(.titleBar)
        .commands {
            CommandGroup(replacing: .newItem) { }
            CommandMenu("Battle") {
                Button("Play / Pause") {
                    appState.togglePlayPause()
                }
                .keyboardShortcut(" ", modifiers: [])
                
                Button("Restart") {
                    appState.restart()
                }
                .keyboardShortcut("r", modifiers: .command)
                
                Divider()
                
                Button("Shuffle Seed") {
                    appState.shuffleSeed()
                }
                .keyboardShortcut("t", modifiers: [.command, .shift])
            }
            CommandMenu("Export") {
                Button("Export Video…") {
                    appState.exportSingleVideo()
                }
                .keyboardShortcut("e", modifiers: .command)
                
                Button("Batch Export…") {
                    appState.showingBatchExport = true
                }
                .keyboardShortcut("b", modifiers: [.command, .shift])
                
                Divider()
                
                Button("Open Output Folder") {
                    appState.revealOutputFolder()
                }
            }
        }
    }
}
