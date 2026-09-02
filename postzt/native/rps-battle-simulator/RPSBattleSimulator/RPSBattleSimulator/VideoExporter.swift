import AVFoundation
import CoreGraphics
import AppKit
import Foundation

/// Errors that can occur during video export.
enum VideoExportError: LocalizedError {
    case h264Unavailable
    case writerCreationFailed(Error)
    case inputSetupFailed
    case pixelBufferPoolUnavailable
    case renderFailed
    case writeFailed(Error)
    case cancelled
    case outputFolderUnwritable
    
    var errorDescription: String? {
        switch self {
        case .h264Unavailable: return "H.264 encoder unavailable on this Mac."
        case .writerCreationFailed(let e): return "Could not create video file: \(e.localizedDescription)"
        case .inputSetupFailed: return "Could not configure video input settings."
        case .pixelBufferPoolUnavailable: return "Pixel buffer pool unavailable."
        case .renderFailed: return "Frame rendering failed."
        case .writeFailed(let e): return "Video writing failed: \(e.localizedDescription)"
        case .cancelled: return "Export was cancelled."
        case .outputFolderUnwritable: return "Cannot write to the output folder."
        }
    }
}

/// Parameters for a single export job.
struct ExportJob {
    var settings: SimulationSettings
    var theme: Theme
    var outputURL: URL
    var videoIndex: Int
    /// Optional starting layout (used for click-to-place battles that have no spawn config).
    var overrideEntities: [Entity]? = nil
}

/// Thread-safe cancellation flag shared between the exporter and writer queues.
final class CancelToken: @unchecked Sendable {
    private let lock = NSLock()
    private var cancelled = false
    
    var isCancelled: Bool {
        lock.lock(); defer { lock.unlock() }
        return cancelled
    }
    
    func cancel() {
        lock.lock(); defer { lock.unlock() }
        cancelled = true
    }
}

/// Mutable box for a per-queue index counter used inside writer callbacks.
final class IndexBox: @unchecked Sendable {
    var value: Int = 0
    init(_ value: Int = 0) { self.value = value }
}

/// Thread-safe box to capture the first error raised on a writer queue.
final class ErrorBox: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: Error? = nil
    
    func set(_ error: Error) {
        lock.lock(); defer { lock.unlock() }
        if stored == nil { stored = error }
    }
    
    var error: Error? {
        lock.lock(); defer { lock.unlock() }
        return stored
    }
}

