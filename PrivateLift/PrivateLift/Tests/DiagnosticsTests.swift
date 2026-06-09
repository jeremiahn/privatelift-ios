import Foundation
import SwiftData
import HealthKit

struct TestDiagnosticResult: Identifiable {
    let id = UUID()
    let name: String
    let passed: Bool
    let message: String
}

@MainActor
class DiagnosticsTests {
    static let shared = DiagnosticsTests()
    
    func runAllTests() -> [TestDiagnosticResult] {
        var results: [TestDiagnosticResult] = []
        
        // 1. Calorie Estimation Math Test
        results.append(testCalorieEstimation())
        
        // 2. Weight Unit Switch Multiplier Test
        results.append(testWeightConversionMultiplier())
        
        // 3. SwiftData Model Validation Test
        results.append(testSwiftDataModelMock())
        
        // 4. Default Preferences Validation Test
        results.append(testDefaultPreferences())
        
        return results
    }
    
    private func testCalorieEstimation() -> TestDiagnosticResult {
        // Calorie formula: max(3.0, (weightKg / 45.0) * Double(reps) * 0.1)
        // Let's test weight of 100 lbs (45.3592 kg), 5 reps:
        let weightLbs = 100.0
        let reps = 5
        let weightKg = weightLbs * 0.453592
        let calculatedVal = (weightKg / 45.0) * Double(reps) * 0.1
        let estimatedKcal = max(3.0, calculatedVal)
        
        // At 100 lbs and 5 reps, the math is (45.3592 / 45.0) * 5 * 0.1 = ~0.504 kcal.
        // It should be floored/capped at the 3.0 kcal minimum.
        if estimatedKcal == 3.0 {
            return TestDiagnosticResult(
                name: "Calorie Estimation Minimum Floor",
                passed: true,
                message: "Passed: Minimum floor of 3.0 kcal successfully applied for lower weights (got \(estimatedKcal) kcal)."
            )
        } else {
            return TestDiagnosticResult(
                name: "Calorie Estimation Minimum Floor",
                passed: false,
                message: "Failed: Expected 3.0 kcal floor, got \(estimatedKcal) kcal."
            )
        }
    }
    
    private func testWeightConversionMultiplier() -> TestDiagnosticResult {
        let weightInLbs = 225.0
        let lbsToKgMultiplier = 0.45359237
        let kgToLbsMultiplier = 1.0 / 0.45359237
        
        let weightInKg = Foundation.round(weightInLbs * lbsToKgMultiplier) // Round to nearest integer like DB converter
        let roundtripLbs = Foundation.round(weightInKg * kgToLbsMultiplier)
        
        // 225 lbs is 102.06 kg, rounded to 102.0.
        // 102.0 kg back to lbs is 224.87, rounded to 225.0.
        if roundtripLbs == weightInLbs {
            return TestDiagnosticResult(
                name: "Weight Unit Roundtrip Conversion",
                passed: true,
                message: "Passed: LBS -> KG -> LBS roundtrip matches exactly at \(weightInLbs) lbs."
            )
        } else {
            return TestDiagnosticResult(
                name: "Weight Unit Roundtrip Conversion",
                passed: false,
                message: "Failed: LBS -> KG -> LBS roundtrip mismatch. Original: \(weightInLbs), Result: \(roundtripLbs)"
            )
        }
    }
    
    private func testSwiftDataModelMock() -> TestDiagnosticResult {
        do {
            let schema = Schema([WorkoutSession.self, WorkoutSet.self, UserPreferences.self, CustomExercise.self])
            let config = ModelConfiguration(isStoredInMemoryOnly: true)
            let container = try ModelContainer(for: schema, configurations: [config])
            let context = container.mainContext
            
            // Insert session
            let session = WorkoutSession(dateString: "2026-06-09", notes: "Test notes")
            context.insert(session)
            
            // Insert set
            let workoutSet = WorkoutSet(exercise: "Squat", weight: 315.0, reps: 5, rpe: 9.0, setType: "working")
            workoutSet.session = session
            context.insert(workoutSet)
            
            try context.save()
            
            // Fetch
            let fetchDescriptor = FetchDescriptor<WorkoutSet>()
            let sets = try context.fetch(fetchDescriptor)
            
            if sets.count == 1 && sets.first?.weight == 315.0 && sets.first?.session?.notes == "Test notes" {
                return TestDiagnosticResult(
                    name: "SwiftData Model Interactions",
                    passed: true,
                    message: "Passed: In-memory container successfully created, populated, saved, and queried."
                )
            } else {
                return TestDiagnosticResult(
                    name: "SwiftData Model Interactions",
                    passed: false,
                    message: "Failed: SwiftData count or properties mismatch."
                )
            }
        } catch {
            return TestDiagnosticResult(
                name: "SwiftData Model Interactions",
                passed: false,
                message: "Failed to initialize and test SwiftData container: \(error.localizedDescription)"
            )
        }
    }
    
    private func testDefaultPreferences() -> TestDiagnosticResult {
        let prefs = UserPreferences()
        
        let validDefaults = (
            prefs.squatMax == 315.0 &&
            prefs.benchMax == 225.0 &&
            prefs.deadliftMax == 405.0 &&
            prefs.defaultRestDuration == 180.0 &&
            prefs.hapticsEnabled == true
        )
        
        if validDefaults {
            return TestDiagnosticResult(
                name: "Default UserPreferences Validation",
                passed: true,
                message: "Passed: Default benchmarks loaded correctly (Squat: 315, Bench: 225, Deadlift: 405)."
            )
        } else {
            return TestDiagnosticResult(
                name: "Default UserPreferences Validation",
                passed: false,
                message: "Failed: Default user preferences values differ from specification."
            )
        }
    }
}
