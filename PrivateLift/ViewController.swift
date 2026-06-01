//
//  ViewController.swift
//  PrivateLift
//
//  Created by Nelson Computers on 2026-05-31.
//

import UIKit
import WebKit

class ViewController: UIViewController, WKScriptMessageHandler, WKUIDelegate {
    
    var webView: WKWebView!
    var statusBarStyle: UIStatusBarStyle = .default
    
    override var preferredStatusBarStyle: UIStatusBarStyle {
        return statusBarStyle
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        
        // 1. Configure WebView Settings & JavaScript Bridges
        let contentController = WKUserContentController()
        contentController.add(self, name: "haptic")
        contentController.add(self, name: "theme")
        contentController.add(self, name: "download")
        
        let config = WKWebViewConfiguration()
        config.userContentController = contentController
        
        // Allow local file loading and inline media playback
        config.allowsInlineMediaPlayback = true
        #if DEBUG
        config.preferences.setValue(true, forKey: "developerExtrasEnabled") // enables Safari dev inspect
        #endif
        
        // 2. Initialize WebView with fullscreen safe-area layout
        webView = WKWebView(frame: self.view.bounds, configuration: config)
        webView.uiDelegate = self
        webView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        webView.backgroundColor = UIColor.systemBackground
        webView.scrollView.contentInsetAdjustmentBehavior = .never // Full screen bleed
        webView.scrollView.bounces = false // Disable standard web elastic scroll bounce
        
        self.view.addSubview(webView)
        
        // 3. Load Offline Bundle Files
        loadOfflineWebAssets()
    }
    
    private func loadOfflineWebAssets() {
               // Looks for index.html flat in the main app bundle root
               guard let url = Bundle.main.url(forResource: "index", withExtension: "html", subdirectory: "web") else {
                   print("Fatal Error: index.html not found in main app bundle root.")
                   return
               }   
        
        // Safely load local files from app storage
        webView.loadFileURL(url, allowingReadAccessTo: url.deletingLastPathComponent())
    }
    
    // 4. Handle JavaScript-to-Swift Messages
    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        
        // Handle Taptic Engine Haptic Feedback
        if message.name == "haptic", let body = message.body as? String {
            switch body {
            case "success":
                let generator = UINotificationFeedbackGenerator()
                generator.notificationOccurred(.success)
            case "warning":
                let generator = UINotificationFeedbackGenerator()
                generator.notificationOccurred(.warning)
            case "error":
                let generator = UINotificationFeedbackGenerator()
                generator.notificationOccurred(.error)
            case "heavy":
                let generator = UIImpactFeedbackGenerator(style: .heavy)
                generator.impactOccurred()
            default: // medium tap
                let generator = UIImpactFeedbackGenerator(style: .medium)
                generator.impactOccurred()
            }
        }
        
        // Handle dynamic iOS Status Bar coloring based on Light/Dark Mode
        if message.name == "theme", let theme = message.body as? String {
            if theme == "dark" {
                statusBarStyle = .lightContent
                webView.backgroundColor = UIColor(red: 0.07, green: 0.09, blue: 0.13, alpha: 1.0) // Dark theme color matches dark:bg-gray-900
            } else {
                statusBarStyle = .darkContent
                webView.backgroundColor = UIColor(red: 0.98, green: 0.98, blue: 0.98, alpha: 1.0) // Light theme color matches bg-gray-50
            }
            
            // Animate the status bar color change smoothly
            UIView.animate(withDuration: 0.3) {
                self.setNeedsStatusBarAppearanceUpdate()
            }
        }
        
        // Handle file downloads from WebView by presenting an iOS Share Sheet (UIActivityViewController)
        if message.name == "download", let body = message.body as? [String: Any],
           let filename = body["filename"] as? String,
           let content = body["content"] as? String {
            
            let tempDir = FileManager.default.temporaryDirectory
            let fileURL = tempDir.appendingPathComponent(filename)
            
            do {
                try content.write(to: fileURL, atomically: true, encoding: .utf8)
                
                DispatchQueue.main.async {
                    let activityVC = UIActivityViewController(activityItems: [fileURL], applicationActivities: nil)
                    
                    if let popoverController = activityVC.popoverPresentationController {
                        popoverController.sourceView = self.webView
                        popoverController.sourceRect = CGRect(x: self.webView.bounds.midX, y: self.webView.bounds.midY, width: 0, height: 0)
                        popoverController.permittedArrowDirections = []
                    }
                    
                    self.present(activityVC, animated: true, completion: nil)
                }
            } catch {
                print("Failed to save or share backup file: \(error)")
            }
        }
    }
    
    // 5. Handle JavaScript alert() and confirm() natively in iOS
    func webView(_ webView: WKWebView, runJavaScriptAlertPanelWithMessage message: String, initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping () -> Void) {
        let alertController = UIAlertController(title: "PrivateLift", message: message, preferredStyle: .alert)
        alertController.addAction(UIAlertAction(title: "OK", style: .default, handler: { _ in
            completionHandler()
        }))
        self.present(alertController, animated: true, completion: nil)
    }
    
    func webView(_ webView: WKWebView, runJavaScriptConfirmPanelWithMessage message: String, initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping (Bool) -> Void) {
        let title: String
        let lower = message.lowercased()
        if lower.contains("delete") || lower.contains("remove") || lower.contains("danger") {
            title = "Confirm Deletion"
        } else if lower.contains("unit") {
            title = "Change Primary Unit"
        } else {
            title = "Confirm"
        }
        
        let alertController = UIAlertController(title: title, message: message, preferredStyle: .alert)
        alertController.addAction(UIAlertAction(title: "Cancel", style: .cancel, handler: { _ in
            completionHandler(false)
        }))
        alertController.addAction(UIAlertAction(title: "Proceed", style: .default, handler: { _ in
            completionHandler(true)
        }))
        self.present(alertController, animated: true, completion: nil)
    }
}
