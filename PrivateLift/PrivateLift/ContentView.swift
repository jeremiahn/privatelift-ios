import SwiftUI
import SwiftData

    // This wraps your custom ViewController so SwiftUI can display it
    struct ViewControllerRepresentable: UIViewControllerRepresentable {
        func makeUIViewController(context: Context) -> ViewController {
            return ViewController()
        }
                                                                                                                                                      
        func updateUIViewController(_ uiViewController: ViewController, context: Context) {}
    }
                                                                                                                                                      
    struct ContentView: View {
        @Environment(\.modelContext) private var modelContext

        var body: some View {
            MainTabView()
                .edgesIgnoringSafeArea(.all) // Bleed fullscreen
                .task {
                    DatabaseSeeder.seedDataIfNeeded(context: modelContext)
                }
        }
    }                                                          
