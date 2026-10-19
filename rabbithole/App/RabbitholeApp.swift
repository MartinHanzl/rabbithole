import SwiftData
import SwiftUI

@main
struct RabbitholeApp: App {
    @State private var auth = AuthService()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(auth)
                .task { await auth.observeAuthChanges() }
                .task { await auth.observeSavedArticleChanges() }
                .onOpenURL { url in
                    Task { await auth.handle(url: url) }
                }
        }
        .modelContainer(for: PersistentSchema.models)
        .backgroundTask(.appRefresh(ActivityNotifier.refreshTaskID)) {
            await ActivityNotifier.runBackgroundCheck()
        }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .active: ActivityNotifier.markChecked()
            case .background: ActivityNotifier.scheduleNextRefresh()
            default: break
            }
        }
    }
}
