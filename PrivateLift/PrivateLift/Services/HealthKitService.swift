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

        // Calorie estimation: ~0.1 kcal per rep per 45kg (100 lbs) lifted, floored at 3 kcal
        let weightKg = weight * 0.453592
        let estimatedKcal = max(3.0, (weightKg / 45.0) * Double(reps) * 0.1)
        let activeEnergy = HKQuantity(unit: .kilocalorie(), doubleValue: estimatedKcal)

        // Use 90 seconds as a proxy duration for a single set (warmup gets 60 s)
        let setDuration: TimeInterval = setType == "warmup" ? 60 : 90

        let configuration = HKWorkoutConfiguration()
        configuration.activityType = .functionalStrengthTraining
        configuration.locationType = .indoor

        let builder = HKWorkoutBuilder(healthStore: healthStore, configuration: configuration, device: .local())

        do {
            try await builder.beginCollection(at: date)

            if let activeEnergyType = HKQuantityType.quantityType(forIdentifier: .activeEnergyBurned) {
                let energySample = HKQuantitySample(
                    type: activeEnergyType,
                    quantity: activeEnergy,
                    start: date,
                    end: date.addingTimeInterval(setDuration)
                )
                try await builder.addSamples([energySample])
            }

            let metadata: [String: Any] = [
                HKMetadataKeyWorkoutBrandName: "PersonalLift",
                HKMetadataKeyIndoorWorkout: true,
                "Exercise": exercise,
                "Weight": "\(weight)",
                "Reps": "\(reps)",
                "SetType": setType,
                "RPE": rpe.map { String(format: "%.1f", $0) } ?? "N/A"
            ]
            try await builder.addMetadata(metadata)

            try await builder.endCollection(at: date.addingTimeInterval(setDuration))
            _ = try await builder.finishWorkout()
            return true
        } catch {
            print("Error saving workout to Apple Health: \(error.localizedDescription)")
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
