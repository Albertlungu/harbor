import AppKit
import HarborCore
import SwiftUI

/// The guided tour. On first launch it also creates the first dock; reopened from the menu bar
/// it only walks through how Harbor works.
struct OnboardingView: View {
    @Environment(AppModel.self) private var model
    /// True on first launch, when the tour includes picking how to start.
    let firstRun: Bool
    /// HARBOR_TOUR_STEP opens the tour on a given step; a development aid for screenshots.
    @State private var step = ProcessInfo.processInfo.environment["HARBOR_TOUR_STEP"].flatMap(Int.init) ?? 0
    @State private var trusted = WindowControl.isTrusted
    /// The dock created on the start step, selected in the Manager when the tour ends.
    @State private var startedDock: UUID?
    @State private var started = false

    private var steps: [TourStep] {
        [.welcome] + (firstRun ? [.start] : []) + [.add, .edit, .folders, .pet, .weather, .permissions, .menu]
    }

    var body: some View {
        let current = steps[min(max(step, 0), steps.count - 1)]
        VStack(alignment: .leading, spacing: Tokens.Space.xl) {
            TourArt(step: current)
                .frame(maxWidth: .infinity)
                .frame(height: 150)
                .background(Tokens.surface, in: RoundedRectangle(cornerRadius: Tokens.Radius.popover))
            content(current)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            footer(current)
        }
        .padding(Tokens.Space.xxl)
        .frame(width: 560, height: 440)
        .onAppear { step = min(max(step, 0), steps.count - 1) }
        .onReceive(Timer.publish(every: 1, on: .main, in: .common).autoconnect()) { _ in trusted = WindowControl.isTrusted }
    }

    // MARK: Steps