/// Deterministic MP4 video exporter.
/// Replays the simulation from seed, rendering each frame independently.
/// Never captures the screen or application window.
actor VideoExporter {
    
    private let cancelToken = CancelToken()
    
    func cancel() { cancelToken.cancel() }
    
    // MARK: - Export a single video
    
    func export(
        job: ExportJob,
        progress: @escaping (ExportProgress) -> Void
    ) async throws {
        let settings = job.settings
        let theme = job.theme
        let fps = settings.exportFPS.rawValue
        let fpsDouble = Double(fps)
        let maxDuration = settings.maxDuration.seconds
        let winnerHold = settings.winnerHoldSeconds
        
        // Preflight: output location must be writable before doing any work.
        let outputDir = job.outputURL.deletingLastPathComponent()
        if !FileManager.default.isWritableFile(atPath: outputDir.path) {
            throw VideoExportError.outputFolderUnwritable
        }
        
        let targetFPS = fpsDouble
        let physicsStepsPerFrame = 2
        let physicsdt = 1.0 / (targetFPS * Double(physicsStepsPerFrame))
        
        // Pre-simulate to collect per-frame states.
        // Use the caller-supplied layout (click-to-place) when provided.
        var simState: SimulationState
        if let override = job.overrideEntities {
            simState = SimulationEngine.spawnFromEntities(entities: override, settings: settings)
        } else {
            simState = SimulationEngine.spawnFresh(settings: settings)
        }
        
        var frames: [(state: SimulationState, countdown: Int?, introAlpha: Double)] = []
        
        let countdownDuration: Double = settings.countdownEnabled ? 3.0 : 0.0
        let introDuration: Double = settings.introEnabled ? settings.introDurationSeconds : 0.0
        
        let estimatedFrames = Int((maxDuration + winnerHold + countdownDuration + introDuration) * fpsDouble) + 10
        
        var simTime: Double = 0
        var winnerTime: Double? = nil
        var confettiSpawned = false
        var conversionEvents: [(timestamp: Double, count: Int)] = []
        
        var frameIndex = 0
        var done = false
        
        while !done {
            if cancelToken.isCancelled { throw VideoExportError.cancelled }
            
            let videoTime = Double(frameIndex) / fpsDouble
            
            // Countdown phase
            let countdownValue: Int?
            if videoTime < countdownDuration {
                let remaining = countdownDuration - videoTime
                if remaining > 2.0 { countdownValue = 3 }
                else if remaining > 1.0 { countdownValue = 2 }
                else { countdownValue = 1 }
                frames.append((state: simState, countdown: countdownValue, introAlpha: 0))
                frameIndex += 1
                continue
            }
            
            // Intro overlay phase
            let simStartTime = countdownDuration + introDuration
            let introAlpha: Double
            if videoTime < simStartTime {
                introAlpha = 1.0 - (videoTime - countdownDuration) / max(introDuration, 0.001)
            } else {
                introAlpha = 0
            }
            
            // Advance simulation to match video time
            let targetSimTime = max(0, videoTime - simStartTime)
            
            // Advance physics
            let neededPhysicsTime = targetSimTime - simTime + physicsdt
            var physicsSteps = Int(neededPhysicsTime / physicsdt)
            physicsSteps = min(physicsSteps, physicsStepsPerFrame * 2)
            
            for _ in 0..<max(physicsSteps, 1) {
                if simTime < targetSimTime || frames.isEmpty {
                    SimulationEngine.tick(state: &simState, settings: settings, dt: physicsdt * 60.0)
                    if simState.pendingConversions > 0 {
                        conversionEvents.append((timestamp: simTime + countdownDuration + introDuration, count: simState.pendingConversions))
                    }
                    if simState.winnerDeclared && !confettiSpawned {
                        SimulationEngine.spawnConfetti(state: &simState, settings: settings)
                        confettiSpawned = true
                        winnerTime = simTime
                    }
                    if simState.winnerDeclared && confettiSpawned {
                        SimulationEngine.updateConfetti(state: &simState, settings: settings, dt: physicsdt * 60.0)
                    }
                    simTime += physicsdt
                }
            }
            
            frames.append((state: simState, countdown: nil, introAlpha: introAlpha))
            frameIndex += 1
            
            // Check termination conditions
            if let wt = winnerTime {
                let holdElapsed = simTime - wt
                if holdElapsed >= winnerHold {
                    done = true
                }
            } else if simTime >= maxDuration {
                if !simState.winnerDeclared {
                    // Predictable fallback: highest remaining count wins; tie broken deterministically by seed
                    let rockC = simState.rockCount
                    let paperC = simState.paperCount
                    let scissorsC = simState.scissorsCount
                    simState.winner = Self.fallbackWinner(rock: rockC, paper: paperC, scissors: scissorsC, seed: settings.seed)
                    simState.winnerDeclared = true
                    SimulationEngine.spawnConfetti(state: &simState, settings: settings)
                    confettiSpawned = true
                    winnerTime = simTime
                } else {
                    done = true
                }
            }
            
            if frameIndex > estimatedFrames + 300 { done = true }
        }
        
        let totalFrames = frames.count
        
        // Write MP4
        try await writeMP4(
            frames: frames,
            totalFrames: totalFrames,
            settings: settings,
            theme: theme,
            fps: fps,
            conversionEvents: conversionEvents,
            outputURL: job.outputURL,
            progress: progress
        )
        
        // Post-export validation: confirm the file is a real, non-empty video.
        try await validateOutput(url: job.outputURL)
    }
    
    /// Verifies the exported file is non-empty and contains a valid video track.
    private func validateOutput(url: URL) async throws {
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw VideoExportError.writeFailed(NSError(domain: "VideoExporter", code: -10, userInfo: [NSLocalizedDescriptionKey: "Output file was not created."]))
        }
        let size = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int64) ?? 0
        guard size > 1024 else {
            throw VideoExportError.writeFailed(NSError(domain: "VideoExporter", code: -11, userInfo: [NSLocalizedDescriptionKey: "Output file is empty or truncated."]))
        }
        let asset = AVURLAsset(url: url)
        guard let tracks = try? await asset.loadTracks(withMediaType: .video), !tracks.isEmpty else {
            throw VideoExportError.writeFailed(NSError(domain: "VideoExporter", code: -12, userInfo: [NSLocalizedDescriptionKey: "Output has no video track."]))
        }
        guard let duration = try? await asset.load(.duration), duration.seconds > 0 else {
            throw VideoExportError.writeFailed(NSError(domain: "VideoExporter", code: -13, userInfo: [NSLocalizedDescriptionKey: "Output has zero duration."]))
        }
    }
    
    /// Deterministic tie-breaking based on the seed when the maximum duration is reached without a natural winner.
    private static func fallbackWinner(rock: Int, paper: Int, scissors: Int, seed: UInt32) -> EntityType {
        let counts = [(EntityType.rock, rock), (EntityType.paper, paper), (EntityType.scissors, scissors)]
        let maxCount = counts.map { $0.1 }.max() ?? 0
        let leaders = counts.filter { $0.1 == maxCount }.map { $0.0 }
        if leaders.count == 1 { return leaders[0] }
        // Deterministic tie-break: pick among leaders using the seed
        var rng = SeededRNG(seed: seed)
        return rng.pick(from: leaders)
    }
    
    // MARK: - AVAssetWriter pipeline
    
    private func writeMP4(
        frames: [(state: SimulationState, countdown: Int?, introAlpha: Double)],
        totalFrames: Int,
        settings: SimulationSettings,
        theme: Theme,
        fps: Int,
        conversionEvents: [(timestamp: Double, count: Int)],
        outputURL: URL,
        progress: @escaping (ExportProgress) -> Void
    ) async throws {
        // Write to a temporary ".part" file and atomically rename on success,
        // so cancelled/failed exports never leave a misleading .mp4 behind.
        let partURL = outputURL.appendingPathExtension("part")
        if FileManager.default.fileExists(atPath: partURL.path) {
            try FileManager.default.removeItem(at: partURL)
        }
        
        let writer: AVAssetWriter
        do {
            writer = try AVAssetWriter(outputURL: partURL, fileType: .mp4)
        } catch {
            throw VideoExportError.writerCreationFailed(error)
        }
        
        let W = Int(VideoFrameRenderer.exportWidth)
        let H = Int(VideoFrameRenderer.exportHeight)
        
        let videoSettings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: W,
            AVVideoHeightKey: H,
        ]
        
        guard writer.canApply(outputSettings: videoSettings, forMediaType: .video) else {
            throw VideoExportError.h264Unavailable
        }
        
        let videoInput = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings)
        videoInput.expectsMediaDataInRealTime = false
        videoInput.transform = CGAffineTransform.identity
        
        let pixelBufferAttributes: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: W,
            kCVPixelBufferHeightKey as String: H,
            kCVPixelBufferCGImageCompatibilityKey as String: true,
            kCVPixelBufferCGBitmapContextCompatibilityKey as String: true,
        ]
        
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: videoInput,
            sourcePixelBufferAttributes: pixelBufferAttributes
        )
        
        writer.add(videoInput)
        
        // Audio setup (only if sound is enabled; never a dependency for silent videos)
        var audioInput: AVAssetWriterInput? = nil
        var audioSamples: [Float] = []
        let sampleRate = AudioGenerator.sampleRate
        let samplesPerFrame = Int(sampleRate / Double(fps))
        if settings.soundEnabled {
            let audioSettings: [String: Any] = [
                AVFormatIDKey: kAudioFormatMPEG4AAC,
                AVSampleRateKey: sampleRate,
                AVNumberOfChannelsKey: 1,
                AVEncoderBitRateKey: 128_000,
            ]
            let input = AVAssetWriterInput(mediaType: .audio, outputSettings: audioSettings)
            input.expectsMediaDataInRealTime = false
            if writer.canAdd(input) {
                writer.add(input)
                audioInput = input
                let totalDuration = Double(frames.count) / Double(fps)
                audioSamples = AudioGenerator.mixAudio(
                    conversionEvents: conversionEvents,
                    totalDuration: totalDuration
                )
            }
        }
        
        guard writer.startWriting() else {
            throw VideoExportError.writeFailed(writer.error ?? NSError(domain: "VideoExporter", code: -1))
        }
        writer.startSession(atSourceTime: .zero)
        
        let group = DispatchGroup()
        let writeError = ErrorBox()
        
        // Depth of motion-trail history (in frames) when trails are enabled.
        let trailHistory = settings.trailsEnabled ? 6 : 0
        
        // Video: render frames on-demand and feed the writer via requestMediaDataWhenReady.
        let videoQueue = DispatchQueue(label: "com.rps.videowriter")
        let videoIndex = IndexBox()
        group.enter()
        videoInput.requestMediaDataWhenReady(on: videoQueue) { [cancelToken] in
            while videoInput.isReadyForMoreMediaData {
                if cancelToken.isCancelled {
                    videoInput.markAsFinished()
                    group.leave()
                    return
                }
                let idx = videoIndex.value
                if idx >= frames.count {
                    videoInput.markAsFinished()
                    group.leave()
                    return
                }
                
                // Acquire a pixel buffer, preferring the adaptor's pool.
                var pixelBuffer: CVPixelBuffer?
                var pbStatus: CVReturn = kCVReturnError
                if let pool = adaptor.pixelBufferPool {
                    pbStatus = CVPixelBufferPoolCreatePixelBuffer(nil, pool, &pixelBuffer)
                }
                if pixelBuffer == nil {
                    pbStatus = CVPixelBufferCreate(
                        nil, W, H,
                        kCVPixelFormatType_32BGRA,
                        pixelBufferAttributes as CFDictionary,
                        &pixelBuffer
                    )
                }
                
                guard let pb = pixelBuffer, pbStatus == kCVReturnSuccess else {
                    writeError.set(VideoExportError.pixelBufferPoolUnavailable)
                    videoInput.markAsFinished()
                    group.leave()
                    return
                }
                
                CVPixelBufferLockBaseAddress(pb, [])
                var rendered = false
                if let baseAddr = CVPixelBufferGetBaseAddress(pb) {
                    let bytesPerRow = CVPixelBufferGetBytesPerRow(pb)
                    if let cs = CGColorSpace(name: CGColorSpace.sRGB),
                       let ctx = CGContext(
                        data: baseAddr,
                        width: W,
                        height: H,
                        bitsPerComponent: 8,
                        bytesPerRow: bytesPerRow,
                        space: cs,
                        bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
                       ) {
                        let frame = frames[idx]
                        
                        // Motion trails: gather faded positions from recent frames.
                        var trailDots: [(type: EntityType, x: Double, y: Double, alpha: CGFloat)] = []
                        if trailHistory > 0 {
                            let start = max(0, idx - trailHistory)
                            for k in start..<idx {
                                let age = idx - k
                                let alpha = CGFloat(0.14) * (1.0 - CGFloat(age - 1) / CGFloat(trailHistory))
                                for e in frames[k].state.entities {
                                    trailDots.append((e.type, e.x, e.y, alpha))
                                }
                            }
                        }
                        
                        VideoFrameRenderer.renderFrame(
                            state: frame.state,
                            settings: settings,
                            theme: theme,
                            context: ctx,
                            countdownValue: frame.countdown,
                            introProgress: frame.introAlpha,
                            time: Double(idx) / Double(fps),
                            trailDots: trailDots
                        )
                        rendered = true
                    }
                }
                CVPixelBufferUnlockBaseAddress(pb, [])
                
                if !rendered {
                    writeError.set(VideoExportError.renderFailed)
                    videoInput.markAsFinished()
                    group.leave()
                    return
                }
                
                let pts = CMTime(value: CMTimeValue(idx), timescale: Int32(fps))
                if !adaptor.append(pb, withPresentationTime: pts) {
                    writeError.set(VideoExportError.writeFailed(writer.error ?? NSError(domain: "VideoExporter", code: -4)))
                    videoInput.markAsFinished()
                    group.leave()
                    return
                }
                videoIndex.value += 1
                
                if idx % 10 == 0 || idx == totalFrames - 1 {
                    let p = ExportProgress(
                        isExporting: true,
                        isCancelled: false,
                        currentFrame: idx + 1,
                        totalFrames: totalFrames,
                        message: "Rendering frame \(idx + 1) of \(totalFrames)…",
                        outputURL: outputURL,
                        error: nil
                    )
                    progress(p)
                }
            }
        }
        
        // Audio: feed synthesized pop samples interleaved with the video track.
        if let ai = audioInput {
            let audioQueue = DispatchQueue(label: "com.rps.audiowriter")
            let audioIndex = IndexBox()
            group.enter()
            ai.requestMediaDataWhenReady(on: audioQueue) { [cancelToken] in
                while ai.isReadyForMoreMediaData {
                    if cancelToken.isCancelled {
                        ai.markAsFinished()
                        group.leave()
                        return
                    }
                    let idx = audioIndex.value
                    if idx >= frames.count {
                        ai.markAsFinished()
                        group.leave()
                        return
                    }
                    let start = idx * samplesPerFrame
                    let end = min(start + samplesPerFrame, audioSamples.count)
                    if end > start {
                        if let sb = Self.audioSampleBuffer(
                            Array(audioSamples[start..<end]),
                            pts: CMTime(value: CMTimeValue(idx), timescale: Int32(fps)),
                            sampleRate: sampleRate
                        ) {
                            if !ai.append(sb) {
                                writeError.set(VideoExportError.writeFailed(writer.error ?? NSError(domain: "VideoExporter", code: -5)))
                                ai.markAsFinished()
                                group.leave()
                                return
                            }
                        } else {
                            writeError.set(VideoExportError.writeFailed(NSError(domain: "VideoExporter", code: -6, userInfo: [NSLocalizedDescriptionKey: "Could not create an audio sample buffer."])))
                            ai.markAsFinished()
                            group.leave()
                            return
                        }
                    }
                    audioIndex.value += 1
                }
            }
        }
        
        // Wait for both inputs to finish, then finalize.
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            group.notify(queue: .global()) { [cancelToken] in
                writer.finishWriting {
                    let cleanupPart = { try? FileManager.default.removeItem(at: partURL) }
                    if let we = writeError.error {
                        cleanupPart()
                        cont.resume(throwing: we)
                    } else if cancelToken.isCancelled {
                        cleanupPart()
                        cont.resume(throwing: VideoExportError.cancelled)
                    } else if writer.status == .failed {
                        cleanupPart()
                        cont.resume(throwing: VideoExportError.writeFailed(writer.error ?? NSError(domain: "VideoExporter", code: -2)))
                    } else if writer.status != .completed {
                        cleanupPart()
                        cont.resume(throwing: VideoExportError.writeFailed(writer.error ?? NSError(domain: "VideoExporter", code: -3)))
                    } else {
                        // Atomically promote the completed .part to the final .mp4.
                        do {
                            try? FileManager.default.removeItem(at: outputURL)
                            try FileManager.default.moveItem(at: partURL, to: outputURL)
                            cont.resume(returning: ())
                        } catch {
                            cleanupPart()
                            cont.resume(throwing: VideoExportError.writeFailed(error))
                        }
                    }
                }
            }
        }
    }
    
    // MARK: - Audio sample buffer helper
    
    private static func audioSampleBuffer(_ samples: [Float], pts: CMTime, sampleRate: Double) -> CMSampleBuffer? {
        guard let pcmBuffer = AudioGenerator.makePCMBuffer(from: samples, sampleRate: sampleRate) else { return nil }
        
        var format: CMAudioFormatDescription? = nil
        var asbd = pcmBuffer.format.streamDescription.pointee
        let fmtStatus = CMAudioFormatDescriptionCreate(
            allocator: kCFAllocatorDefault,
            asbd: &asbd,
            layoutSize: 0,
            layout: nil,
            magicCookieSize: 0,
            magicCookie: nil,
            extensions: nil,
            formatDescriptionOut: &format
        )
        guard fmtStatus == noErr, let fmt = format else { return nil }
        
        let frameCount = Int(pcmBuffer.frameLength)
        var timing = CMSampleTimingInfo(
            duration: CMTime(value: 1, timescale: CMTimeScale(sampleRate)),
            presentationTimeStamp: pts,
            decodeTimeStamp: .invalid
        )
        
        var sampleBuffer: CMSampleBuffer? = nil
        let createStatus = CMSampleBufferCreate(
            allocator: kCFAllocatorDefault,
            dataBuffer: nil,
            dataReady: false,
            makeDataReadyCallback: nil,
            refcon: nil,
            formatDescription: fmt,
            sampleCount: frameCount,
            sampleTimingEntryCount: 1,
            sampleTimingArray: &timing,
            sampleSizeEntryCount: 0,
            sampleSizeArray: nil,
            sampleBufferOut: &sampleBuffer
        )
        guard createStatus == noErr, let sb = sampleBuffer else { return nil }
        
        let setBufferStatus = CMSampleBufferSetDataBufferFromAudioBufferList(
            sb,
            blockBufferAllocator: kCFAllocatorDefault,
            blockBufferMemoryAllocator: kCFAllocatorDefault,
            flags: 0,
            bufferList: pcmBuffer.audioBufferList
        )
        guard setBufferStatus == noErr else { return nil }
        CMSampleBufferSetDataReady(sb)
        
        return sb
    }
    
    // MARK: - Safe filename
    
    /// Removes path separators and other illegal filename characters from a prefix.
    static func sanitizePrefix(_ prefix: String) -> String {
        let forbidden = CharacterSet(charactersIn: "/\\:?%*|\"<>").union(.controlCharacters)
        let sanitized = prefix.unicodeScalars.map { forbidden.contains($0) ? "_" : String($0) }.joined()
        let trimmed = sanitized.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "RPS_Battle" : trimmed
    }
    
    static func safeOutputURL(prefix: String, index: Int, outputFolder: URL) -> URL {
        let safePrefix = sanitizePrefix(prefix)
        let paddingWidth = 3
        let paddedIndex = String(format: "%0\(paddingWidth)d", index)
        var url = outputFolder.appendingPathComponent("\(safePrefix)_\(paddedIndex).mp4")
        
        var counter = 2
        while FileManager.default.fileExists(atPath: url.path) {
            url = outputFolder.appendingPathComponent("\(safePrefix)_\(paddedIndex)_\(counter).mp4")
            counter += 1
        }
        return url
    }
}
