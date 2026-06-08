import Foundation
import SwiftData

@Model
final class RoutineExerciseTarget {
    var exercise: String = "" // "SQUAT" | "BENCH" | "DEADLIFT"
    var reps: Int = 0
    var setType: String = "" // "working" | "warmup"
    var pct: Double = 0.0 // E.g., 0.85 (85% of 1RM)
    
    var template: RoutineTemplate?

    init(exercise: String, reps: Int, setType: String, pct: Double) {
        self.exercise = exercise
        self.reps = reps
        self.setType = setType
        self.pct = pct
    }
}
