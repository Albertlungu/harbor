// Placeholder until the system widgets land. Delete when implementing.
import HarborCore
import SwiftUI
struct MonitorWidget: View { let item: DockItem; let widget: WidgetConfig; let dock: Dock; let size: CGSize; let state: DockViewState; var body: some View { Image(systemName: "hourglass").frame(width: size.width, height: size.height) } }
struct IPWidget: View { let item: DockItem; let widget: WidgetConfig; let dock: Dock; let size: CGSize; let state: DockViewState; var body: some View { Image(systemName: "hourglass").frame(width: size.width, height: size.height) } }
struct BluetoothWidget: View { let item: DockItem; let widget: WidgetConfig; let dock: Dock; let size: CGSize; let state: DockViewState; var body: some View { Image(systemName: "hourglass").frame(width: size.width, height: size.height) } }
struct SystemWidgetMenu: View { let item: DockItem; let dock: Dock; var body: some View { EmptyView() } }
struct SystemWidgetSettings: View { let item: DockItem; let dockID: UUID; var body: some View { EmptyView() } }
