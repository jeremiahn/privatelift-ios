import Foundation
import SwiftData

@MainActor
struct DatabaseSeeder {
    static func seedDataIfNeeded(context: ModelContext) {
        // 1. Seed Preferences if none exist
        let prefFetchDescriptor = FetchDescriptor<UserPreferences>()
        do {
            let existingPrefs = try context.fetch(prefFetchDescriptor)
            if existingPrefs.isEmpty {
                let defaultPrefs = UserPreferences()
                context.insert(defaultPrefs)
                print("Default user preferences seeded successfully.")
            }
        } catch {
            print("Error checking/seeding user preferences: \(error)")
        }
        
        // 2. Seed Routine Templates if none exist
        let templateFetchDescriptor = FetchDescriptor<RoutineTemplate>()
        do {
            let existingTemplates = try context.fetch(templateFetchDescriptor)
            if existingTemplates.isEmpty {
                // Template 1: Powerlifting Big Three
                let t1 = RoutineTemplate(
                    name: "Powerlifting Big Three",
                    templateDescription: "Squat, Bench, and Deadlift target weights."
                )
                context.insert(t1)
                let e1 = RoutineExerciseTarget(exercise: "SQUAT", reps: 5, setType: "working", pct: 0.85)
                let e2 = RoutineExerciseTarget(exercise: "BENCH", reps: 5, setType: "working", pct: 0.85)
                let e3 = RoutineExerciseTarget(exercise: "DEADLIFT", reps: 5, setType: "working", pct: 0.85)
                e1.template = t1
                e2.template = t1
                e3.template = t1
                context.insert(e1)
                context.insert(e2)
                context.insert(e3)

                // Template 2: Squat Focus (3x5)
                let t2 = RoutineTemplate(
                    name: "Squat Focus (3x5)",
                    templateDescription: "Triple working sets for leg development."
                )
                context.insert(t2)
                let e4 = RoutineExerciseTarget(exercise: "SQUAT", reps: 5, setType: "working", pct: 0.85)
                let e5 = RoutineExerciseTarget(exercise: "SQUAT", reps: 5, setType: "working", pct: 0.85)
                let e6 = RoutineExerciseTarget(exercise: "SQUAT", reps: 5, setType: "working", pct: 0.85)
                e4.template = t2
                e5.template = t2
                e6.template = t2
                context.insert(e4)
                context.insert(e5)
                context.insert(e6)

                // Template 3: Bench Press Volume (3x5)
                let t3 = RoutineTemplate(
                    name: "Bench Press Volume (3x5)",
                    templateDescription: "Triple working sets for upper body pushing power."
                )
                context.insert(t3)
                let e7 = RoutineExerciseTarget(exercise: "BENCH", reps: 5, setType: "working", pct: 0.85)
                let e8 = RoutineExerciseTarget(exercise: "BENCH", reps: 5, setType: "working", pct: 0.85)
                let e9 = RoutineExerciseTarget(exercise: "BENCH", reps: 5, setType: "working", pct: 0.85)
                e7.template = t3
                e8.template = t3
                e9.template = t3
                context.insert(e7)
                context.insert(e8)
                context.insert(e9)

                try context.save()
                print("Default routine templates seeded successfully.")
            }
        } catch {
            print("Error checking/seeding routine templates: \(error)")
        }
    }
}
