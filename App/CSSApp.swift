import SwiftUI

@main
struct CSSApp: App {
    var body: some Scene {
        WindowGroup {
            MainView().preferredColorScheme(.dark)
        }
    }
}
