// Placeholder until the tool widgets land. Delete when implementing.
import HarborCore
import SwiftUI
struct ClickerWidget: View { let item: DockItem; let widget: WidgetConfig; let dock: Dock; let size: CGSize; let state: DockViewState; var body: some View { Image(systemName: "hourglass").frame(width: size.width, height: size.height) } }
struct TimerWidget: View { let item: DockItem; let widget: WidgetConfig; let dock: Dock; let size: CGSize; let state: DockViewState; var body: some View { Image(systemName: "hourglass").frame(width: size.width, height: size.height) } }
struct MetronomeWidget: View { let item: DockItem; let widget: WidgetConfig; let dock: Dock; let size: CGSize; let state: DockViewState; var body: some View { Image(systemName: "hourglass").frame(width: size.width, height: size.height) } }
struct PetWidget: View { let item: DockItem; let widget: WidgetConfig; let dock: Dock; let size: CGSize; let state: DockViewState; var body: some View { Image(systemName: "hourglass").frame(width: size.width, height: size.height) } }
struct SpaceIndicatorWidget: View { let item: DockItem; let widget: WidgetConfig; let dock: Dock; let size: CGSize; let state: DockViewState; var body: some View { Image(systemName: "hourglass").frame(width: size.width, height: size.height) } }
struct ToolWidgetMenu: View { let item: DockItem; let dock: Dock; var body: some View { EmptyView() } }
struct ToolWidgetSettings: View { let item: DockItem; let dockID: UUID; var body: some View { EmptyView() } }
