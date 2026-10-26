import SwiftUI

@main
struct AfterglowApp: App {
    @StateObject private var model = AppModel()
    var body: some Scene {
        WindowGroup {
            ContentView().environmentObject(model)
                .preferredColorScheme(.dark)
                .tint(Palette.orange)
        }
    }
}
