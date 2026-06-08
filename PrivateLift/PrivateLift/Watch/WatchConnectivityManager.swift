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
    /// Routes incoming Watch requests to the appropriate handler.
    func session(_ session: WCSession, didReceiveMessage message: [String: Any], replyHandler: @escaping ([String: Any]) -> Void) {
        guard let request = message["request"] as? String else { return }

        switch request {
        case "todaySummary":
            // WCSession callbacks arrive on a background thread; SwiftData's ModelContext
            // is @MainActor-bound, so we must hop to the main actor before fetching.
            Task { @MainActor in
                let summary = fetchTodaySummary()
                replyHandler(["summary": summary])
            }

        case "exercises":
            Task { @MainActor in
                let list = fetchExercises()
                replyHandler(["exercises": list])
            }

        case "logSet":
            Task { @MainActor in
                let success = saveSetFromWatch(message)
                replyHandler(["success": success])
            }

        default:
            break
        }
    }

    // MARK: - Helpers

    private static let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    @MainActor
    private func fetchTodaySummary() -> [String: Any] {
        guard let context = modelContext else { return [:] }
        let today = WatchConnectivityManager.dayFormatter.string(from: Date())
        let fetch = FetchDescriptor<WorkoutSet>(predicate: #Predicate { $0.session?.dateString == today })
        let sets = (try? context.fetch(fetch)) ?? []
        let totalWeight = sets.reduce(0.0) { $0 + $1.weight }
        return ["setCount": sets.count, "totalWeight": totalWeight]
    }

    /// Returns an array of exercise dictionaries the Watch can use to build its picker.
    @MainActor
    private func fetchExercises() -> [[String: Any]] {
        guard let context = modelContext else { return [] }
        let fetch = FetchDescriptor<CustomExercise>(sortBy: [SortDescriptor(\.orderIndex)])
        let exercises = (try? context.fetch(fetch)) ?? []
        return exercises.map { ex in
            [
                "name": ex.name,
                "displayName": ex.displayName,
                "colorHex": ex.colorHex
            ]
        }
    }

    /// Saves a WorkoutSet sent from the Watch.
    /// Expected keys: exercise (String), weight (Double), reps (Int), rpe (Double), setType (String)
    @MainActor
    private func saveSetFromWatch(_ message: [String: Any]) -> Bool {
        guard let context = modelContext,
              let exercise = message["exercise"] as? String,
              let weight = message["weight"] as? Double,
              let reps = message["reps"] as? Int,
              let rpe = message["rpe"] as? Double,
              let setType = message["setType"] as? String else {
            return false
        }

        let today = WatchConnectivityManager.dayFormatter.string(from: Date())
        let sessionFetch = FetchDescriptor<WorkoutSession>(predicate: #Predicate { $0.dateString == today })

        do {
            let session: WorkoutSession
            if let existing = try context.fetch(sessionFetch).first {
                session = existing
            } else {
                session = WorkoutSession(dateString: today)
                context.insert(session)
            }

            let newSet = WorkoutSet(
                exercise: exercise,
                weight: weight,
                reps: reps,
                rpe: rpe,
                setType: setType
            )
            newSet.session = session
            context.insert(newSet)
            try context.save()
            return true
        } catch {
            print("WatchConnectivityManager: failed to save set – \(error)")
            return false
        }
    }
}
