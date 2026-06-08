import Foundation
import SwiftData

@MainActor
struct DatabaseSeeder {
    static func seedDataIfNeeded(context: ModelContext) {
        // 1. Seed Preferences if none exist
        do {
            let existingPrefs = try context.fetch(FetchDescriptor<UserPreferences>())
            if existingPrefs.isEmpty {
                context.insert(UserPreferences())
                try context.save()
                print("Default user preferences seeded successfully.")
            }
        } catch {
            print("Error checking/seeding user preferences: \(error)")
        }

        // 2. Seed the three default powerlifting exercises — only if each is missing by name.
        //    This is intentionally per-exercise (not a bulk "if empty" check) so that
        //    CloudKit-synced duplicates or partial seeds never re-insert an existing record.
        let defaultExercises: [(name: String, displayName: String, colorHex: String, index: Int, type: String)] = [
            ("SQUAT",     "Squat",       "#ef4444", 0, "squat"),
            ("BENCH",     "Bench Press", "#3b82f6", 1, "bench"),
            ("DEADLIFT",  "Deadlift",    "#10b981", 2, "deadlift"),
        ]
        do {
            for ex in defaultExercises {
                let name = ex.name
                let existing = try context.fetch(
                    FetchDescriptor<CustomExercise>(predicate: #Predicate { $0.name == name })
                )
                if existing.isEmpty {
                    // Seed with a neutral 1RM — onboarding will overwrite it
                    let prefs = (try? context.fetch(FetchDescriptor<UserPreferences>()))?.first
                    let oneRM: Double
                    switch ex.type {
                    case "squat":    oneRM = prefs?.squatMax    ?? 315.0
                    case "bench":    oneRM = prefs?.benchMax    ?? 225.0
                    case "deadlift": oneRM = prefs?.deadliftMax ?? 405.0
                    default:         oneRM = 0.0
                    }
                    context.insert(CustomExercise(
                        name: ex.name,
                        displayName: ex.displayName,
                        oneRepMax: oneRM,
                        colorHex: ex.colorHex,
                        orderIndex: ex.index,
                        isPowerlift: true,
                        powerliftType: ex.type
                    ))
                    print("Seeded missing exercise: \(ex.name)")
                }
            }
            try context.save()
        } catch {
            print("Error checking/seeding custom exercises: \(error)")
        }

        // 3. Seed Routine Templates if none exist
        do {
            let existingTemplates = try context.fetch(FetchDescriptor<RoutineTemplate>())
            if existingTemplates.isEmpty {
                // Template 1: Powerlifting Big Three
                let t1 = RoutineTemplate(name: "Powerlifting Big Three", templateDescription: "Squat, Bench, and Deadlift target weights.")
                context.insert(t1)
                for exName in ["SQUAT", "BENCH", "DEADLIFT"] {
                    let e = RoutineExerciseTarget(exercise: exName, reps: 5, setType: "working", pct: 0.85)
                    e.template = t1
                    context.insert(e)
                }

                // Template 2: Squat Focus (3x5)
                let t2 = RoutineTemplate(name: "Squat Focus (3x5)", templateDescription: "Triple working sets for leg development.")
                context.insert(t2)
                for _ in 0..<3 {
                    let e = RoutineExerciseTarget(exercise: "SQUAT", reps: 5, setType: "working", pct: 0.85)
                    e.template = t2
                    context.insert(e)
                }

                // Template 3: Bench Press Volume (3x5)
                let t3 = RoutineTemplate(name: "Bench Press Volume (3x5)", templateDescription: "Triple working sets for upper body pushing power.")
                context.insert(t3)
                for _ in 0..<3 {
                    let e = RoutineExerciseTarget(exercise: "BENCH", reps: 5, setType: "working", pct: 0.85)
                    e.template = t3
                    context.insert(e)
                }

                try context.save()
                print("Default routine templates seeded successfully.")
            }
        } catch {
            print("Error checking/seeding routine templates: \(error)")
        }

        // 4. De-duplicate any existing exercises with the same name (safety net for
        //    CloudKit sync races that may have already inserted duplicates).
        deduplicateExercises(context: context)
    }

    /// Removes any duplicate CustomExercise records that share the same name,
    /// keeping the one with the lowest orderIndex (i.e. the original seed).
    private static func deduplicateExercises(context: ModelContext) {
        guard let allExercises = try? context.fetch(FetchDescriptor<CustomExercise>()) else { return }
        var seen: [String: CustomExercise] = [:]
        var didDelete = false
        
        // Sort exercises so that active powerlifts or lower order indexes are processed first (retaining them)
        let sortedExercises = allExercises.sorted { (a, b) in
            if a.isPowerlift != b.isPowerlift {
                return a.isPowerlift && !b.isPowerlift
            }
            return a.orderIndex < b.orderIndex
        }
        
        for exercise in sortedExercises {
            let key: String
            let normalizedName = exercise.name.uppercased().replacingOccurrences(of: " ", with: "")
            let normalizedDisplay = exercise.displayName.uppercased().replacingOccurrences(of: " ", with: "")
            
            if normalizedName == "BENCH" || normalizedName == "BENCHPRESS" || normalizedDisplay == "BENCHPRESS" || normalizedDisplay == "BENCH" {
                key = "BENCH"
            } else if normalizedName == "SQUAT" || normalizedDisplay == "SQUAT" {
                key = "SQUAT"
            } else if normalizedName == "DEADLIFT" || normalizedDisplay == "DEADLIFT" {
                key = "DEADLIFT"
            } else {
                key = normalizedName
            }
            
            if let existing = seen[key] {
                // Keep the first sorted one, delete the duplicate
                context.delete(exercise)
                _ = existing
                didDelete = true
            } else {
                seen[key] = exercise
            }
        }
        if didDelete {
            try? context.save()
            print("De-duplicated CustomExercise records.")
        }
    }
}
