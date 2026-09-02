import SwiftUI
import AppKit
import AVFoundation
import UserNotifications

@MainActor
final class AppState: ObservableObject {
    
    // MARK: - Settings
    @Published var settings = SimulationSettings()
    
    // MARK: - Simulation State
    @Published var simState: SimulationState = SimulationState.empty(settings: SimulationSettings())
    @Published var isRunning: Bool = true
    @Published var countdown: Int? = nil
    @Published var showingCountdown: Bool = false
    
    // MARK: - Theme
    let themeManager = ThemeManager()
    
    // MARK: - Social platforms
    let socialAuth = SocialAuthManager()
    @Published var uploadResults: [SocialPlatform: UploadResult] = [:]
    @Published var uploadingPlatform: SocialPlatform? = nil
    @Published var presetError: String? = nil
    
    // MARK: - Export
    @Published var exportProgress: ExportProgress? = nil
    @Published var batchProgress: BatchProgress? = nil
    @Published var showingExportProgress = false
    @Published var showingBatchExport = false
    @Published var outputFolder: URL = AppState.defaultOutputFolder()
    @Published var lastExportedURL: URL? = nil
    
    // MARK: - Audio
    private var audioEngine: AVAudioEngine? = nil
    private var playerNode: AVAudioPlayerNode? = nil
    private var popBuffer: AVAudioPCMBuffer? = nil
    
    // MARK: - Animation timing
    private var lastStepDate: Date = Date()
    private var accumulatedTime: Double = 0
    
    // MARK: - Export / Batch tasks
    private var exportTask: Task<Void, Never>? = nil
    private var currentExporter: VideoExporter? = nil
    private var batchExporter: BatchExporter? = nil
    
    // MARK: - Init
    
    init() {
        simState = SimulationEngine.spawnFresh(settings: settings)
        setupAudio()
    }
    
    private func setupAudio() {
        let samples = AudioGenerator.generatePopSamples(amplitude: 0.14)
        popBuffer = AudioGenerator.makePCMBuffer(from: samples)
        
        let engine = AVAudioEngine()
        let player = AVAudioPlayerNode()
        engine.attach(player)
        if let buffer = popBuffer {
            engine.connect(player, to: engine.mainMixerNode, format: buffer.format)
            try? engine.start()
        }
        self.audioEngine = engine
        self.playerNode = player
    }
    
    // MARK: - Default output folder
    
