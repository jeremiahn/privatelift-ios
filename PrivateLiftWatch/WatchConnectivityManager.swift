// WatchConnectivityManager.swift
import Foundation
import WatchConnectivity
import Combine

/// Manages the WatchConnectivity session on the watchOS side in a robust, offline-first manner.
final class WatchConnectivityManager: NSObject, WCSessionDelegate, ObservableObject {
    static let shared = WatchConnectivityManager()
    
    @Published var setCount: Int = 0
    @Published var totalWeight: Double = 0.0
    @Published var exercises: [[String: String]] = []
    @Published var isActivated = false
    
    private override init() {
        super.init()
        guard WCSession.isSupported() else { return }
        WCSession.default.delegate = self
        WCSession.default.activate()
    }
    
    // MARK: - WCSessionDelegate
    
    func session(
        _ session: WCSession,
        activationDidCompleteWith activationState: WCSessionActivationState,
        error: Error?
    ) {
        DispatchQueue.main.async {
            self.isActivated = activationState == .activated
            if activationState == .activated {
                self.loadStoredData()
            }
        }
    }
    
    func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String : Any]) {
        DispatchQueue.main.async {
            self.processApplicationContext(applicationContext)
        }
    }
    
    private func loadStoredData() {
        processApplicationContext(WCSession.default.receivedApplicationContext)
    }
    
    private func processApplicationContext(_ context: [String: Any]) {
        if let summary = context["todaySummary"] as? [String: Any] {
            if let countNum = summary["setCount"] as? NSNumber {
                self.setCount = countNum.intValue
            } else {
                self.setCount = summary["setCount"] as? Int ?? 0
            }
            
            if let weightNum = summary["totalWeight"] as? NSNumber {
                self.totalWeight = weightNum.doubleValue
            } else {
                self.totalWeight = summary["totalWeight"] as? Double ?? 0.0
            }
        }
        if let list = context["exercises"] as? [[String: Any]] {
            self.exercises = list.map { dict in
                [
                    "name": dict["name"] as? String ?? "",
                    "displayName": dict["displayName"] as? String ?? "",
                    "colorHex": dict["colorHex"] as? String ?? ""
                ]
            }
        }
    }
    
    /// Queues a new set log to be sent to the iPhone via a reliable background transfer.
    func logSet(exercise: String, weight: Double, reps: Int, setType: String) {
        guard WCSession.isSupported() else { return }
        
        let payload: [String: Any] = [
            "exercise": exercise,
            "weight": weight,
            "reps": reps,
            "rpe": 8.0, // Sensible default RPE on the Watch to keep the UI clean
            "setType": setType,
            "timestamp": Date()
        ]
        
        // Optimistically update local summary metrics
        self.setCount += 1
        self.totalWeight += weight * Double(reps)
        
        // Transfer user info (reliable queued background transfer)
        WCSession.default.transferUserInfo(payload)
    }
}
