import SwiftUI

struct ExportProgressView: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) var dismiss
    
    var body: some View {
        VStack(spacing: 16) {
            
            // Header
            HStack {
                Text("Export Video")
                    .font(.title2.bold())
                Spacer()
                if let ep = appState.exportProgress, !ep.isExporting {
                    Button(action: { dismiss() }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.title3)
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding([.horizontal, .top])
            
            Divider()
            
            if let ep = appState.exportProgress {
                if ep.isExporting {
                    // In progress
                    VStack(spacing: 16) {
                        Spacer()
                        
                        ProgressView(value: ep.fraction)
                            .progressViewStyle(.linear)
                            .padding(.horizontal)
                        
                        Text(ep.message)
                            .font(.callout)
                            .opacity(0.8)
                        
                        if ep.totalFrames > 0 {
                            Text("Frame \(ep.currentFrame) / \(ep.totalFrames)")
                                .font(.caption.monospacedDigit())
                                .opacity(0.6)
                        }
                        
                        Text("1080×1920 9:16 · H.264 · \(appState.settings.exportFPS.displayName)")
                            .font(.caption)
                            .opacity(0.5)
                        
                        Spacer()
                        
                        Button("Cancel") { appState.cancelExport() }
                            .buttonStyle(.bordered)
                            .tint(.red)
                    }
                    .padding(.bottom)
                    
                } else if let err = ep.error {
                    // Error
                    VStack(spacing: 12) {
                        Spacer()
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 40))
                            .foregroundColor(.red)
                        Text("Export Failed")
                            .font(.headline)
                        Text(err)
                            .font(.caption)
                            .multilineTextAlignment(.center)
                            .opacity(0.8)
                        Spacer()
                        Button("Dismiss") { dismiss() }
                            .buttonStyle(.borderedProminent)
                    }
                    .padding()
                    
                } else {
                    // Success
                    VStack(spacing: 12) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 48))
                            .foregroundColor(.green)
                        Text("Export Complete!")
                            .font(.title3.bold())
                        if let url = ep.outputURL {
                            Text(url.lastPathComponent)
                                .font(.callout.bold())
                                .opacity(0.9)
                            Text("Saved to: " + url.deletingLastPathComponent().path)
                                .font(.caption)
                                .opacity(0.6)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                        Text("1080×1920 · H.264 · MP4 (Ready for TikTok/Shorts)")
                            .font(.caption)
                            .opacity(0.6)
                        
                        HStack(spacing: 12) {
                            if ep.outputURL != nil {
                                Button("Show in Finder") { appState.revealLastExport() }
                                    .buttonStyle(.bordered)
                            }
                            Button("Done") { dismiss() }
                                .buttonStyle(.borderedProminent)
                        }
                    }
                    .padding()
                }
            }
        }
        .frame(width: 400, height: 480)
    }
}
