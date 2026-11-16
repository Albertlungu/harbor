import Foundation
import Testing
@testable import HarborCore

struct SystemLogicTests {
    @Test func cpuPercentFromDeltas() {
        let a = CPUTicks(user: 100, system: 50, idle: 850, nice: 0)
        let b = CPUTicks(user: 150, system: 70, idle: 920, nice: 0)
        #expect(SystemLogic.cpuPercent(previous: a, current: b) == 50)
    }

    @Test func cpuPercentIgnoresBackwardsCounters() {
        let a = CPUTicks(user: 100, system: 50, idle: 850, nice: 0)
        #expect(SystemLogic.cpuPercent(previous: a, current: a) == 0)
        #expect(SystemLogic.cpuPercent(previous: a, current: CPUTicks(user: 1, system: 1, idle: 1, nice: 0)) == 0)
    }

    @Test func memoryPercent() {
        #expect(SystemLogic.memoryPercent(active: 2, wired: 1, compressed: 1, physical: 8) == 50)
        #expect(SystemLogic.memoryPercent(active: 1, wired: 1, compressed: 1, physical: 0) == 0)
    }

    @Test func usageThresholds() {
        #expect(SystemLogic.level(for: 59, reversed: false) == .good)
        #expect(SystemLogic.level(for: 60, reversed: false) == .warn)
        #expect(SystemLogic.level(for: 85, reversed: false) == .critical)
    }

    @Test func batteryThresholdsAreReversed() {
        #expect(SystemLogic.level(for: 19, reversed: true) == .critical)
        #expect(SystemLogic.level(for: 39, reversed: true) == .warn)
        #expect(SystemLogic.level(for: 40, reversed: true) == .good)
    }

    @Test func refreshIntervals() {
        #expect(SystemLogic.interval(forRate: "fast") == 1)
        #expect(SystemLogic.interval(forRate: "normal") == 2)
        #expect(SystemLogic.interval(forRate: "relaxed") == 5)
        #expect(SystemLogic.interval(forRate: "powerSaver") == 10)
    }

    @Test func ipv4RankingPrefersPrimaryAndDropsUnusable() {
        let ranked = SystemLogic.rankIPv4([
            .init(name: "lo0", address: "127.0.0.1"),
            .init(name: "utun3", address: "100.64.0.2"),
            .init(name: "en1", address: "10.0.0.9"),
            .init(name: "en0", address: "192.168.1.5"),
            .init(name: "en5", address: "169.254.1.1"),
            .init(name: "en6", address: "10.1.1.1", isUp: false),
        ])
        #expect(ranked.map(\.address) == ["192.168.1.5", "10.0.0.9", "100.64.0.2"])
    }

    @Test func durationText() {
        #expect(SystemLogic.durationText(minutes: 65) == "1h 05m")
        #expect(SystemLogic.durationText(minutes: 12) == "12m")
        #expect(SystemLogic.durationText(minutes: 0) == nil)
    }

    static let fixture = """
    {"SPBluetoothDataType":[{"device_connected":[
      {"Alice's AirPods Pro":{"device_address":"AA:01","device_minorType":"Headphones",
        "device_batteryLevelLeft":"85%","device_batteryLevelRight":"80%","device_batteryLevelCase":"40%"}},
      {"Magic Keyboard":{"device_address":"AA:02","device_minorType":"Keyboard","device_batteryLevelMain":"62%"}},
      {"Speaker":{"device_address":"AA:03","device_minorType":"Speaker"}}
    ],"device_not_connected":[
      {"Magic Mouse":{"device_address":"AA:04","device_minorType":"Mouse","device_batteryLevelMain":"15%"}}
    ]}]}
    """

    @Test func parsesBluetoothFixture() {
        let devices = BluetoothParser.parse(Data(Self.fixture.utf8))
        #expect(devices.count == 4)
        let pods = devices.first { $0.address == "AA:01" }
        #expect(pods?.left == 85 && pods?.right == 80 && pods?.caseLevel == 40 && pods?.main == nil)
        #expect(pods?.kind == .headphones && pods?.connected == true)
        #expect(devices.first { $0.address == "AA:04" }?.connected == false)
        #expect(devices.first { $0.address == "AA:04" }?.kind == .mouse)
        #expect(devices.first { $0.address == "AA:03" }?.hasBattery == false)
    }

    @Test func parseToleratesGarbage() {
        #expect(BluetoothParser.parse(Data("nope".utf8)).isEmpty)
        #expect(BluetoothParser.parse(Data("{}".utf8)).isEmpty)
    }

    @Test func readingsRespectSettings() {
        let devices = BluetoothParser.parse(Data(Self.fixture.utf8))
        let basic = BluetoothParser.readings(from: devices, includeOffline: false, includeNoBattery: false, splitAirPods: false, limit: 12)
        #expect(basic.map(\.percent) == [80, 62])
        let split = BluetoothParser.readings(from: devices, includeOffline: true, includeNoBattery: false, splitAirPods: true, limit: 12)
        #expect(split.map(\.label) == ["L", "R", "Case", nil, nil])
        #expect(split.last?.connected == false)
        #expect(BluetoothParser.readings(from: devices, includeOffline: true, includeNoBattery: true, splitAirPods: false, limit: 2).count == 2)
    }
}
