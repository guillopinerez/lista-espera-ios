import SwiftUI

@main
struct ListaEsperaApp: App {
    @StateObject private var syncEngine = BackgroundSyncEngine.shared

    var body: some Scene {
        WindowGroup {
            ClientCardsView()
                .preferredColorScheme(.light)
                .onAppear {
                    syncEngine.setupNotifications()
                }
        }
    }
}
