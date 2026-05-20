import SwiftUI
import AppKit

@main
struct MargheritaApp: App {
    @StateObject private var model = IndicatorModel()

    var body: some Scene {
        MenuBarExtra {
            PopoverView(model: model)
        } label: {
            MenuBarLabel(model: model)
        }
        .menuBarExtraStyle(.window)
    }
}

/// Vista que vive en la menu bar. Cada vez que el modelo cambia,
/// regenera el NSImage y lo entrega como label de MenuBarExtra.
struct MenuBarLabel: View {
    @ObservedObject var model: IndicatorModel

    var body: some View {
        Image(nsImage: IconRenderer.render(
            percent: model.percent,
            resetProgress: model.resetProgress,
            shape: model.shape,
            polygonSides: model.polygonSides,
            isPlaceholder: model.dataSource == .statusLine && model.updatedAt == nil
        ))
    }
}
