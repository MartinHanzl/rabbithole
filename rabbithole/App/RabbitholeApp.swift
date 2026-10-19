import SwiftData
import SwiftUI

@main
struct RabbitholeApp: App {
    var body: some Scene {
        WindowGroup {
            RootView()
        }
        .modelContainer(for: PersistentSchema.models)
    }
}
