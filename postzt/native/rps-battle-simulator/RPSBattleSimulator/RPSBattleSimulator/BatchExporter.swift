import Foundation
import AVFoundation

/// Sequential batch video export.
/// Processes jobs one at a time, maintains memory efficiency.
actor BatchExporter {
    
    private var isCancelled = false
    private var currentExporter: VideoExporter? = nil
    
    func cancel() {
        isCancelled = true
        Task { await currentExporter?.cancel() }
    }
    
    /// Run a batch of export jobs sequentially.
    func runBatch(
        jobs: [ExportJob],
        progress: @escaping (BatchProgress) -> Void
    ) async {
        isCancelled = false
        var batchProgress = BatchProgress(
            isRunning: true,
            totalVideos: jobs.count
        )
        progress(batchProgress)
        
        var statuses: [String: String] = [:]  // filename -> status
        var errors: [String: String] = [:]    // filename -> error
        let folder = jobs.first?.outputURL.deletingLastPathComponent()
        
        for (idx, job) in jobs.enumerated() {
            if isCancelled {
                // Mark remaining jobs as cancelled/unstarted in the manifest.
                for remaining in jobs[idx...] {
                    statuses[remaining.outputURL.lastPathComponent] = "cancelled"
                }
                batchProgress.isCancelled = true
                batchProgress.isRunning = false
                batchProgress.manifestURL = Self.writeManifest(jobs: jobs, statuses: statuses, errors: errors, folder: folder)
                progress(batchProgress)
                return
            }
            
            batchProgress.currentVideo = idx + 1
            batchProgress.currentSeed = job.settings.seed
            batchProgress.currentFilename = job.outputURL.lastPathComponent
            batchProgress.currentFrameFraction = 0
            progress(batchProgress)
            
            let exporter = VideoExporter()
            currentExporter = exporter
            
            do {
                try await exporter.export(job: job) { frameProgress in
                    var bp = batchProgress
                    bp.currentFrameFraction = frameProgress.fraction
                    progress(bp)
                }
                batchProgress.completedURLs.append(job.outputURL)
                statuses[job.outputURL.lastPathComponent] = "completed"
            } catch VideoExportError.cancelled {
                statuses[job.outputURL.lastPathComponent] = "cancelled"
                for remaining in jobs[(idx + 1)...] {
                    statuses[remaining.outputURL.lastPathComponent] = "cancelled"
                }
                batchProgress.isCancelled = true
                batchProgress.isRunning = false
                batchProgress.manifestURL = Self.writeManifest(jobs: jobs, statuses: statuses, errors: errors, folder: folder)
                progress(batchProgress)
                return
            } catch {
                batchProgress.failedIndices.append(idx + 1)
                batchProgress.failures.append(BatchFailure(
                    index: idx + 1,
                    filename: job.outputURL.lastPathComponent,
                    error: error.localizedDescription
                ))
                batchProgress.error = error.localizedDescription
                statuses[job.outputURL.lastPathComponent] = "failed"
                errors[job.outputURL.lastPathComponent] = error.localizedDescription
            }
            
            currentExporter = nil
        }
        
        batchProgress.isRunning = false
        batchProgress.currentVideo = batchProgress.totalVideos
        batchProgress.currentFrameFraction = 1.0
        
        // Write an export manifest describing every video in the batch.
        batchProgress.manifestURL = Self.writeManifest(jobs: jobs, statuses: statuses, errors: errors, folder: folder)
        
        progress(batchProgress)
    }
    
    /// Writes a CSV manifest mapping each video to its seed, settings, and explicit outcome.
    static func writeManifest(jobs: [ExportJob], statuses: [String: String], errors: [String: String], folder: URL?) -> URL? {
        guard let folder else { return nil }
        var rows = ["filename,seed,rock,paper,scissors,speed,wobble,fps,status,error"]
        for job in jobs {
            let name = job.outputURL.lastPathComponent
            let s = job.settings
            let status = statuses[name] ?? "unstarted"
            let err = errors[name] ?? ""
            let clean = { (s: String) in s.replacingOccurrences(of: ",", with: ";").replacingOccurrences(of: "\"", with: "'") }
            rows.append("\"\(clean(name))\",\(s.seed),\(s.rockCount),\(s.paperCount),\(s.scissorsCount),\(s.speed),\(s.wobble),\(s.exportFPS.rawValue),\(status),\"\(clean(err))\"")
        }
        let csv = rows.joined(separator: "\n")
        let url = folder.appendingPathComponent("manifest.csv")
        do {
            try csv.write(to: url, atomically: true, encoding: .utf8)
            return url
        } catch {
            return nil
        }
    }
    
    /// Build export jobs from a batch configuration.
    /// Throws if the output/batch folder cannot be created.
    static func buildJobs(
        config: BatchConfig,
        baseSettings: SimulationSettings,
        theme: Theme,
        outputFolder: URL,
        overrideEntities: [Entity]? = nil
    ) throws -> [ExportJob] {
        // Place each batch into its own timestamped subfolder so groups stay organized.
        let batchFolder = try Self.makeBatchFolder(prefix: baseSettings.filenamePrefix, parent: outputFolder)
        var jobs: [ExportJob] = []
        var randomSeedRNG = SeededRNG(seed: UInt32(truncatingIfNeeded: Int64(Date().timeIntervalSince1970 * 1000)))
        
        for i in 0..<config.count {
            var settings = baseSettings
            
            // Assign seed
            switch config.seedMode {
            case .sequential:
                settings.seed = config.startingSeed &+ UInt32(i)
            case .random:
                settings.seed = UInt32(truncatingIfNeeded: Int(randomSeedRNG.range(1, Double(UInt32.max))))
            }
            
            // If randomize settings is enabled, introduce variations.
            // Skip count variation for click-to-place (fixed layout) so the manifest
            // never disagrees with the actual exported entities.
            if config.randomizeSettings {
                var varRNG = SeededRNG(seed: settings.seed)
                if overrideEntities == nil {
                    settings.rockCount = varRNG.rangeInt(15, 45)
                    settings.paperCount = varRNG.rangeInt(15, 45)
                    settings.scissorsCount = varRNG.rangeInt(15, 45)
                }
                settings.speed = varRNG.range(0.8, 2.0)
                settings.wobble = varRNG.range(0.05, 0.3)
            }
            
            let url = VideoExporter.safeOutputURL(
                prefix: baseSettings.filenamePrefix,
                index: i + 1,
                outputFolder: batchFolder
            )
            
            let currentTheme = config.randomizeSettings ? ThemeManager.theme(for: settings.theme) : theme
            
            jobs.append(ExportJob(
                settings: settings,
                theme: currentTheme,
                outputURL: url,
                videoIndex: i + 1,
                overrideEntities: overrideEntities
            ))
        }
        
        return jobs
    }
    
    /// Create (if needed) and return a unique subfolder for a batch run.
    /// Batch folders always live inside an "output" folder under the chosen destination.
    static func makeBatchFolder(prefix: String, parent: URL) throws -> URL {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd_HHmmss"
        let stamp = formatter.string(from: Date())
        let safePrefix = VideoExporter.sanitizePrefix(prefix)
        let outputDir = parent.appendingPathComponent("output", isDirectory: true)
        let folder = outputDir.appendingPathComponent("\(safePrefix)_\(stamp)_\(Int.random(in: 0..<10000))")
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        } catch {
            throw VideoExportError.outputFolderUnwritable
        }
        return folder
    }
}
