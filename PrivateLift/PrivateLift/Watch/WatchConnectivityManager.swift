// WatchConnectivityManager.swift
import Foundation
import WatchConnectivity
import SwiftData

/// Manages communication between the iPhone app and the Apple Watch extension.
final class WatchConnectivityManager: NSObject, WCSessionDelegate {
    static let shared = WatchConnectivityManager()
    private var session: WCSession?
    private var modelContext: ModelContext?

    private override init() {
        super.init()
        if WCSession.isSupported() {
            session = WCSession.default
            session?.delegate = self
            session?.activate()
        }
    }

    /// Provide the SwiftData model context so we can fetch data when requested by the watch.
    func configure(context: ModelContext) {
        self.modelContext = context
    }

    // MARK: - WCSessionDelegate
    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        // No‑op – activation handled automatically.
    }

    #if os(iOS)
    func sessionDidBecomeInactive(_ session: WCSession) {}
    func sessionDidDeactivate(_ session: WCSession) {
        session.activate()
    }
    #endif

    // MARK: - Message handling
    /// The watch can request a summary of today's workout data.
    func session(_ session: WCSession, didReceiveMessage message: [String : Any]) {
        guard let request = message["request"] as? String, request == "todaySummary" else { return }
        let summary = fetchTodaySummary()
        session.sendMessage(["summary": summary], replyHandler: nil, errorHandler: nil)
    }

    private func fetchTodaySummary() -> [String: Any] {
        guard let context = modelContext else { return [:] }
        // Simple summary: total sets and total weight lifted today.
        let today = todayString()
        let fetch = FetchDescriptor<WorkoutSet>(predicate: #Predicate { $0.session?.dateString == today })
        let sets = (try? context.fetch(fetch)) ?? []
        let totalWeight = sets.reduce(0.0) { $0 + $1.weight }
        return ["setCount": sets.count, "totalWeight": totalWeight]
    }

    private func todayString() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: Date())
    }
}
