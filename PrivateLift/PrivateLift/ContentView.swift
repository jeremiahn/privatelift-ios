import SwiftUI
import SwiftData

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext

    var body: some View {
        MainTabView()
            .edgesIgnoringSafeArea(.all) // Bleed fullscreen
            // ponytail: fonts scale with Dynamic Type; capped where fixed-size pills and
            // cards still clip. Raise the cap as those layouts move to flexible sizing.
            .dynamicTypeSize(...DynamicTypeSize.accessibility2)
            .task {
                DatabaseSeeder.seedDataIfNeeded(context: modelContext)
            }
    }
}
