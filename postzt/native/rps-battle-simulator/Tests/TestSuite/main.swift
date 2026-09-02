import Foundation
import AVFoundation

var failures = 0

func check(_ cond: Bool, _ msg: String) {
    if cond {
        print("  PASS  \(msg)")
    } else {
        failures += 1
        print("  FAIL  \(msg)")
    }
    fflush(stdout)
}

func expectEqual<T: Equatable>(_ a: T, _ b: T, _ msg: String) {
    check(a == b, "\(msg)  (\(a) == \(b))")
}

func testDeterminism() {
    print("\n== Seed determinism ==")
    var s1 = SimulationSettings(); s1.seed = 12345
    var s2 = SimulationSettings(); s2.seed = 12345
    var a = SimulationEngine.spawnFresh(settings: s1)
    var b = SimulationEngine.spawnFresh(settings: s2)
    check(a.entities.count == b.entities.count, "same entity count")
    check(a.entities.count == s1.rockCount + s1.paperCount + s1.scissorsCount, "spawned all entities")
    for _ in 0..<50 {
        SimulationEngine.tick(state: &a, settings: s1, dt: 1.0)
        SimulationEngine.tick(state: &b, settings: s2, dt: 1.0)
    }
    var identical = true
    for i in 0..<a.entities.count where identical {
        if a.entities[i].x != b.entities[i].x || a.entities[i].y != b.entities[i].y || a.entities[i].type != b.entities[i].type {
            identical = false
        }
    }
    check(identical, "identical trajectory for identical seed")
}

func testConversionRules() {
    print("\n== Conversion rules ==")
    expectEqual(EntityType.rock.beats, .scissors, "rock beats scissors")
    expectEqual(EntityType.scissors.beats, .paper, "scissors beats paper")
    expectEqual(EntityType.paper.beats, .rock, "paper beats rock")
}

func testWinnerDetection() {
    print("\n== Winner detection ==")
    var settings = SimulationSettings()
    var oneType = SimulationState.empty(settings: settings)
    oneType.entities = [
        Entity(id: 0, type: .rock, x: 10, y: 10, vx: 0, vy: 0),
        Entity(id: 1, type: .rock, x: 20, y: 20, vx: 0, vy: 0),
    ]
    SimulationEngine.checkWinner(state: &oneType)
    check(oneType.winnerDeclared && oneType.winner == .rock, "winner when single type remains")

    var mixed = SimulationState.empty(settings: settings)
    mixed.entities = [
        Entity(id: 0, type: .rock, x: 10, y: 10, vx: 0, vy: 0),
        Entity(id: 1, type: .paper, x: 20, y: 20, vx: 0, vy: 0),
    ]
    SimulationEngine.checkWinner(state: &mixed)
    check(!mixed.winnerDeclared, "no winner while multiple types remain")
}

func testSanitizePrefix() {
    print("\n== Filename prefix sanitization ==")
    expectEqual(VideoExporter.sanitizePrefix("abc/def"), "abc_def", "strip slash")
    expectEqual(VideoExporter.sanitizePrefix("a\\b:c"), "a_b_c", "strip backslash/colon")
    expectEqual(VideoExporter.sanitizePrefix("   "), "RPS_Battle", "blank falls back")
    expectEqual(VideoExporter.sanitizePrefix("normal"), "normal", "valid prefix unchanged")
}

func testSafeOutputURL() {
    print("\n== Safe output URL ==")
    let url = VideoExporter.safeOutputURL(prefix: "a/b/c", index: 1, outputFolder: URL(fileURLWithPath: "/tmp"))
    check(!url.lastPathComponent.contains("/"), "no path separators in filename")
    expectEqual(url.pathExtension, "mp4", "mp4 extension")
}

