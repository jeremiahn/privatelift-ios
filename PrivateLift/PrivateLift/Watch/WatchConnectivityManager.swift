// WatchConnectivityManager.swift
import Foundation
import WatchConnectivity
import SwiftData
import CoreData

/// Manages communication between the iPhone app and the Apple Watch extension.
final class WatchConnectivityManager: NSObject, WCSessionDelegate {
    static let shared = WatchConnectivityManager()
    private var session: WCSession?
    private var modelContext: ModelContext?
    private var isObserverSetup = false

    private override init() {
        super.init()
        if WCSession.isSupported() {
            session = WCSession.default
            session?.delegate = self
            session?.activate()
        }
    }

    /// Provide the SwiftData model context so we can fetch data.
    func configure(context: ModelContext) {
        self.modelContext = context
        setupObserver()
        Task { @MainActor in
            sendUserDataToWatch()
        }
    }

    private func setupObserver() {
        guard !isObserverSetup else { return }
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(contextDidSave),
            name: .NSManagedObjectContextDidSave,
            object: nil
        )
        isObserverSetup = true
    }

    @objc private func contextDidSave(notification: Notification) {
        // Run on MainActor to safely read from ModelContext
        Task { @MainActor in
            sendUserDataToWatch()
        }
    }

    // MARK: - WCSessionDelegate
    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        if activationState == .activated {
            Task { @MainActor in
                sendUserDataToWatch()
            }
        }
    }

    #if os(iOS)
    func sessionDidBecomeInactive(_ session: WCSession) {}
    func sessionDidDeactivate(_ session: WCSession) {
        session.activate()
    }
    #endif

    // MARK: - User Info (Background Queued Transfers)
    func session(_ session: WCSession, didReceiveUserInfo userInfo: [String : Any] = [:]) {
        Task { @MainActor in
            saveSetFromWatch(userInfo)
        }
    }

    // MARK: - Message Handling (Interactive Fallback)
    func session(_ session: WCSession, didReceiveMessage message: [String: Any], replyHandler: @escaping ([String: Any]) -> Void) {
        guard let request = message["request"] as? String else { return }

        switch request {
        case "todaySummary":
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
                saveSetFromWatch(message)
                replyHandler(["success": true])
            }
        default:
            break
        }
    }

    // MARK: - Data Synchronization

    @MainActor
    func sendUserDataToWatch() {
        guard let session = session, session.activationState == .activated else { return }
        
        let summary = fetchTodaySummary()
        let exercises = fetchExercises()
        
        let payload: [String: Any] = [
            "todaySummary": summary,
            "exercises": exercises
        ]
        
        do {
            try session.updateApplicationContext(payload)
            print("WatchConnectivityManager: successfully updated application context on watch: \(payload)")
        } catch {
            print("WatchConnectivityManager: failed to update application context: \(error.localizedDescription)")
        }
    }

    private static let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    @MainActor
    private func fetchTodaySummary() -> [String: Any] {
        guard let context = modelContext else { return ["setCount": 0, "totalWeight": 0.0] }
        let today = WatchConnectivityManager.dayFormatter.string(from: Date())
        let fetch = FetchDescriptor<WorkoutSet>(predicate: #Predicate { $0.session?.dateString == today })
        let sets = (try? context.fetch(fetch)) ?? []
        let totalWeight = sets.reduce(0.0) { $0 + ($1.weight * Double($1.reps)) }
        return ["setCount": sets.count, "totalWeight": totalWeight]
    }

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

    @MainActor
    private func saveSetFromWatch(_ message: [String: Any]) {
        guard let context = modelContext,
              let exercise = message["exercise"] as? String,
              let weight = message["weight"] as? Double,
              let reps = message["reps"] as? Int,
              let rpe = message["rpe"] as? Double,
              let setType = message["setType"] as? String else {
            return
        }

        let timestamp = message["timestamp"] as? Date ?? Date()
        let today = WatchConnectivityManager.dayFormatter.string(from: timestamp)
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
                setType: setType,
                timestamp: timestamp
            )
            newSet.session = session
            context.insert(newSet)
            try context.save()
            print("WatchConnectivityManager: saved set logged from watch: \(exercise) \(weight)x\(reps)")
        } catch {
            print("WatchConnectivityManager: failed to save watch set: \(error.localizedDescription)")
        }
    }
}
