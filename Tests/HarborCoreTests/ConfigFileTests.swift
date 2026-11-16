import Foundation
import Testing
@testable import HarborCore

@Suite struct ConfigFileTests {
    func tempFile() -> ConfigFile {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("harbor-tests-\(UUID().uuidString)", isDirectory: true)
        return ConfigFile(directory: dir)
    }

    func config(named name: String) -> Config {
        var c = Config()
        c.docks = [Dock(name: name)]
        return c
    }

    @Test func missingFileLoadsEmpty() {
        let file = tempFile()
        let (config, recovered) = file.load()
        #expect(config.docks.isEmpty && !recovered)
    }

    @Test func saveThenLoad() throws {
        let file = tempFile()
        try file.save(config(named: "A"))
        #expect(file.load().config.docks.first?.name == "A")
    }

    @Test func firstChangeOfDayTakesOneDailySnapshot() throws {
        let file = tempFile()
        let day = Date(timeIntervalSince1970: 1_800_000_000)
        try file.save(config(named: "A"), now: day)
        try file.save(config(named: "B"), now: day)
        try file.save(config(named: "C"), now: day.addingTimeInterval(60))
        #expect(file.snapshots().count == 1)
        try file.save(config(named: "D"), now: day.addingTimeInterval(86_400 * 2))
        #expect(file.snapshots().count == 2)
    }

    @Test func dailiesArePruned() throws {
        var file = tempFile()
        file.maxDailySnapshots = 3
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        try file.save(config(named: "0"), now: start)
        for d in 1...6 {
            try file.save(config(named: "\(d)"), now: start.addingTimeInterval(Double(d) * 86_400))
        }
        #expect(file.snapshots().filter { $0.reason == .daily }.count == 3)
    }

    @Test func restoreKeepsReplacedState() throws {
        let file = tempFile()
        let day = Date(timeIntervalSince1970: 1_800_000_000)
        try file.save(config(named: "Old"), now: day)
        try file.save(config(named: "Old"), now: day.addingTimeInterval(86_400))
        try file.save(config(named: "Current"), now: day.addingTimeInterval(86_401))
        let daily = try #require(file.snapshots().first { $0.reason == .daily })
        let restored = try file.restore(daily, now: day.addingTimeInterval(86_500))
        #expect(restored.docks.first?.name == "Old")
        #expect(file.load().config.docks.first?.name == "Old")
        let replaced = try #require(file.snapshots().first { $0.reason == .replacedByRestore })
        #expect(try ConfigFile.decode(Data(contentsOf: replaced.url)).docks.first?.name == "Current")
    }

    @Test func damagedConfigRecoversFromSnapshot() throws {
        let file = tempFile()
        let day = Date(timeIntervalSince1970: 1_800_000_000)
        try file.save(config(named: "Good"), now: day)
        try file.save(config(named: "Good"), now: day.addingTimeInterval(86_400))
        try Data("{broken".utf8).write(to: file.configURL)
        let (config, recovered) = file.load()
        #expect(recovered)
        #expect(config.docks.first?.name == "Good")
    }
}