    @ViewBuilder
    private func content(_ current: TourStep) -> some View {
        switch current {
        case .welcome:
            page(Copy.welcomeTitle(model.playful),
                 "Make as many docks as you like, put each on any edge of any screen, and fill them with apps, folders and widgets. This short tour shows you around.") {
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
                    .frame(width: 240)
                }
            }
        case .start:
            page("How do you want to start?", started ? "Done. Your dock is on screen; keep going to learn what it can do." : "Pick one; you can change everything later.") {
                HStack(spacing: Tokens.Space.l) {
                    if model.nativeDock.isReadable {
                        let replace = Copy.replaceDock(model.playful)
                        choice(replace.title, detail: replace.detail, symbol: "dock.rectangle") {
                            model.setReplaceNativeDock(true)
                            startedDock = model.selectedDockID
                            begin()
                        }
                    }
                    let fresh = Copy.emptyChoice(model.playful)
                    choice(fresh.title, detail: fresh.detail, symbol: "plus.rectangle") {
                        startedDock = model.store.createDock().id
                        begin()
                    }
                    let later = Copy.notNow(model.playful)
                    choice(later.title, detail: "Make a dock later from the Manager", symbol: "sidebar.left") {
                        begin(celebrate: false)
                    }
                }
                .disabled(started)
            }
        case .add: page(Copy.tourAdd(model.playful))
        case .edit: page(Copy.tourEdit(model.playful))
        case .folders: page(Copy.tourFolders(model.playful))
        case .pet: page(Copy.tourPet(model.playful))
        case .weather: page(Copy.tourWeather(model.playful))
        case .permissions:
            page(Copy.tourPermissions(model.playful)) {
                HStack {
                    Label(trusted ? "Accessibility is allowed" : "Accessibility is optional",
                          systemImage: trusted ? "checkmark.circle.fill" : "hand.raised")
                        .foregroundStyle(trusted ? Tokens.success : Tokens.textMuted)
                    Spacer()
                    if !trusted { Button("Allow Access…") { WindowControl.requestTrust() } }
                }
            }
        case .menu: page(Copy.tourMenu(model.playful))
        }
    }

    private func page(_ line: Copy.Line, @ViewBuilder extra: () -> some View = { EmptyView() }) -> some View {
        page(line.title, line.detail, extra: extra)
    }

    private func page(_ title: String, _ detail: String, @ViewBuilder extra: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: Tokens.Space.l) {
            Text(title).font(.title2.weight(.semibold))
            Text(detail).fixedSize(horizontal: false, vertical: true)
            extra()
        }
    }

    private func footer(_ current: TourStep) -> some View {
        // The dots sit in an overlay so they stay centred while the buttons around them change.
        HStack {
            if current != .menu {
                Button("Skip Tour") { finish() }.buttonStyle(.link)
            }
            Spacer()
            if step > 0 { Button("Back") { step -= 1 } }
            if current == .menu {
                Button("Done") { finish() }.keyboardShortcut(.defaultAction)
            } else {
                // The start step needs a choice before moving on, so a first dock exists or was declined.
                Button("Next") { advance() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(current == .start && !started)
            }
        }
        .overlay {
            HStack(spacing: Tokens.Space.s) {
                ForEach(steps.indices, id: \.self) { i in
                    Circle()
                        .fill(i == step ? Color.accentColor : Tokens.border)
                        .frame(width: 7, height: 7)
                }
            }
            .accessibilityElement()
            .accessibilityLabel("Step \(step + 1) of \(steps.count)")
        }
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

    // MARK: Flow

    private func advance() { step = min(step + 1, steps.count - 1) }

    /// Marks onboarding done as soon as the start choice is made, so closing the tour window
    /// early doesn't bring it back next launch and make a second dock.
    private func begin(celebrate: Bool = true) {
        started = true
        model.store.updateSettings { $0.onboardingDone = true }
        if celebrate { model.celebrateFirstDock() }
        advance()
    }

    private func finish() {
        model.windows.closeOnboarding()
        guard firstRun else { return }
        model.store.updateSettings { $0.onboardingDone = true }
        model.selectedDockID = startedDock ?? model.store.docks.first?.id
        model.windows.showManager()
    }
}

private enum TourStep { case welcome, start, add, edit, folders, pet, weather, permissions, menu }

/// A small live drawing for each tour step: a dock bar with the step's subject on it.
private struct TourArt: View {
    let step: TourStep

    var body: some View {
        let (hero, dock) = Self.symbols(for: step)
        VStack(spacing: Tokens.Space.l) {
            Image(systemName: hero)
                .font(.system(size: 40, weight: .regular))
                .foregroundStyle(Color.accentColor)
                .symbolRenderingMode(.hierarchical)
            HStack(spacing: Tokens.Space.m) {
                ForEach(dock, id: \.self) { symbol in
                    Image(systemName: symbol)
                        .font(.system(size: 18))
                        .frame(width: 34, height: 34)
                        .background(Tokens.dockSolid, in: RoundedRectangle(cornerRadius: 8))
                }
            }
            .padding(Tokens.Space.s)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Tokens.border))
        }
        .accessibilityHidden(true)
    }

    /// The large symbol above the bar and the symbols standing in for dock items.
    private static func symbols(for step: TourStep) -> (String, [String]) {
        switch step {
        case .welcome: ("dock.rectangle", ["dock.rectangle", "rectangle.split.3x1", "rectangle.bottomhalf.inset.filled"])
        case .start: ("plus.rectangle.on.rectangle", ["safari", "envelope", "music.note", "folder"])
        case .add: ("hand.draw", ["safari", "folder", "clock", "battery.75percent", "trash"])
        case .edit: ("contextualmenu.and.cursorarrow", ["pin", "slider.horizontal.3", "eye"])
        case .folders: ("folder", ["list.bullet", "square.grid.2x2", "doc", "photo"])
        case .pet: ("pawprint", ["pawprint", "hare", "bird", "tortoise"])
        case .weather: ("snowflake", ["leaf", "snowflake", "camera.macro", "photo.on.rectangle"])
        case .permissions: ("lock.shield", ["accessibility", "rectangle.dashed.badge.record", "applescript", "dot.radiowaves.left.and.right"])
        case .menu: ("menubar.rectangle", ["dock.rectangle", "gearshape", "photo.on.rectangle", "questionmark.circle"])
        }
    }
}
