//
//  ViewController.swift
//  PrivateLift
//
//  Created by Nelson Computers on 2026-05-31.
//

import UIKit
import WebKit
import HealthKit

class ViewController: UIViewController, WKScriptMessageHandler, WKUIDelegate {
    
    var webView: WKWebView!
    var statusBarStyle: UIStatusBarStyle = .default
    let healthStore = HKHealthStore()
    
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
        contentController.add(self, name: "applehealth")
        
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
                   debugLog("Fatal Error: index.html not found in main app bundle root.")
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
                webView.backgroundColor = UIColor.black // Pure pitch-black background to eliminate gray bleed
            } else {
                statusBarStyle = .darkContent
                webView.backgroundColor = UIColor(red: 0.98, green: 0.98, blue: 0.98, alpha: 1.0) // Light theme color matches bg-gray-50
            }
            
            // Animate the status bar color change smoothly
            UIView.animate(withDuration: 0.3) {
                self.setNeedsStatusBarAppearanceUpdate()
            }
        }
        
        // Handle Apple Health (HealthKit) sync bridges
        if message.name == "applehealth" {
            handleAppleHealthMessage(message)
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
                debugLog("Failed to save or share backup file: \(error)")
            }
        }
    }
    
    // Apple Health Integration Bridges
    private func handleAppleHealthMessage(_ message: WKScriptMessage) {
        guard HKHealthStore.isHealthDataAvailable() else {
            sendHealthStatusToWebView("unavailable")
            return
        }
        
        // A. Request Authorization
        if let bodyString = message.body as? String, bodyString == "requestAuthorization" {
            let writeTypes: Set<HKSampleType> = [
                HKObjectType.workoutType(),
                HKQuantityType.quantityType(forIdentifier: .bodyMass)!,
                HKQuantityType.quantityType(forIdentifier: .activeEnergyBurned)!
            ]
            let readTypes: Set<HKObjectType> = [
                HKQuantityType.quantityType(forIdentifier: .bodyMass)!
            ]
            
            healthStore.requestAuthorization(toShare: writeTypes, read: readTypes) { (success, error) in
                DispatchQueue.main.async {
                    self.sendHealthStatusToWebView(success && error == nil ? "authorized" : "failed")
                }
            }
        }
        
        // B. Save set as a strength workout session
        if let bodyDict = message.body as? [String: Any],
           let action = bodyDict["action"] as? String, action == "saveWorkout",
           let dateStr = bodyDict["date"] as? String,
           let exercise = bodyDict["exercise"] as? String,
           let weight = bodyDict["weight"] as? Double,
           let reps = bodyDict["reps"] as? Int,
           let setType = bodyDict["set_type"] as? String {
            
            let rpe = bodyDict["rpe"] as? Double
            saveWorkoutToAppleHealth(dateStr: dateStr, exercise: exercise, weight: weight, reps: reps, setType: setType, rpe: rpe)
        }
        
        // C. Save Body Weight entry
        if let bodyDict = message.body as? [String: Any],
           let action = bodyDict["action"] as? String, action == "saveWeight",
           let weightVal = bodyDict["weight"] as? Double,
           let unit = bodyDict["unit"] as? String {
            
            saveWeightToAppleHealth(weightVal: weightVal, unit: unit)
        }
    }
    
    private func sendHealthStatusToWebView(_ status: String) {
        let script = "onAppleHealthStatusChanged('\(status)')"
        webView.evaluateJavaScript(script, completionHandler: nil)
    }
    
    private func saveWorkoutToAppleHealth(dateStr: String, exercise: String, weight: Double, reps: Int, setType: String, rpe: Double?) {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        guard let workoutDate = dateFormatter.date(from: dateStr) else { return }
        
        // Calories estimation: Warmups burn ~3 kcal, working sets ~8 kcal
        let calories = setType == "warmup" ? 3.0 : 8.0
        let activeEnergy = HKQuantity(unit: .kilocalorie(), doubleValue: calories)
        
        let configuration = HKWorkoutConfiguration()
        configuration.activityType = .functionalStrengthTraining
        configuration.locationType = .indoor
        
        let builder = HKWorkoutBuilder(healthStore: healthStore, configuration: configuration, device: .local())
        
        Task {
            do {
                try await builder.beginCollection(at: workoutDate)
                
                // Add active energy burned sample associated with workout
                if let activeEnergyType = HKQuantityType.quantityType(forIdentifier: .activeEnergyBurned) {
                    let energySample = HKQuantitySample(
                        type: activeEnergyType,
                        quantity: activeEnergy,
                        start: workoutDate,
                        end: workoutDate.addingTimeInterval(3 * 60)
                    )
                    try await builder.addSamples([energySample])
                }
                
                let metadata: [String: Any] = [
                    HKMetadataKeyWorkoutBrandName: "Personal Lift",
                    HKMetadataKeyIndoorWorkout: true,
                    "Exercise": exercise,
                    "Weight": "\(weight)",
                    "Reps": "\(reps)",
                    "SetType": setType,
                    "RPE": rpe != nil ? "\(rpe!)" : "N/A"
                ]
                try await builder.addMetadata(metadata)
                
                try await builder.endCollection(at: workoutDate.addingTimeInterval(3 * 60))
                _ = try await builder.finishWorkout()
                debugLog("Workout successfully saved to Apple Health!")
            } catch {
                debugLog("Error saving workout to Apple Health: \(error.localizedDescription)")
            }
        }
    }
    
    private func saveWeightToAppleHealth(weightVal: Double, unit: String) {
        guard let weightType = HKQuantityType.quantityType(forIdentifier: .bodyMass) else { return }
        
        // Convert unit
        let hkUnit = unit == "lbs" ? HKUnit.pound() : HKUnit.gramUnit(with: .kilo)
        let quantity = HKQuantity(unit: hkUnit, doubleValue: weightVal)
        let weightSample = HKQuantitySample(type: weightType, quantity: quantity, start: Date(), end: Date())
        
        healthStore.save(weightSample) { (success, error) in
            if success {
                debugLog("Body Weight successfully updated in Apple Health!")
            } else {
                debugLog("Error saving weight to Apple Health: \(String(describing: error))")
            }
        }
    }
    
    // 5. Handle JavaScript alert() and confirm() natively in iOS
    func webView(_ webView: WKWebView, runJavaScriptAlertPanelWithMessage message: String, initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping () -> Void) {
        let alertController = UIAlertController(title: "Personal Lift", message: message, preferredStyle: .alert)
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
