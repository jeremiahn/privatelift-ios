import Foundation
import HealthKit
import Combine
import SwiftData

class HealthKitService: ObservableObject {
    let healthStore = HKHealthStore()
    @Published var isAuthorized: Bool = false

    func requestAuthorization() async -> Bool {
        guard HKHealthStore.isHealthDataAvailable() else { return false }
        
        guard let bodyMassType = HKQuantityType.quantityType(forIdentifier: .bodyMass),
              let energyBurnedType = HKQuantityType.quantityType(forIdentifier: .activeEnergyBurned) else {
            return false
        }
        
        let writeTypes: Set<HKSampleType> = [
            HKObjectType.workoutType(),
            bodyMassType,
            energyBurnedType
        ]
        
        let readTypes: Set<HKObjectType> = []
        
        do {
            try await healthStore.requestAuthorization(toShare: writeTypes, read: readTypes)
            let status = healthStore.authorizationStatus(for: HKObjectType.workoutType())
            let authorized = (status == .sharingAuthorized)
            await MainActor.run {
                self.isAuthorized = authorized
            }
            return authorized
        } catch {
            debugLog("HealthKit Authorization Failed: \(error.localizedDescription)")
            return false
        }
    }

    static let shared = HealthKitService()

    /// Value copy of a logged set, so SwiftData models never cross into HealthKit tasks.
    struct SetSnapshot {
        let timestamp: Date
        let weight: Double
        let reps: Int
    }

    private static let sessionKey = "PersonalLiftSession"
    private var syncChain: Task<Void, Never>?

    /// Keeps exactly one Apple Health workout per logged session (day). Call after any
    /// set in that session is added or removed; an empty `sets` removes the workout.
    /// Calls run one after another so rapid logging can't produce duplicates.
    func syncSession(dateString: String, sets: [WorkoutSet], unit: String) {
        let snapshots = sets
            .filter { !$0.isDeleted } // a just-deleted set can linger in the relationship until the next save
            .map { SetSnapshot(timestamp: $0.timestamp, weight: $0.weight, reps: $0.reps) }
            .sorted { $0.timestamp < $1.timestamp }
        let previous = syncChain
        syncChain = Task {
            await previous?.value
            await replaceWorkout(dateString: dateString, sets: snapshots, unit: unit)
        }
    }

    /// One-time cleanup for data written by versions before 1.3.3, which saved one
    /// workout per set. Deletes every workout and energy sample this app wrote (HealthKit
    /// only lets an app delete its own samples) and writes one workout per session.
    func rebuildAllWorkouts(sessions: [WorkoutSession], unit: String) async -> Bool {
        guard HKHealthStore.isHealthDataAvailable(),
              let energyType = HKQuantityType.quantityType(forIdentifier: .activeEnergyBurned) else { return false }
        await syncChain?.value
        let ownData = HKQuery.predicateForObjects(from: HKSource.default())
        do {
            _ = try await healthStore.deleteObjects(of: HKObjectType.workoutType(), predicate: ownData)
            _ = try await healthStore.deleteObjects(of: energyType, predicate: ownData)
        } catch {
            debugLog("Apple Health rebuild: delete failed: \(error.localizedDescription)")
            return false
        }
        let snapshots = sessions.map { session in
            (session.dateString, (session.sets ?? [])
                .map { SetSnapshot(timestamp: $0.timestamp, weight: $0.weight, reps: $0.reps) }
                .sorted { $0.timestamp < $1.timestamp })
        }
        for (dateString, sets) in snapshots where !sets.isEmpty {
            await replaceWorkout(dateString: dateString, sets: sets, unit: unit, deleteExisting: false)
        }
        return true
    }

    private func replaceWorkout(dateString: String, sets: [SetSnapshot], unit: String, deleteExisting: Bool = true) async {
        guard HKHealthStore.isHealthDataAvailable(),
              let energyType = HKQuantityType.quantityType(forIdentifier: .activeEnergyBurned) else { return }

        if deleteExisting {
            let thisSession = HKQuery.predicateForObjects(withMetadataKey: Self.sessionKey, allowedValues: [dateString])
            do {
                _ = try await healthStore.deleteObjects(of: HKObjectType.workoutType(), predicate: thisSession)
                _ = try await healthStore.deleteObjects(of: energyType, predicate: thisSession)
            } catch {
                // Nothing matched is reported as success; a real failure means we would
                // duplicate the session, so stop here and let the next sync retry.
                debugLog("Apple Health: could not remove previous workout for \(dateString): \(error.localizedDescription)")
                return
            }
        }
        guard let interval = Self.workoutInterval(dateString: dateString, sets: sets) else { return }

        let kcal = sets.reduce(0) { $0 + LiftMath.estimatedKcal(weight: $1.weight, reps: $1.reps, unit: unit) }
        let configuration = HKWorkoutConfiguration()
        configuration.activityType = .traditionalStrengthTraining
        configuration.locationType = .indoor
        let builder = HKWorkoutBuilder(healthStore: healthStore, configuration: configuration, device: .local())
        let metadata: [String: Any] = [
            Self.sessionKey: dateString,
            HKMetadataKeyWorkoutBrandName: "Personal Lift",
            HKMetadataKeyIndoorWorkout: true,
            "SetCount": sets.count
        ]
        do {
            try await builder.beginCollection(at: interval.start)
            try await builder.addSamples([HKQuantitySample(
                type: energyType,
                quantity: HKQuantity(unit: .kilocalorie(), doubleValue: kcal),
                start: interval.start,
                end: interval.end,
                metadata: [Self.sessionKey: dateString]
            )])
            try await builder.addMetadata(metadata)
            try await builder.endCollection(at: interval.end)
            _ = try await builder.finishWorkout()
        } catch {
            debugLog("Error saving workout to Apple Health: \(error.localizedDescription)")
        }
    }

    /// First set to 90 s after the last set. Sets whose timestamps aren't on the session's
    /// day (e.g. restored from a backup, which stamps them with the import time) get a
    /// synthetic window at noon instead, 3 minutes per set.
    private static func workoutInterval(dateString: String, sets: [SetSnapshot]) -> DateInterval? {
        guard let first = sets.first, let last = sets.last else { return nil }
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        guard let dayStart = formatter.date(from: dateString) else { return nil }
        let window = DateInterval(start: dayStart, duration: 36 * 3600) // allows sessions past midnight
        if window.contains(first.timestamp) && window.contains(last.timestamp) {
            return DateInterval(start: first.timestamp, end: last.timestamp.addingTimeInterval(90))
        }
        let noon = dayStart.addingTimeInterval(12 * 3600)
        return DateInterval(start: noon, duration: Double(sets.count) * 180)
    }

    func saveWeight(weightVal: Double, unit: String) async -> Bool {
        guard HKHealthStore.isHealthDataAvailable(),
              let weightType = HKQuantityType.quantityType(forIdentifier: .bodyMass) else {
            return false
        }
        
        let hkUnit = unit == "lbs" ? HKUnit.pound() : HKUnit.gramUnit(with: .kilo)
        let quantity = HKQuantity(unit: hkUnit, doubleValue: weightVal)
        let weightSample = HKQuantitySample(type: weightType, quantity: quantity, start: Date(), end: Date())
        
        do {
            try await healthStore.save(weightSample)
            return true
        } catch {
            debugLog("Failed to save weight sample to Apple Health: \(error.localizedDescription)")
            return false
        }
    }
}
