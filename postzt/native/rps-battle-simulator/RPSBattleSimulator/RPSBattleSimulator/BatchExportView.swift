import SwiftUI

struct BatchExportView: View {
    @EnvironmentObject var appState: AppState
    @State private var config = BatchConfig(count: 5, seedMode: .sequential, startingSeed: 1)
    @State private var customCount: Int = 5
    @Environment(\.dismiss) var dismiss
    
    private let countPresets = [1, 5, 10, 25, 50]
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Batch Video Export")
                    .font(.title2.bold())
                Spacer()
                Button(action: { dismiss() }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title3)
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding()
            
            Divider()
            
            // If batch is running or finished, show progress/results
            if let bp = appState.batchProgress, bp.isRunning {
                batchRunningView(bp: bp)
            } else if let bp = appState.batchProgress, !bp.isRunning {
                batchCompleteView(bp: bp)
            } else {
                batchConfigView()
            }
        }
        .frame(width: 480, height: 530)
    }
    
    // MARK: - Config
    
    @ViewBuilder
    private func batchConfigView() -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                
                // Count
                VStack(alignment: .leading, spacing: 8) {
                    Text("NUMBER OF VIDEOS")
                        .font(.caption.uppercaseSmallCaps())
                        .opacity(0.6)
                    
                    HStack(spacing: 6) {
                        ForEach(countPresets, id: \.self) { n in
                            Button("\(n)") {
                                config.count = n
                                customCount = n
                            }
                            .buttonStyle(.bordered)
                            .tint(config.count == n ? .accentColor : nil)
                            .frame(maxWidth: .infinity)
                        }
                        
                        // Custom
                        HStack(spacing: 2) {
                            TextField("#", value: $customCount, format: .number)
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 45)
                                .onChange(of: customCount) { v in
                                    if v > 0 { config.count = v }
                                }
                        }
                    }
                }
                
                Divider()
                
                // Seed mode
                VStack(alignment: .leading, spacing: 8) {
                    Text("SEED MODE")
                        .font(.caption.uppercaseSmallCaps())
                        .opacity(0.6)
                    
                    Picker("", selection: $config.seedMode) {
                        ForEach(BatchSeedMode.allCases, id: \.self) { mode in
                            Text(mode.displayName).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                    
                    if config.seedMode == .sequential {
                        HStack {
                            Text("Starting Seed")
                            Spacer()
                            TextField("Seed", value: $config.startingSeed, format: .number)
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 100)
                                .multilineTextAlignment(.trailing)
                        }
                        .padding(.top, 2)
                        
                        Text("Seeds will be: \(config.startingSeed), \(config.startingSeed &+ 1), \(config.startingSeed &+ 2), …")
                            .font(.caption)
                            .opacity(0.6)
                    } else {
                        Text("Each video in the batch gets a unique pseudorandom seed.")
                            .font(.caption)
                            .opacity(0.6)
                    }
                }
                
                Divider()
                
                // Randomize settings variation
                Toggle("Randomize settings between videos (variation)", isOn: $config.randomizeSettings)
                    .font(.callout)
                if config.randomizeSettings {
                    Text("Varies icon counts, speed, and wobble within balanced ranges for unique TikTok/Shorts content.")
                        .font(.caption)
                        .opacity(0.7)
                }
                
                Divider()
                
                // Output
                VStack(alignment: .leading, spacing: 6) {
                    Text("OUTPUT DESTINATION")
                        .font(.caption.uppercaseSmallCaps())
                        .opacity(0.6)
                    
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(appState.outputFolder.path)
                                .font(.caption)
                                .opacity(0.8)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                        Spacer()
                        Button("Change…") { appState.pickOutputFolder() }
                            .buttonStyle(.bordered)
                    }
                    
                    Text("Filenames: \(appState.settings.filenamePrefix)_001.mp4 … \(appState.settings.filenamePrefix)_\(String(format: "%03d", config.count)).mp4")
                        .font(.caption)
                        .opacity(0.6)
                    
                    Text("Each batch is saved into its own timestamped subfolder.")
                        .font(.caption)
                        .opacity(0.6)
                }
                
                Divider()
                
                // Settings summary
                VStack(alignment: .leading, spacing: 4) {
                    Text("VIDEO SPECIFICATIONS")
                        .font(.caption.uppercaseSmallCaps())
                        .opacity(0.6)
                    HStack {
                        Text("Format").opacity(0.7)
                        Spacer()
                        Text("1080×1920 9:16 H.264 MP4")
                    }
                    .font(.caption)
                    HStack {
                        Text("Frame Rate").opacity(0.7)
                        Spacer()
                        Text(appState.settings.exportFPS.displayName)
                    }
                    .font(.caption)
                }
                
                Spacer(minLength: 16)
            }
            .padding()
        }
        
        Divider()
        
        HStack {
            Button("Cancel") { dismiss() }
                .buttonStyle(.bordered)
            Spacer()
            Button("Generate \(config.count) Video\(config.count == 1 ? "" : "s")") {
                appState.batchProgress = nil
                appState.startBatchExport(config: config)
            }
            .buttonStyle(.borderedProminent)
            .tint(.red)
        }
        .padding()
    }
    
    // MARK: - Running
    
    @ViewBuilder
    private func batchRunningView(bp: BatchProgress) -> some View {
        VStack(spacing: 18) {
            Spacer()
            
            ProgressView(value: bp.overallFraction)
                .progressViewStyle(.linear)
                .padding(.horizontal)
            
            Text("Generating video \(bp.currentVideo) of \(bp.totalVideos)")
                .font(.headline)
            
            VStack(spacing: 4) {
                Text("Seed: \(bp.currentSeed)")
                    .font(.caption.monospacedDigit())
                    .opacity(0.8)
                Text(bp.currentFilename)
                    .font(.caption)
                    .opacity(0.7)
            }
            
            ProgressView(value: bp.currentFrameFraction)
                .progressViewStyle(.linear)
                .padding(.horizontal)
                .opacity(0.6)
            
            if !bp.completedURLs.isEmpty {
                Text("\(bp.completedURLs.count) video\(bp.completedURLs.count == 1 ? "" : "s") completed")
                    .font(.caption)
                    .opacity(0.7)
            }
            
            Spacer()
            
            Button("Cancel Batch") {
                appState.cancelBatch()
            }
            .buttonStyle(.bordered)
            .tint(.red)
            .padding(.bottom)
        }
    }
    
    // MARK: - Complete
    
    @ViewBuilder
    private func batchCompleteView(bp: BatchProgress) -> some View {
        let failed = bp.failures.count
        ScrollView {
            VStack(spacing: 14) {
                Image(systemName: bp.isCancelled ? "xmark.circle" : (failed > 0 ? "exclamationmark.triangle.fill" : "checkmark.circle.fill"))
                    .font(.system(size: 48))
                    .foregroundColor(bp.isCancelled ? .orange : (failed > 0 ? .orange : .green))
                
                if bp.isCancelled {
                    Text("Batch Cancelled")
                        .font(.title3.bold())
                    Text("\(bp.completedURLs.count) of \(bp.totalVideos) videos saved.")
                        .opacity(0.7)
                } else if failed > 0 {
                    Text("Batch Complete with Failures")
                        .font(.title3.bold())
                    Text("\(bp.completedURLs.count) saved, \(failed) failed.")
                        .opacity(0.7)
                } else {
                    Text("Batch Complete!")
                        .font(.title3.bold())
                    Text("\(bp.completedURLs.count) video\(bp.completedURLs.count == 1 ? "" : "s") saved successfully.")
                        .opacity(0.7)
                }
                
                if !bp.failures.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(bp.failures) { f in
                            HStack(alignment: .top, spacing: 6) {
                                Text("#\(f.index)")
                                    .font(.caption.monospacedDigit())
                                    .foregroundColor(.red)
                                Text(f.filename)
                                    .font(.caption)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                                Spacer()
                                Text(f.error)
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                                    .lineLimit(2)
                                    .truncationMode(.tail)
                            }
                            .padding(6)
                            .background(Color.black.opacity(0.15))
                            .cornerRadius(6)
                        }
                    }
                }
                
                if let folder = bp.batchFolder {
                    Text("Saved to: \(folder.lastPathComponent)")
                        .font(.caption)
                        .opacity(0.6)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                
                if let manifest = bp.manifestURL {
                    Text("Manifest: \(manifest.lastPathComponent)")
                        .font(.caption2)
                        .opacity(0.5)
                }
                
                HStack(spacing: 12) {
                    Button("Open Folder in Finder") {
                        if let folder = bp.batchFolder {
                            NSWorkspace.shared.open(folder)
                        } else {
                            appState.revealOutputFolder()
                        }
                    }
                    .buttonStyle(.bordered)
                    
                    if failed > 0 {
                        Button("Retry Failed (\(failed))") { appState.retryFailedBatch() }
                            .buttonStyle(.bordered)
                    }
                    
                    Button("Done") {
                        appState.batchProgress = nil
                        dismiss()
                    }
                    .buttonStyle(.borderedProminent)
                }
                .padding(.bottom)
            }
            .padding()
        }
    }
}
