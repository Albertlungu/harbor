import AppKit
import HarborCore
import SwiftUI

struct ClockWidget: View {
    let widget: WidgetConfig
    let size: CGSize
    let state: DockViewState

    var body: some View {
        let seconds = widget.bool("showSeconds", false)
        // Every tick lays out the whole dock panel, so a hidden dock's clock stops until it is shown.
        TimelineView(.animation(minimumInterval: seconds ? 1 : 15, paused: state.contentHidden)) { context in
            VStack(spacing: 0) {
                Text(timeString(context.date))
                    .font(font(size: size.height * (widget.bool("showDate", false) ? 0.32 : 0.4)))
                    .monospacedDigit()
                if widget.bool("showDate", false) {
                    Text(dateString(context.date))
                        .font(font(size: size.height * 0.2).weight(.regular))
                }
            }
            .lineLimit(1)
            .minimumScaleFactor(0.5)
            .foregroundStyle(textColor)
            .padding(.horizontal, Tokens.Space.xs)
            .frame(width: size.width, height: size.height)
            .background {
                if let bg = background {
                    RoundedRectangle(cornerRadius: widget.double("cornerRadius", 8)).fill(bg)
                }
            }
            .accessibilityLabel(timeString(context.date))
        }
        .contentShape(Rectangle())
        .onTapGesture {
            if widget.string("click", "none") == "dateTime" {
                NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.Date-Time-Settings.extension")!)
            }
        }
    }

    private var timeZone: TimeZone {
        let id = widget.string("timeZone", "")
        return id.isEmpty ? .current : TimeZone(identifier: id) ?? .current
    }

    private func timeString(_ date: Date) -> String {
        let f = DateFormatter()
        f.timeZone = timeZone
        let h24 = widget.string("hours", "system") == "24" || (widget.string("hours", "system") == "system" && Self.systemUses24h)
        let seconds = widget.bool("showSeconds", false)
        f.dateFormat = (h24 ? "HH:mm" : "h:mm") + (seconds ? ":ss" : "") + (h24 ? "" : " a")
        var s = f.string(from: date)
        if widget.bool("showZone", false) { s += " " + (timeZone.abbreviation(for: date) ?? "") }
        return s
    }

    private func dateString(_ date: Date) -> String {
        let f = DateFormatter()
        f.timeZone = timeZone
        switch widget.string("dateStyle", "short") {
        case "long": f.dateFormat = "EEEE, MMM d"
        case "custom": f.dateFormat = widget.string("dateFormat", "EEE d")
        default: f.dateFormat = "EEE d MMM"
        }
        return f.string(from: date)
    }

    private func font(size: CGFloat) -> Font {
        let design: Font.Design = switch widget.string("font", "system") {
        case "mono": .monospaced
        case "rounded": .rounded
        default: .default
        }
        return .system(size: max(size, 8), weight: widget.bool("bold", true) ? .semibold : .regular, design: design)
    }

    private var textColor: Color {
        colorSetting(widget, "textColor") ?? (Appearance.shared.themesDocks ? Appearance.shared.dockAccent(for: .clock) : Tokens.text)
    }
    private var background: Color? { colorSetting(widget, "background") }

    static var systemUses24h: Bool {
        let format = DateFormatter.dateFormat(fromTemplate: "j", options: 0, locale: .current) ?? ""
        return !format.contains("a")
    }
}

struct DividerWidget: View {
    let widget: WidgetConfig
    let size: CGSize
    let horizontal: Bool

    var body: some View {
        let color = colorSetting(widget, "color") ?? (Appearance.shared.dockWash ?? Tokens.textMuted).opacity(0.5)
        Rectangle()
            .fill(color)
            .frame(width: horizontal ? 1 : size.width * 0.7, height: horizontal ? size.height * 0.7 : 1)
            .frame(width: size.width, height: size.height)
            .accessibilityHidden(true)
    }
}

struct LabelWidget: View {
    let widget: WidgetConfig
    let size: CGSize
    let horizontal: Bool

    var body: some View {
        let scale: CGFloat = switch widget.string("textSize", "medium") {
        case "small": 0.22
        case "large": 0.36
        default: 0.28
        }
        let cross = horizontal ? size.height : size.width
        let alignment: HorizontalAlignment = switch widget.string("alignment", "center") {
        case "left": .leading
        case "right": .trailing
        default: .center
        }
        VStack(alignment: alignment, spacing: 0) {
            Text(widget.string("title", "Label")).font(.system(size: cross * scale, weight: .semibold))
            let subtitle = widget.string("subtitle", "")
            if !subtitle.isEmpty { Text(subtitle).font(.system(size: cross * scale * 0.7)).foregroundStyle(Tokens.textMuted) }
        }
        .lineLimit(1)
        .truncationMode(.tail)
        .foregroundStyle(colorSetting(widget, "color") ?? Tokens.text)
        .frame(width: horizontal ? size.width : size.height, height: horizontal ? size.height : size.width,
               alignment: Alignment(horizontal: alignment, vertical: .center))
        .rotationEffect(!horizontal && widget.bool("vertical", true) ? .degrees(-90) : .zero)
        .frame(width: size.width, height: size.height)
    }
}

/// Reads an RGBA stored as {"r","g","b","a"} in widget settings.
func colorSetting(_ widget: WidgetConfig, _ key: String) -> Color? {
    guard case .object(let o)? = widget.settings[key],
          let r = o["r"]?.doubleValue, let g = o["g"]?.doubleValue, let b = o["b"]?.doubleValue else { return nil }
    return Color(.sRGB, red: r, green: g, blue: b, opacity: o["a"]?.doubleValue ?? 1)
}

func colorValue(_ color: Color) -> JSONValue {
    let c = RGBA(color)
    return .object(["r": .number(c.red), "g": .number(c.green), "b": .number(c.blue), "a": .number(c.alpha)])
}