func testBatchJobs() throws {
    print("\n== Batch jobs ==")
    var settings = SimulationSettings()
    settings.filenamePrefix = "Test"
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent("rps-tests-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: folder) }

    let config = BatchConfig(count: 3, seedMode: .sequential, startingSeed: 100)
    let jobs = try BatchExporter.buildJobs(config: config, baseSettings: settings, theme: ThemeManager.theme(for: .default), outputFolder: folder)
    expectEqual(jobs.count, 3, "3 jobs")
    expectEqual(jobs[0].settings.seed, UInt32(100), "seed 0 == 100")
    expectEqual(jobs[1].settings.seed, UInt32(101), "seed 1 == 101")
    expectEqual(jobs[2].settings.seed, UInt32(102), "seed 2 == 102")
    check(jobs.allSatisfy { $0.outputURL.path.contains("/output/") }, "videos live in 'output' subfolder")

    let randomConfig = BatchConfig(count: 20, seedMode: .random, startingSeed: 1)
    let rjobs = try BatchExporter.buildJobs(config: randomConfig, baseSettings: settings, theme: ThemeManager.theme(for: .default), outputFolder: folder)
    expectEqual(Set(rjobs.map { $0.settings.seed }).count, rjobs.count, "random seeds unique")
}

func testCancellation() async {
    print("\n== Cancellation ==")
    var settings = SimulationSettings()
    settings.seed = 7
    settings.maxDuration = .custom(20.0)
    settings.countdownEnabled = false
    settings.soundEnabled = false
    let out = FileManager.default.temporaryDirectory.appendingPathComponent("rps-cancel-\(UUID().uuidString).mp4")
    defer { try? FileManager.default.removeItem(at: out) }
    let job = ExportJob(settings: settings, theme: ThemeManager.theme(for: .default), outputURL: out, videoIndex: 1)
    let exporter = VideoExporter()
    await exporter.cancel()
    do {
        try await exporter.export(job: job) { _ in }
        check(false, "cancelled export throws")
    } catch {
        if let vee = error as? VideoExportError, case .cancelled = vee {
            check(true, "throws VideoExportError.cancelled")
        } else {
            check(false, "throws .cancelled (got \(error))")
        }
    }
    // No .mp4 or .part files should be left behind.
    check(!FileManager.default.fileExists(atPath: out.path), "no .mp4 left after cancel")
    check(!FileManager.default.fileExists(atPath: out.path + ".part"), "no .part left after cancel")
}

func testPresetValidation() {
    print("\n== Preset validation ==")
    var s = SimulationSettings()
    s.rockCount = -5
    s.arenaWidth = 99999
    s.speed = 999
    s.wobble = -3
    let v = s.validated()
    check(v.rockCount >= 0 && v.rockCount <= 240, "entity count clamped")
    check(v.arenaWidth <= 1200, "arena width clamped")
    check(v.speed <= 10, "speed clamped")
    check(v.wobble >= 0, "wobble clamped")
}

func testMP4Export() async {
    print("\n== MP4 export validity ==")
    var settings = SimulationSettings()
    settings.seed = 42
    settings.rockCount = 8; settings.paperCount = 8; settings.scissorsCount = 8
    settings.maxDuration = .custom(2.0)
    settings.countdownEnabled = false
    settings.soundEnabled = false
    let out = FileManager.default.temporaryDirectory.appendingPathComponent("rps-export-\(UUID().uuidString).mp4")
    defer { try? FileManager.default.removeItem(at: out) }
    let job = ExportJob(settings: settings, theme: ThemeManager.theme(for: .default), outputURL: out, videoIndex: 1)
    let exporter = VideoExporter()
    do {
        try await exporter.export(job: job) { _ in }
        check(FileManager.default.fileExists(atPath: out.path), "output file exists")
        let asset = AVURLAsset(url: out)
        let tracks = try await asset.loadTracks(withMediaType: .video)
        expectEqual(tracks.count, 1, "one video track")
        if let track = tracks.first {
            let size = try await track.load(.naturalSize)
            check(Int(size.width) == 1080 && Int(size.height) == 1920, "1080x1920 resolution")
        }
    } catch {
        check(false, "export succeeded (got \(error))")
    }
}

print("RPSBattleSimulator — automated test suite")
testDeterminism()
testConversionRules()
testWinnerDetection()
testSanitizePrefix()
testSafeOutputURL()
        do { try testBatchJobs() } catch { check(false, "batch jobs threw: \(error)") }
        testPresetValidation()
        await testCancellation()
        await testMP4Export()
if failures == 0 {
    print("\nALL TESTS PASSED")
} else {
    print("\n\(failures) TEST(S) FAILED")
    exit(1)
}


