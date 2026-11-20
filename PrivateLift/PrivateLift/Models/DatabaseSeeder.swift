import Foundation
import SwiftData

@MainActor
struct DatabaseSeeder {
    static func seedDataIfNeeded(context: ModelContext) {
        let isScreenshotMode = CommandLine.arguments.contains("-seedScreenshots") ||
                               UserDefaults.standard.bool(forKey: "SeedScreenshots") ||
                               UserDefaults.standard.bool(forKey: "FASTLANE_SNAPSHOT")

        // 1. Seed Preferences if none exist
        do {
            let existingPrefs = try context.fetch(FetchDescriptor<UserPreferences>())
            if existingPrefs.isEmpty {
                let prefs = UserPreferences()
                if isScreenshotMode {
                    applyScreenshotProfile(prefs, context: context)
                }
                context.insert(prefs)
                try context.save()
                debugLog("Default user preferences seeded successfully (onboarded=\(prefs.isOnboarded)).")
            } else if isScreenshotMode {
                // Another code path can create the record first on a fresh install.
                for prefs in existingPrefs {
                    applyScreenshotProfile(prefs, context: context)
                }
                try context.save()
            }
        } catch {
            debugLog("Error checking/seeding user preferences: \(error)")
        }

        // 1.5 Screenshot demo history (only with -seedScreenshots, only on an empty store)
        if isScreenshotMode {
            seedScreenshotHistory(context: context)
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
                    debugLog("Seeded missing exercise: \(ex.name)")
                }
            }
            try context.save()
        } catch {
            debugLog("Error checking/seeding custom exercises: \(error)")
        }

        // 3. De-duplicate any existing exercises with the same name (safety net for
        //    CloudKit sync races that may have already inserted duplicates).
        deduplicateExercises(context: context)

        if isScreenshotMode {
            applyScreenshotMaxes(context: context)
        }
    }

    /// Screenshot profile: onboarded, with maxes and body weight that make the PR, Wilks
    /// and DOTS cards read like a real intermediate lifter. Only applied once per store.
    private static func applyScreenshotProfile(_ prefs: UserPreferences, context: ModelContext) {
        guard !prefs.isOnboarded || prefs.gender == "other" else { return }
        prefs.isOnboarded = true
        prefs.squatMax = 345
        prefs.benchMax = 245
        prefs.deadliftMax = 425
        prefs.bodyWeight = 198
        prefs.gender = "male"
    }

    /// The legacy web-data migration runs after the first seed and resets exercise maxes,
    /// so screenshot mode re-applies the demo maxes on every launch.
    private static func applyScreenshotMaxes(context: ModelContext) {
        for exercise in (try? context.fetch(FetchDescriptor<CustomExercise>())) ?? [] {
            switch exercise.powerliftType {
            case "squat": exercise.oneRepMax = 345
            case "bench": exercise.oneRepMax = 245
            case "deadlift": exercise.oneRepMax = 425
            default: break
            }
        }
        try? context.save()
    }

    /// Screenshot-only demo data: eight weeks of progressing sessions, an Overhead Press
    /// accessory with its own rest time, and today's workout in progress.
    private static func seedScreenshotHistory(context: ModelContext) {
        guard (try? context.fetchCount(FetchDescriptor<WorkoutSession>())) == 0 else { return }
        let calendar = Calendar.current
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        let round5 = { (v: Double) in (v / 5).rounded() * 5 }

        let ohpName = "OHP"
        if (try? context.fetchCount(FetchDescriptor<CustomExercise>(predicate: #Predicate { $0.name == ohpName }))) == 0 {
            let ohp = CustomExercise(name: ohpName, displayName: "Overhead Press", oneRepMax: 155, colorHex: "#8b5cf6", orderIndex: 3)
            ohp.restSeconds = 120
            context.insert(ohp)
        }

        func addSet(_ session: WorkoutSession, _ exercise: String, _ weight: Double, _ reps: Int, _ rpe: Double, _ type: String, _ at: Date) {
            let set = WorkoutSet(exercise: exercise, weight: weight, reps: reps, rpe: rpe, setType: type, timestamp: at)
            set.session = session
            context.insert(set)
        }

        // Top working weights (x5) climb ~12% across the block.
        let finals: [(name: String, top: Double)] = [("SQUAT", 300), ("BENCH", 215), ("DEADLIFT", 375), ("OHP", 125)]
        let daysAgo = [54, 52, 49, 47, 45, 42, 40, 38, 35, 33, 31, 28, 26, 24, 21, 19, 17, 14, 12, 10, 7, 5, 3, 1]
        let notes = ["Belt on for top sets.", "Bar speed felt great today.", "", "Short on sleep; kept RPE honest.", "", "New 5-rep PR on squat."]
        for (index, ago) in daysAgo.enumerated() {
            guard let day = calendar.date(byAdding: .day, value: -ago, to: Date()),
                  let start = calendar.date(bySettingHour: 18, minute: 0, second: 0, of: day) else { continue }
            let session = WorkoutSession(dateString: formatter.string(from: day), notes: notes[index % notes.count])
            context.insert(session)
            let progress = 0.88 + 0.12 * Double(54 - ago) / 51
            let lifts = index % 2 == 0 ? ["SQUAT", "BENCH", "OHP"] : ["DEADLIFT", "BENCH", "SQUAT"]
            var minute = 0.0
            for lift in lifts {
                guard let top = finals.first(where: { $0.name == lift })?.top else { continue }
                let work = round5(top * progress)
                let bar = 45.0
                for warm in [bar, round5(work * 0.6), round5(work * 0.8)] {
                    addSet(session, lift, warm, 5, 6, "warmup", start.addingTimeInterval(minute * 60)); minute += 2
                }
                for rpe in [7.5, 8.0, 8.5] {
                    addSet(session, lift, work, 5, rpe, "working", start.addingTimeInterval(minute * 60)); minute += 3
                }
            }
        }

        // Today: squat in progress, so the log, "Previous set" and weekly volume have content.
        let today = WorkoutSession(dateString: formatter.string(from: Date()), notes: "Squat day. Aiming for 3x5 at 295.")
        context.insert(today)
        let now = Date()
        let todaySets: [(minutesAgo: Double, weight: Double, type: String, rpe: Double)] = [
            (24, 135, "warmup", 6), (21, 185, "warmup", 6.5), (18, 245, "warmup", 7),
            (14, 295, "working", 7.5), (9, 295, "working", 8)
        ]
        for entry in todaySets {
            addSet(today, "SQUAT", entry.weight, 5, entry.rpe, entry.type, now.addingTimeInterval(-entry.minutesAgo * 60))
        }

        try? context.save()
        debugLog("Seeded screenshot history.")
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
            debugLog("De-duplicated CustomExercise records.")
        }
    }
}
