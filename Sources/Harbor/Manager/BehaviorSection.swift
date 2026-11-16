import AppKit
import Carbon.HIToolbox
import HarborCore
import SwiftUI

struct BehaviorSection: View {
    @Environment(AppModel.self) private var model
    let dock: Dock

    var body: some View {
        let pinned = dock.position.mode == .pinned
        Form {
            if dock.layout == .dock {
                Section("Auto-hide") {
                    Toggle("Hide automatically", isOn: dock[binding: model, \.behavior.autoHide])
                    if dock.behavior.autoHide {
                        if pinned {
                            Picker("Reveal", selection: dock[binding: model, \.behavior.revealTrigger]) {
                                Text("At the screen edge").tag(RevealTrigger.atEdge)
                                Text("Near the screen edge").tag(RevealTrigger.nearEdge)
                            }
                            if dock.behavior.revealTrigger == .nearEdge {
                                ValueSlider(title: "Distance", value: dock[binding: model, \.behavior.revealDistance],
                                            range: 4...120, unit: " pt")
                            }
                        } else {
                            ValueSlider(title: "Reveal distance", value: dock[binding: model, \.behavior.revealDistance],
                                        range: 4...200, unit: " pt")
                        }
                        delays
                    }
                }
            }

            Section("Visibility") {
                Picker("Show on", selection: dock[binding: model, \.behavior.showOn]) {
                    Text("All desktops").tag(SpacesVisibility.allSpaces)
                    Text("The current desktop (follows you)").tag(SpacesVisibility.activeSpace)
                    Text("One desktop only").tag(SpacesVisibility.pinnedSpace)
                }
                Toggle("Hide when an app is fullscreen", isOn: dock[binding: model, \.behavior.hideInFullscreen])
                Toggle("Fade when a window covers it", isOn: Binding(
                    get: { dock.behavior.hideOnWindowHover },
                    set: { on in model.store.updateDock(dock.id) {
                        $0.behavior.hideOnWindowHover = on
                        if on { $0.behavior.reserveSpace = false }
                    } }))
                if pinned && dock.layout == .dock {
                    Toggle("Peek at the edge while hidden", isOn: dock[binding: model, \.behavior.showAtEdgeWhileHidden])
                    if dock.behavior.showAtEdgeWhileHidden && !dock.behavior.autoHide { delays }
                }
            }

            Section("Window space") {
                if pinned {
                    Toggle("Keep windows from covering this dock", isOn: Binding(
                        get: { dock.behavior.reserveSpace },
                        set: { on in model.store.updateDock(dock.id) {
                            $0.behavior.reserveSpace = on
                            if on { $0.behavior.hideOnWindowHover = false }
                        } }))
                    if dock.behavior.reserveSpace && !model.store.settings.reserveDockSpace {
                        HStack {
                            Text("Window space keeping is off for the whole app.").font(.caption)
                            Button("Turn On") { model.store.updateSettings { $0.reserveDockSpace = true } }
                        }
                    }
                } else {
                    Text("Floating docks can't keep windows away. Pin the dock to an edge to use this.")
                        .font(.caption).foregroundStyle(Tokens.textMuted)
                }
            }

            Section("Clicks") {
                Picker("Clicking the frontmost app", selection: dock[binding: model, \.behavior.activeAppClick]) {
                    Text("Does nothing").tag(ActiveAppClick.none)
                    Text("Minimizes its window").tag(ActiveAppClick.minimize)
                    Text("Hides it").tag(ActiveAppClick.hide)
                    Text("Shows its next window").tag(ActiveAppClick.cycleWindows)
                }
            }

            Section("Badges") {
                Toggle("Show notification badges", isOn: dock[binding: model, \.behavior.showBadges])
                if dock.behavior.showBadges {
                    Toggle("Show the full number", isOn: dock[binding: model, \.behavior.fullBadgeNumber])
                    Text("Badges are read from the macOS Dock and need Accessibility access.")
                        .font(.caption).foregroundStyle(Tokens.textMuted)
                }
            }

            Section("Keyboard shortcut") {
                LabeledContent("Show or hide this dock") {
                    ShortcutRecorder(hotkey: dock[binding: model, \.behavior.hotkey])
                }
                if dock.behavior.hotkey != nil {
                    Picker("Hide again after", selection: dock[binding: model, \.behavior.hideAgainAfter]) {
                        Text("Never").tag(0.0)
                        Text("15 seconds").tag(15.0)
                        Text("30 seconds").tag(30.0)
                        Text("1 minute").tag(60.0)
                    }
                    let sharing = model.store.docks.filter { $0.id != dock.id && $0.behavior.hotkey == dock.behavior.hotkey }
                    if !sharing.isEmpty {
                        Text("Also toggles: \(sharing.map(\.name).joined(separator: ", "))")
                            .font(.caption).foregroundStyle(Tokens.textMuted)
                    }
                    if let error = HotkeyCenter.shared.failures[dock.id] {
                        Text(error).font(.caption).foregroundStyle(Tokens.danger)
                    }
                }
            }
        }
        .formStyle(.grouped)
    }

    @ViewBuilder
    private var delays: some View {
        PresetPicker(title: "Hide after", preset: dock[binding: model, \.behavior.hidePreset], custom: .custom,
                     value: dock[binding: model, \.behavior.customHideDelay], range: 0...5, unit: "s")
        PresetPicker(title: "Show after", preset: dock[binding: model, \.behavior.revealPreset], custom: .custom,
                     value: dock[binding: model, \.behavior.customRevealDelay], range: 0...2, unit: "s")
    }
}

/// Records a global shortcut. Needs at least one modifier; Escape cancels, Delete clears.
struct ShortcutRecorder: View {
    @Binding var hotkey: Hotkey?
    @State private var recording = false
    @State private var monitor: Any?

    var body: some View {
        HStack {
            Button(recording ? "Type a shortcut…" : (hotkey?.display ?? "Record Shortcut")) {
                recording ? stop() : start()
            }
            .frame(minWidth: 130)
            if hotkey != nil && !recording {
                Button { hotkey = nil } label: { Image(systemName: "xmark.circle.fill") }
                    .buttonStyle(.borderless)
                    .accessibilityLabel("Clear shortcut")
            }
        }
        .onDisappear(perform: stop)
    }

    private func start() {
        recording = true
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            switch Int(event.keyCode) {
            case kVK_Escape:
                stop()
            case kVK_Delete, kVK_ForwardDelete:
                hotkey = nil
                stop()
            default:
                let mods = event.modifierFlags.intersection([.command, .option, .control, .shift])
                guard !mods.isEmpty else { NSSound.beep(); return nil }
                hotkey = Hotkey(keyCode: UInt32(event.keyCode), modifiers: HotkeyCenter.carbonModifiers(mods),
                                display: HotkeyCenter.display(mods, event: event))
                stop()
            }
            return nil
        }
    }

    private func stop() {
        recording = false
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
    }
}
