import AppKit
import HarborCore
import SwiftUI

/// First launch: explain, offer Accessibility, and create a first dock.
struct OnboardingView: View {
    @Environment(AppModel.self) private var model
    @State private var trusted = WindowControl.isTrusted

    var body: some View {
        VStack(alignment: .leading, spacing: Tokens.Space.xl) {
            Label(Copy.welcomeTitle(model.playful), systemImage: "dock.rectangle").font(.title2.weight(.semibold))
            Text("Make as many docks as you like, put each on any edge of any screen, and fill them with apps, folders and widgets.")
                .fixedSize(horizontal: false, vertical: true)

            GroupBox {
                VStack(alignment: .leading, spacing: Tokens.Space.s) {
                    HStack {
                        Text("Accessibility access").font(.headline)
                        Spacer()
                        Text(trusted ? "Allowed" : "Optional").foregroundStyle(trusted ? Tokens.success : Tokens.textMuted)
                    }
                    Text("Lets Harbor bring back the exact window you want, step through windows and keep windows off your docks. You can turn it on later in Settings.")
                        .font(.callout).foregroundStyle(Tokens.textMuted)
                        .fixedSize(horizontal: false, vertical: true)
                    if !trusted {
                        Button("Allow Access…") { WindowControl.requestTrust() }
                    }
                }
                .padding(Tokens.Space.s)
            }

            HStack {
                Text("How lively should Harbor be?").font(.headline)
                Spacer()
                Picker("Personality", selection: Binding(
                    get: { model.store.settings.personality },
                    set: { p in model.store.updateSettings { p.apply(to: &$0) } })) {
                    ForEach(Personality.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 260)
            }

            Text("How do you want to start?").font(.headline)
            HStack(spacing: Tokens.Space.l) {
                if model.nativeDock.isReadable {
                    let replace = Copy.replaceDock(model.playful)
                    choice(replace.title, detail: replace.detail, symbol: "dock.rectangle") {
                        model.setReplaceNativeDock(true)
                        finish(selecting: model.selectedDockID)
                        model.celebrateFirstDock()
                    }
                }
                let fresh = Copy.emptyChoice(model.playful)
                choice(fresh.title, detail: fresh.detail, symbol: "plus.rectangle") {
                    finish(selecting: model.store.createDock().id)
                    model.celebrateFirstDock()
                }
                let later = Copy.notNow(model.playful)
                choice(later.title, detail: later.detail, symbol: "sidebar.left") {
                    finish(selecting: nil)
                }
            }
        }
        .padding(Tokens.Space.xxl)
        .frame(width: 560)
        .onReceive(Timer.publish(every: 1, on: .main, in: .common).autoconnect()) { _ in trusted = WindowControl.isTrusted }
    }

    private func choice(_ title: String, detail: String, symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: Tokens.Space.s) {
                Image(systemName: symbol).font(.system(size: 24))
                Text(title).font(.callout.weight(.semibold))
                Text(detail).font(.caption).foregroundStyle(Tokens.textMuted).multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity, minHeight: 100)
            .padding(Tokens.Space.s)
            .background(Tokens.surface, in: RoundedRectangle(cornerRadius: Tokens.Radius.card))
        }
        .buttonStyle(.plain)
    }

    private func finish(selecting id: UUID?) {
        model.store.updateSettings { $0.onboardingDone = true }
        model.selectedDockID = id ?? model.store.docks.first?.id
        model.windows.closeOnboarding()
        model.windows.showManager()
    }
}
