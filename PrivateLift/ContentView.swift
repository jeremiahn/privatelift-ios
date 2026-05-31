import SwiftUI
                                                                                                                                                      
    // This wraps your custom ViewController so SwiftUI can display it
    struct ViewControllerRepresentable: UIViewControllerRepresentable {
        func makeUIViewController(context: Context) -> ViewController {
            return ViewController()
        }
                                                                                                                                                      
        func updateUIViewController(_ uiViewController: ViewController, context: Context) {}
    }
                                                                                                                                                      
    struct ContentView: View {
        var body: some View {
            ViewControllerRepresentable()
                .edgesIgnoringSafeArea(.all) // Bleed fullscreen, bypassing navigation bars
        }
    }                                                          