    static func defaultOutputFolder() -> URL {
        // Prefer the project folder (the directory that contains the app bundle),
        // but fall back to user-writable locations when it isn't writable.
        let candidates: [URL] = [
            Bundle.main.bundleURL.pathExtension == "app"
                ? Bundle.main.bundleURL.deletingLastPathComponent()
                : FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask).first!,
            FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask).first!,
            FileManager.default.urls(for: .moviesDirectory, in: .userDomainMask).first!,
            FileManager.default.homeDirectoryForCurrentUser,
        ]
        for c in candidates where FileManager.default.isWritableFile(atPath: c.path) {
            return c
        }
        return FileManager.default.homeDirectoryForCurrentUser
    }
    
    // MARK: - Simulation control
    
    func play() {
        isRunning = true
        lastStepDate = Date()
    }
    
    func pause() {
        isRunning = false
    }
    
    func togglePlayPause() {
        if isRunning { pause() } else { play() }
    }
    
    func restart() {
        isRunning = false
        simState = SimulationEngine.spawnFresh(settings: settings)
        if settings.countdownEnabled {
            startCountdown { [weak self] in
                self?.play()
            }
        } else {
            play()
        }
    }
    
    func clearArena() {
        simState.entities = []
        simState.winnerDeclared = false
        simState.winner = nil
        isRunning = true
    }
    
    // MARK: - Countdown
    
    private func startCountdown(completion: @escaping () -> Void) {
        countdown = 3
        showingCountdown = true
        
        func tick(_ n: Int) {
            countdown = n
            if n <= 0 {
                showingCountdown = false
                countdown = nil
                completion()
            } else {
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                    tick(n - 1)
                }
            }
        }
        tick(3)
    }
    
    // MARK: - Physics step
    
    func stepSimulation(currentDate: Date) {
        guard isRunning else { return }
        
        let elapsed = currentDate.timeIntervalSince(lastStepDate)
        lastStepDate = currentDate
        
        let cappedElapsed = min(elapsed, 0.1)
        accumulatedTime += cappedElapsed
        
        let stepSize = 1.0 / 60.0
        while accumulatedTime >= stepSize {
            SimulationEngine.tick(state: &simState, settings: settings, dt: 1.0)
            
            if simState.winnerDeclared && simState.confetti.isEmpty {
                SimulationEngine.spawnConfetti(state: &simState, settings: settings)
            }
            if !simState.confetti.isEmpty {
                SimulationEngine.updateConfetti(state: &simState, settings: settings, dt: 1.0)
            }
            
            if simState.winnerDeclared && settings.autoStopOnWinner {
                isRunning = false
                accumulatedTime = 0
                break
            }
            
            if simState.pendingConversions > 0 && settings.soundEnabled {
                playPop()
            }
            
            accumulatedTime -= stepSize
        }
    }
    
    // MARK: - Click to place
    
    func placeEntities(at simPoint: CGPoint) {
        SimulationEngine.addEntitiesAtPoint(
            x: Double(simPoint.x),
            y: Double(simPoint.y),
            type: settings.activeClickType,
            count: settings.iconsPerClick,
            state: &simState,
            settings: settings
        )
        simState.winnerDeclared = false
        simState.winner = nil
    }
    
    // MARK: - Arena resize
    
    func arenaResized() {
        simState.camera = CameraState.initial(arenaWidth: settings.arenaWidth, arenaHeight: settings.arenaHeight)
        SimulationEngine.clampEntities(state: &simState, settings: settings)
    }
    
    // MARK: - Theme
    
    func applyTheme(_ name: ThemeName) {
        settings.theme = name
        themeManager.apply(name)
    }
    
    // MARK: - Seed
    
    func shuffleSeed() {
        settings.seed = UInt32.random(in: 1...UInt32.max)
        restart()
    }
    
    // MARK: - Battle presets
    
    func savePreset() {
        let preset = BattlePreset(name: settings.filenamePrefix, settings: settings, createdAt: Date())
        do {
            try PresetManager.saveWithDialog(preset: preset)
        } catch {
            presetError = error.localizedDescription
        }
    }
    
    func loadPreset() {
        do {
            let preset = try PresetManager.loadWithDialog()
            settings = preset.settings.validated()
            applyTheme(preset.settings.theme)
            restart()
        } catch {
            let ns = error as NSError
            if ns.domain == NSCocoaErrorDomain && ns.code == CocoaError.userCancelled.rawValue {
                return  // user cancelled — ignore
            }
            presetError = error.localizedDescription
        }
    }
    
    // MARK: - Sound
    
    private func playPop() {
        guard let player = playerNode, let buffer = popBuffer else { return }
        // Layer overlapping pops instead of cutting the previous one off.
        player.scheduleBuffer(buffer, at: nil, options: [], completionHandler: nil)
        if !player.isPlaying {
            player.play()
        }
    }
    
    // MARK: - Single Export
    
    /// Rough estimated output size (bytes) for one video, used for the disk-space preflight.
    static func estimatedFileSize(_ settings: SimulationSettings) -> Int64 {
        let duration = (settings.countdownEnabled ? 3.0 : 0.0)
            + (settings.introEnabled ? settings.introDurationSeconds : 0.0)
            + settings.maxDuration.seconds
            + settings.winnerHoldSeconds
        // Approximate ~2 MB/s for 1080x1920 H.264 (validated exports are ~1.8 MB/s).
        return Int64(duration * 2.0 * 1024 * 1024)
    }
    
    private func freeDiskSpace(at url: URL) -> Int64 {
        let values = try? url.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
        return Int64(values?.volumeAvailableCapacityForImportantUsage ?? 0)
    }
    
    private func preflightDiskSpace(neededBytes: Int64) -> Bool {
        let available = freeDiskSpace(at: outputFolder)
        guard available > 0 else { return true }  // unknown — don't block
        let needed = neededBytes + 200 * 1024 * 1024  // 200 MB headroom
        return available >= needed
    }
    
    func exportSingleVideo() {
        // Prevent overlapping exports and cross-block single vs. batch runs.
        guard exportProgress?.isExporting != true, batchProgress?.isRunning != true else { return }
        
        // Disk-space preflight.
        if !preflightDiskSpace(neededBytes: Self.estimatedFileSize(settings)) {
            showingExportProgress = true
            exportProgress = ExportProgress(
                isExporting: false,
                message: "Not enough disk space.",
                error: "Insufficient free disk space to export this video."
            )
            return
        }
        
        let url = VideoExporter.safeOutputURL(
            prefix: settings.filenamePrefix,
            index: 1,
            outputFolder: outputFolder
        )
        
        let job = ExportJob(
            settings: settings,
            theme: ThemeManager.theme(for: settings.theme),
            outputURL: url,
            videoIndex: 1,
            overrideEntities: exportOverrideEntities()
        )
        
        showingExportProgress = true
        exportProgress = ExportProgress(isExporting: true, message: "Starting export…")
        
        let exporter = VideoExporter()
        currentExporter = exporter
        
        exportTask = Task { [weak self] in
            do {
                try await exporter.export(job: job) { p in
                    Task { @MainActor in
                        self?.exportProgress = p
                    }
                }
                await MainActor.run {
                    self?.exportProgress = ExportProgress(
                        isExporting: false,
                        message: "Export complete!",
                        outputURL: url
                    )
                    self?.lastExportedURL = url
                    self?.currentExporter = nil
                }
            } catch {
                await MainActor.run {
                    let cancelled = Self.isCancellation(error)
                    self?.exportProgress = ExportProgress(
                        isExporting: false,
                        isCancelled: cancelled,
                        message: cancelled ? "Export cancelled." : "Export failed.",
                        error: cancelled ? nil : error.localizedDescription
                    )
                    self?.currentExporter = nil
                }
            }
        }
    }
    
    func cancelExport() {
        exportProgress?.isCancelled = true
        exportProgress?.message = "Cancelling…"
        let exporter = currentExporter
        Task { await exporter?.cancel() }
        exportTask?.cancel()
    }
    
    static func isCancellation(_ error: Error) -> Bool {
        if error is CancellationError { return true }
        if let vee = error as? VideoExportError, case .cancelled = vee { return true }
        return false
    }
    
    // MARK: - Batch Export
    
    private var lastBatchJobs: [ExportJob] = []
    
    func startBatchExport(config: BatchConfig) {
        // Prevent overlapping batch runs and cross-block single vs. batch runs.
        guard batchProgress?.isRunning != true, exportProgress?.isExporting != true else { return }
        
        // Ask for notification permission only when the user actually starts a batch.
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
        
        let jobs: [ExportJob]
        do {
            jobs = try BatchExporter.buildJobs(
                config: config,
                baseSettings: settings,
                theme: ThemeManager.theme(for: settings.theme),
                outputFolder: outputFolder,
                overrideEntities: exportOverrideEntities()
            )
        } catch {
            showingBatchExport = true
            batchProgress = BatchProgress(isRunning: false, error: error.localizedDescription)
            return
        }
        
        lastBatchJobs = jobs
        
        let batchFolder = jobs.first?.outputURL.deletingLastPathComponent()
        
        showingBatchExport = true
        batchProgress = BatchProgress(
            isRunning: true,
            totalVideos: jobs.count,
            batchFolder: batchFolder
        )
        
        let exporter = BatchExporter()
        batchExporter = exporter
        
        Task {
            await exporter.runBatch(jobs: jobs) { [weak self] p in
                Task { @MainActor in
                    var updated = p
                    if updated.batchFolder == nil { updated.batchFolder = batchFolder }
                    self?.batchProgress = updated
                    if !updated.isRunning { self?.notifyBatchFinished(updated) }
                }
            }
        }
    }
    
    /// Re-runs only the failed videos from the previous batch.
    func retryFailedBatch() {
        guard let bp = batchProgress, !bp.isRunning else { return }
        let failed = Set(bp.failedIndices.map { $0 - 1 })
        let retryJobs = lastBatchJobs.enumerated().filter { failed.contains($0.offset) }.map { $0.element }
        guard !retryJobs.isEmpty else { return }
        
        showingBatchExport = true
        batchProgress = BatchProgress(isRunning: true, totalVideos: retryJobs.count)
        
        let exporter = BatchExporter()
        batchExporter = exporter
        
        Task {
            await exporter.runBatch(jobs: retryJobs) { [weak self] p in
                Task { @MainActor in
                    var updated = p
                    updated.batchFolder = retryJobs.first?.outputURL.deletingLastPathComponent()
                    self?.batchProgress = updated
                    if !updated.isRunning { self?.notifyBatchFinished(updated) }
                }
            }
        }
    }
    
    func cancelBatch() {
        Task {
            await batchExporter?.cancel()
        }
    }
    
    private func notifyBatchFinished(_ bp: BatchProgress) {
        let failed = bp.failures.count
        let done = bp.completedURLs.count
        var title: String
        var body: String
        if bp.isCancelled {
            title = "Batch cancelled"
            body = "\(done) video(s) saved."
        } else if failed > 0 {
            title = "Batch finished with failures"
            body = "\(done) saved, \(failed) failed."
        } else {
            title = "Batch complete"
            body = "\(done) video(s) exported successfully."
        }
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }
    
    // MARK: - Output folder picker
    
    func pickOutputFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.title = "Choose Output Folder"
        panel.prompt = "Select"
        if panel.runModal() == .OK, let url = panel.url {
            outputFolder = url
        }
    }
    
    func revealOutputFolder() {
        NSWorkspace.shared.open(outputFolder)
    }
    
    func revealLastExport() {
        if let url = lastExportedURL {
            NSWorkspace.shared.activateFileViewerSelecting([url])
        }
    }
    
    /// When exporting a click-to-place battle, reuse the current arena layout.
    private func exportOverrideEntities() -> [Entity]? {
        settings.spawnMode == .click ? simState.entities : nil
    }
    
    // MARK: - Social uploads
    
    func connectPlatform(_ platform: SocialPlatform) {        Task { @MainActor in
            do {
                try await socialAuth.connect(platform)
            } catch {
                socialAuth.lastError = error.localizedDescription
            }
        }
    }
    
    func disconnectPlatform(_ platform: SocialPlatform) {
        socialAuth.disconnect(platform)
    }
    
    func uploadLastExport(to platform: SocialPlatform) {
        guard let url = lastExportedURL else { return }
        uploadingPlatform = platform
        let creds = socialAuth.credentials
        let title = "\(settings.filenamePrefix) #\(settings.seed) #Shorts"
        
        Task { @MainActor in
            defer { uploadingPlatform = nil }
            do {
                let token = try await socialAuth.validAccessToken(for: platform)
                let result = try await SocialUploader.upload(
                    videoURL: url,
                    title: title,
                    platform: platform,
                    credentials: creds,
                    accessToken: token,
                    asDraft: true
                )
                uploadResults[platform] = result
            } catch {
                uploadResults[platform] = UploadResult(platform: platform, success: false, message: error.localizedDescription)
            }
        }
    }
}
