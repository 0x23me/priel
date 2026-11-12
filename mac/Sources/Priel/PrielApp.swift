import JuistKit
import SwiftUI

@main
struct PrielApp: App {
    @State private var monitor = Monitor()

    var body: some Scene {
        MenuBarExtra {
            JuistWindow(monitor: monitor)
                .onAppear { monitor.open = true }
                .onDisappear { monitor.open = false }
        } label: {
            Image(systemName: monitor.phase.symbol)
                .accessibilityLabel("juist, \(monitor.phase.label)")
        }
        .menuBarExtraStyle(.window)
    }
}
