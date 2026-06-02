import Foundation
import HealthKit
import Combine

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
        
        let readTypes: Set<HKObjectType> = [
            bodyMassType
        ]
        
        do {
            try await healthStore.requestAuthorization(toShare: writeTypes, read: readTypes)
            let status = healthStore.authorizationStatus(for: HKObjectType.workoutType())
            let authorized = (status == .sharingAuthorized)
            await MainActor.run {
                self.isAuthorized = authorized
            }
            return authorized
        } catch {
            print("HealthKit Authorization Failed: \(error.localizedDescription)")
            return false
        }
    }

    func saveWorkout(date: Date, exercise: String, weight: Double, reps: Int, setType: String, rpe: Double?) async -> Bool {
        guard HKHealthStore.isHealthDataAvailable() else { return false }
        
        // Calories estimation: Warmups burn ~3 kcal, working sets ~8 kcal
        let calories = setType == "warmup" ? 3.0 : 8.0
        let activeEnergy = HKQuantity(unit: .kilocalorie(), doubleValue: calories)
        
        let workout = HKWorkout(
            activityType: .functionalStrengthTraining,
            start: date,
            end: date.addingTimeInterval(3 * 60), // standard 3-minute block per set
            duration: 3 * 60,
            totalEnergyBurned: activeEnergy,
            totalDistance: nil,
            metadata: [
                HKMetadataKeyWorkoutBrandName: "PrivateLift",
                HKMetadataKeyIndoorWorkout: true,
                "Exercise": exercise,
                "Weight": "\(weight)",
                "Reps": "\(reps)",
                "SetType": setType,
                "RPE": rpe != nil ? "\(rpe!)" : "N/A"
            ]
        )
        
        do {
            try await healthStore.save(workout)
            return true
        } catch {
            print("Failed to save workout to Apple Health: \(error.localizedDescription)")
            return false
        }
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
            print("Failed to save weight sample to Apple Health: \(error.localizedDescription)")
            return false
        }
    }
}
