import HarborCore
import SwiftUI

struct ClickerWidget: View {
    @Environment(AppModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let item: DockItem
    let widget: WidgetConfig
    let dock: Dock
    let size: CGSize
    let state: DockViewState

    @State private var popped = false

    var body: some View {
        let unit = Tokens.Tool.unit(size)
        let count = Int(widget.stateDouble("count") ?? 0)
        let caption = widget.string("caption", "")
        let radius = Tokens.Tool.chipRadius(unit)
        VStack(spacing: unit * 0.04) {
            Text("\(count)")
                .font(.system(size: unit * 0.4, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.4)
                .foregroundStyle(colorSetting(widget, "numberColor") ?? Tokens.text)
                .padding(.horizontal, unit * 0.1)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(
                    RoundedRectangle(cornerRadius: radius, style: .continuous)
                        .fill(colorSetting(widget, "chipColor") ?? Tokens.surface)
                        .overlay(RoundedRectangle(cornerRadius: radius, style: .continuous).strokeBorder(Tokens.border, lineWidth: 1))
                )
            if !caption.isEmpty {
                Text(caption)
                    .font(.system(size: max(unit * 0.17, 8)))
                    .lineLimit(1)
                    .foregroundStyle(Tokens.textMuted)
            }
        }
        .padding(unit * 0.06)
        .frame(width: size.width, height: size.height)
        .scaleEffect(popped ? Tokens.Tool.pop : 1)
        .contentShape(Rectangle())
        .onTapGesture {
            ToolActions.bumpClicker(WidgetFields(model: model, itemID: item.id, dockID: dock.id), increase: true)
            pop()
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(caption.isEmpty ? "Counter" : caption)
        .accessibilityValue("\(count)")
        .accessibilityHint("Adds \(ClickerLogic.step(widget.double("step", 1)))")
        .accessibilityAddTraits(.isButton)
    }

    private func pop() {
        guard !reduceMotion else { return }
        withAnimation(Tokens.Tool.popSpring) { popped = true } completion: {
            withAnimation(Tokens.Tool.popSpring) { popped = false }
        }
    }
}
