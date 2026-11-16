import AppKit
import Foundation
import HarborCore
import SwiftUI

/// Bluetooth accessories from system_profiler, shared by every Bluetooth widget.
@MainActor
@Observable
final class BluetoothModel {
    static let shared = BluetoothModel()

    private(set) var devices: [BluetoothDevice] = []
    private(set) var loaded = false

    @ObservationIgnored private var loop: SystemLoop?

    private init() {
        loop = SystemLoop { [weak self] in await self?.refresh() }
    }

    func register(_ id: UUID, minutes: Double) {
        loop?.register(id, interval: max(1, min(15, minutes)) * 60)
    }

    func unregister(_ id: UUID) {
        loop?.unregister(id)
    }

    func refresh() async {
        let data = await Self.runProfiler()
        devices = BluetoothParser.parse(data)
        loaded = true
    }

    /// system_profiler takes a second or more, so it never runs on the main actor.
    private nonisolated static func runProfiler() async -> Data {
        await Task.detached(priority: .utility) {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/sbin/system_profiler")
            process.arguments = ["SPBluetoothDataType", "-json"]
            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = FileHandle.nullDevice
            guard (try? process.run()) != nil else { return Data() }
            // Drain before waiting; the output can exceed the pipe buffer.
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            return data
        }.value
    }
}

struct BluetoothWidget: View {
    let item: DockItem
    let widget: WidgetConfig
    let dock: Dock
    let size: CGSize
    let state: DockViewState

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var token = UUID()
    private let bluetooth = BluetoothModel.shared

    private var minutes: Double { widget.double("minutes", 1) }

    private var readings: [BluetoothReading] {
        BluetoothParser.readings(
            from: bluetooth.devices,
            includeOffline: widget.bool("includeOffline", false),
            includeNoBattery: widget.bool("includeNoBattery", false),
            splitAirPods: widget.bool("splitAirPods", false),
            limit: Int(widget.double("maxDevices", 4)))
    }

    var body: some View {
        let readings = self.readings
        HStack(spacing: 0) {
            if readings.isEmpty {
                empty
            } else {
                ForEach(readings) { cell($0, count: readings.count) }
            }
        }
        .frame(width: size.width, height: size.height)
        .contentShape(Rectangle())
        .onTapGesture(perform: click)
        .help(readings.isEmpty ? "No Bluetooth devices" : readings.map { "\($0.name) \($0.percent.map { "\($0)%" } ?? "")" }.joined(separator: "\n"))
        .animation(reduceMotion ? nil : .easeOut(duration: Tokens.System.valueEase), value: readings)
        .onAppear { bluetooth.register(token, minutes: minutes) }
        .onDisappear { bluetooth.unregister(token) }
        .onChange(of: minutes) { bluetooth.register(token, minutes: minutes) }
    }

    private func cell(_ reading: BluetoothReading, count: Int) -> some View {
        let width = size.width / CGFloat(count)
        let icon = max(8, min(width * 0.6, size.height * 0.46))
        let low = widget.double("lowBattery", 20)
        let tint: Color = reading.percent.map { Double($0) < low ? Tokens.danger : Tokens.text } ?? Tokens.textMuted
        return VStack(spacing: size.height * 0.03) {
            Image(systemName: Self.symbol(for: reading))
                .font(.system(size: icon, weight: .regular))
                .foregroundStyle(tint)
            Text(reading.percent.map { "\($0)%" } ?? "--")
                .font(.system(size: max(7, icon * 0.5), weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(tint)
            if let label = reading.label {
                Text(label)
                    .font(.system(size: max(6, icon * 0.32), weight: .medium, design: .rounded))
                    .foregroundStyle(Tokens.textMuted)
            }
        }
        .lineLimit(1)
        .minimumScaleFactor(0.5)
        .opacity(reading.connected ? 1 : Tokens.System.offlineOpacity)
        .frame(width: width, height: size.height)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(reading.name) \(reading.label ?? "")")
        .accessibilityValue(reading.percent.map { "\($0) percent" } ?? "No battery reading")
    }

    private var empty: some View {
        VStack(spacing: size.height * 0.04) {
            Image(systemName: bluetooth.loaded ? "headphones.slash" : "headphones")
                .font(.system(size: size.height * 0.4))
            Text(bluetooth.loaded ? "No devices" : "Loading")
                .font(.system(size: max(7, size.height * 0.16), weight: .medium, design: .rounded))
        }
        .foregroundStyle(Tokens.textMuted)
        .frame(width: size.width, height: size.height)
    }

    private func click() {
        switch widget.string("click", "open") {
        case "refresh": Task { await bluetooth.refresh() }
        case "none": break
        default: NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.BluetoothSettings")!)
        }
    }

    /// Falls back when a symbol name is missing on this macOS version.
    private static func symbol(for reading: BluetoothReading) -> String {
        let isPods = reading.name.localizedCaseInsensitiveContains("airpods")
        let candidates: [String] = switch (reading.label, reading.kind) {
        case ("L"?, _): ["airpodpro.left", "headphones"]
        case ("R"?, _): ["airpodpro.right", "headphones"]
        case ("Case"?, _): ["airpodspro.chargingcase.wireless", "airpodspro", "headphones"]
        case (_, .headphones) where isPods: ["airpodspro", "headphones"]
        case (_, .headphones): ["headphones"]
        case (_, .keyboard): ["keyboard"]
        case (_, .mouse): ["computermouse"]
        case (_, .trackpad): ["rectangle.and.hand.point.up.left", "computermouse"]
        case (_, .speaker): ["hifispeaker"]
        case (_, .gamepad): ["gamecontroller"]
        case (_, .other): ["dot.radiowaves.left.and.right"]
        }
        return candidates.first { NSImage(systemSymbolName: $0, accessibilityDescription: nil) != nil } ?? "dot.radiowaves.left.and.right"
    }
}
