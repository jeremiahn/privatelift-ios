import Foundation
import SwiftData

@Model
final class WorkoutSet {
    var exercise: String // "SQUAT" | "BENCH" | "DEADLIFT"
    var weight: Double
    var reps: Int
    var rpe: Double // 1.0 - 10.0
    var setType: String // "warmup" | "working" | "drop"
    var timestamp: Date = Date()
    
    var session: WorkoutSession?

    init(exercise: String, weight: Double, reps: Int, rpe: Double, setType: String, timestamp: Date = Date()) {
        self.exercise = exercise
        self.weight = weight
        self.reps = reps
        self.rpe = rpe
        self.setType = setType
        self.timestamp = timestamp
    }
}
