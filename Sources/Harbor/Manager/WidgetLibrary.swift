import HarborCore
import SwiftUI

/// Searchable gallery of widgets grouped by category.
struct WidgetLibrary: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let dock: Dock
    @State private var category: WidgetCategory = .all
    @State private var query = ""
    @State private var lockedInfo: WidgetKind?
    @FocusState private var searchFocused: Bool

    var body: some View {
        let kinds = WidgetCatalog.kinds(in: category, matching: query)
        NavigationSplitView {
            List(WidgetCategory.allCases, id: \.self, selection: $category) { c in
                Text(c.title).tag(c)
            }
            .navigationSplitViewColumnWidth(160)
        } detail: {
            VStack(spacing: 0) {
                HStack {
                    TextField("Search widgets", text: $query)
                        .textFieldStyle(.roundedBorder)
                        .focused($searchFocused)
                        .onSubmit { if kinds.count == 1 { add(kinds[0]) } }
                    Button("Done") { dismiss() }
                }
                .padding(Tokens.Space.m)
                if kinds.isEmpty {
                    ContentUnavailableView.search(text: query)
                } else {
                    ScrollView {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: Tokens.Space.m)], spacing: Tokens.Space.m) {
                            ForEach(kinds, id: \.self) { kind in card(kind) }
                        }
                        .padding(Tokens.Space.m)
                    }
                }
            }
        }
        .frame(width: 680, height: 480)
        .background {
            Button("") { searchFocused = true }.keyboardShortcut("f").hidden()
        }
    }

    @ViewBuilder
    private func card(_ kind: WidgetKind) -> some View {
        let present = model.store.dock(dock.id)?.hasWidget(kind) == true
        let blocked = kind.singleInstance && present
        Button { blocked ? (lockedInfo = kind) : add(kind) } label: {
            VStack(alignment: .leading, spacing: Tokens.Space.s) {
                let tint = Self.tint(for: WidgetCatalog.category(for: kind))
                Image(systemName: WidgetCatalog.symbol(for: kind))
                    .font(.system(size: 26, weight: .medium))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(tint)
                    .frame(maxWidth: .infinity, minHeight: 54)
                    .background(tint.opacity(0.13), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                HStack {
                    Text(WidgetCatalog.name(for: kind)).font(.callout.weight(.semibold))
                    Spacer()
                    if present {
                        Text(blocked ? "In this dock" : "Added").font(.caption2).foregroundStyle(Tokens.textMuted)
                    }
                }
                Text(WidgetCatalog.summary(for: kind)).font(.caption).foregroundStyle(Tokens.textMuted)
                    .lineLimit(2, reservesSpace: true)
            }
            .padding(Tokens.Space.m)
            .background(RoundedRectangle(cornerRadius: Tokens.Radius.card).stroke(Tokens.border))
            .opacity(blocked ? 0.55 : 1)
        }
        .buttonStyle(.plain)
        .help(WidgetCatalog.summary(for: kind))
        .popover(isPresented: Binding(get: { lockedInfo == kind }, set: { if !$0 { lockedInfo = nil } })) {
            Text("A dock can hold only one \(WidgetCatalog.name(for: kind)).").padding()
        }
        .contextMenu {
            Button("Add") { add(kind) }.disabled(blocked)
        }
    }

    /// One soft hue per category so the gallery scans by color as well as by name.
    static func tint(for category: WidgetCategory) -> Color {
        switch category {
        case .apps: .blue
        case .folders: .teal
        case .clocks: .orange
        case .tasks: .purple
        case .system: .green
        case .all: Tokens.accent
        }
    }

    private func add(_ kind: WidgetKind) {
        guard let item = model.store.addWidget(kind, to: dock.id, settings: WidgetDefaultsBridge.settings(for: kind)) else { return }
        if kind.needsSetup {
            dismiss()
            model.itemSheet = ItemRef(dockID: dock.id, itemID: item.id)
        }
    }
}

/// Where the library gets starting settings for a new widget.
enum WidgetDefaultsBridge {
    static func settings(for kind: WidgetKind) -> [String: JSONValue] { [:] }
}
