import HarborCore
import SwiftUI

/// CPU, memory, GPU and battery as a thin ring gauge.
struct MonitorWidget: View {
    let item: DockItem
    let widget: WidgetConfig
    let dock: Dock
    let size: CGSize
    let state: DockViewState

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var token = UUID()
    private let sampler = SystemSampler.shared

    private var rate: String { widget.string("refresh", "normal") }

    var body: some View {
        let reading = self.reading
        let showLabel = widget.bool("showLabel", true)
        let diameter = max(8, min(size.width, size.height * (showLabel ? 0.82 : 1)) * 0.92)
        VStack(spacing: size.height * 0.03) {
            gauge(reading, diameter: diameter)
            if showLabel {
                Text(reading.label)
                    .font(.system(size: max(7, diameter * Tokens.System.labelScale), weight: .medium, design: .rounded))
                    .foregroundStyle(Tokens.textMuted)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
            }
        }
        .frame(width: size.width, height: size.height)
        .help(reading.tooltip)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(reading.label)
        .accessibilityValue(reading.value.map { "\(Int($0.rounded())) percent" } ?? reading.unavailableText)
        .onAppear { sampler.register(token, rate: rate) }
        .onDisappear { sampler.unregister(token) }
        .onChange(of: rate) { sampler.register(token, rate: rate) }
    }

    private func gauge(_ reading: Reading, diameter: CGFloat) -> some View {
        let fraction = (reading.value ?? 0) / 100
        let tint = ringColor(reading)
        return ZStack {
            Circle().stroke(tint.opacity(Tokens.System.trackOpacity), lineWidth: diameter * Tokens.System.ringWidth)
            Circle()
                .trim(from: 0, to: fraction)
                .stroke(tint, style: StrokeStyle(lineWidth: diameter * Tokens.System.ringWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
            VStack(spacing: 0) {
                Image(systemName: reading.symbol)
                    .font(.system(size: diameter * Tokens.System.symbolScale, weight: .semibold))
                    .foregroundStyle(tint)
                digits(reading, diameter: diameter)
            }
        }
        .frame(width: diameter, height: diameter)
        .animation(reduceMotion ? nil : .easeOut(duration: Tokens.System.valueEase), value: fraction)
    }

    private func digits(_ reading: Reading, diameter: CGFloat) -> some View {
        let scale = widget.double("numberSize", 1)
        let fontSize = diameter * Tokens.System.digitScale * scale
        return Group {
            if let value = reading.value {
                Text("\(Int(value.rounded()))")
                    .font(.system(size: fontSize, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .contentTransition(.numericText())
            } else {
                Text(reading.unavailableText)
                    .font(.system(size: fontSize * 0.6, weight: .semibold, design: .rounded))
            }
        }
        .foregroundStyle(textColor)
        .lineLimit(1)
        .minimumScaleFactor(0.5)
        .frame(maxWidth: diameter * 0.8)
    }

    private func ringColor(_ reading: Reading) -> Color {
        guard let value = reading.value else { return Tokens.textMuted }
        let look = Appearance.shared
        if widget.string("colorMode", "auto") == "fixed" { return colorSetting(widget, "fixedColor") ?? look.dockAccent(for: widget.kind) }
        let level = SystemLogic.level(for: value, reversed: widget.kind == .battery)
        // Themed docks show the palette while all is well and keep the warning colours for trouble.
        if level == .good && look.themesDocks { return look.dockAccent(for: widget.kind) }
        return Tokens.System.color(for: level)
    }

    private var textColor: Color {
        guard widget.kind != .battery else { return Tokens.text }
        switch widget.string("textMode", "auto") {
        case "white": return .white
        case "black": return .black
        case "custom": return colorSetting(widget, "textColor") ?? Tokens.text
        default: return Tokens.text
        }
    }

    // MARK: Readings

    private struct Reading {
        var label: String
        var symbol: String
        var value: Double?
        var unavailableText = "N/A"
        var tooltip: String
    }

    private var reading: Reading {
        switch widget.kind {
        case .cpu?:
            Reading(label: "CPU", symbol: "cpu", value: sampler.cpu, unavailableText: "--", tooltip: percentTip("CPU", sampler.cpu))
        case .memory?:
            Reading(label: "Memory", symbol: "memorychip", value: sampler.memory, unavailableText: "--", tooltip: percentTip("Memory in use", sampler.memory))
        case .gpu?:
            Reading(label: "GPU", symbol: "square.3.layers.3d", value: sampler.gpu,
                    tooltip: sampler.gpu == nil ? "GPU usage isn't available on this Mac" : percentTip("GPU", sampler.gpu))
        default:
            batteryReading
        }
    }

    private var batteryReading: Reading {
        guard let info = sampler.battery else {
            let none = sampler.hasSampled
            return Reading(label: none ? "No battery" : "Battery", symbol: none ? "powerplug" : "battery.50percent", value: nil,
                           unavailableText: "--", tooltip: none ? "This Mac has no battery" : "Battery")
        }
        let symbol: String
        if info.isCharging {
            symbol = "bolt.fill"
        } else {
            symbol = switch info.percent {
            case ..<13: "battery.0percent"
            case ..<38: "battery.25percent"
            case ..<63: "battery.50percent"
            case ..<88: "battery.75percent"
            default: "battery.100percent"
            }
        }
        var tip = "Battery \(info.percent)%"
        if info.isCharging {
            tip += SystemLogic.durationText(minutes: info.minutesRemaining ?? 0).map { ", \($0) until full" } ?? ", charging"
        } else if info.pluggedIn {
            tip += ", on power"
        } else if let time = SystemLogic.durationText(minutes: info.minutesRemaining ?? 0) {
            tip += ", \(time) remaining"
        }
        return Reading(label: "Battery", symbol: symbol, value: Double(info.percent), tooltip: tip)
    }

    private func percentTip(_ name: String, _ value: Double?) -> String {
        value.map { "\(name) \(Int($0.rounded()))%" } ?? "\(name) is being measured"
    }
}
