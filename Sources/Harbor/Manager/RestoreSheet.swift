import AppKit
import HarborCore
import SwiftUI

/// Lists automatic snapshots and restores one after confirmation.
struct RestoreSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var snapshots: [Snapshot] = []
    @State private var pending: Snapshot?
    @State private var error: String?

    var body: some View {
        VStack(alignment: .leading, spacing: Tokens.Space.m) {
            Text("Restore a Backup").font(.headline)
            Text("Harbor saves a copy of your docks before the first change each day, before imports and before restores.")
                .font(.callout).foregroundStyle(Tokens.textMuted)
            if snapshots.isEmpty {
                let line = Copy.noBackups(model.playful)
                ContentUnavailableView(line.title, systemImage: "clock.arrow.circlepath", description: Text(line.detail))
            } else {
                List(snapshots) { snapshot in
                    HStack {
                        VStack(alignment: .leading) {
                            Text(snapshot.date.formatted(date: .abbreviated, time: .shortened))
                            Text(snapshot.reason.title).font(.caption).foregroundStyle(Tokens.textMuted)
                        }
                        Spacer()
                        Button("Restore…") { pending = snapshot }
                    }
                }
            }
            if let error { Text(error).foregroundStyle(Tokens.danger).font(.callout) }
            HStack {
                Spacer()
                Button("Close") { dismiss() }.keyboardShortcut(.cancelAction)
            }
        }
        .padding(Tokens.Space.xl)
        .frame(width: 460, height: 420)
        .onAppear { snapshots = model.file.snapshots() }
        .confirmationDialog(Copy.restoreConfirm(model.playful).title, isPresented: Binding(
            get: { pending != nil }, set: { if !$0 { pending = nil } }), presenting: pending
        ) { snapshot in
            Button("Replace") { restore(snapshot) }
            Button("Cancel", role: .cancel) {}
        } message: { _ in
            Text(Copy.restoreConfirm(model.playful).detail)
        }
    }

    private func restore(_ snapshot: Snapshot) {
        do {
            model.store.flush()
            let config = try model.file.restore(snapshot)
            model.store.replaceConfig(config)
            snapshots = model.file.snapshots()
            dismiss()
        } catch {
            self.error = error.localizedDescription
        }
    }
}
