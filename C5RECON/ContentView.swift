import SwiftUI

struct ContentView: View {
    @StateObject private var session = SessionModel()
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        Group {
            if session.state.role == nil {
                RoleSelectionView(session: session)
            } else {
                SessionView(session: session)
            }
        }
        .preferredColorScheme(.dark)
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .active {
                session.resumeTransportAfterForegroundTransition()
            }
        }
    }
}
