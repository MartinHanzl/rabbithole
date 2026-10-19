import SwiftData
import SwiftUI

@main
struct RabbitholeApp: App {
    @State private var auth = AuthService()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(auth)
                .task { await auth.observeAuthChanges() }
                .onOpenURL { url in
                    Task { await auth.handle(url: url) }
                }
        }
        .modelContainer(for: PersistentSchema.models)
    }
}
