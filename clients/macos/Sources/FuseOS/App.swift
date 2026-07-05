import SwiftUI

@main
struct FuseOSApp: App {
    @StateObject private var session = SessionStore.shared

    var body: some Scene {
        WindowGroup("FuseOS") {
            Group {
                if session.token == nil {
                    AuthView()
                } else {
                    HomeView()
                }
            }
            .environmentObject(session)
            .frame(minWidth: 420, minHeight: 600)
        }
        .windowResizability(.contentSize)
    }
}
