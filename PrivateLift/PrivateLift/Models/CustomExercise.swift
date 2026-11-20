import Foundation
import SwiftData

@Model
final class CustomExercise {
    var id: UUID = UUID()
    var name: String = ""            // Unique key, e.g. "SQUAT", "BENCH", "DEADLIFT", "OHP"
    var displayName: String = ""     // User-friendly name, e.g., "Overhead Press"
    var oneRepMax: Double = 0.0       // 1RM value used for targets
    var colorHex: String = ""        // Custom card & label styling color (e.g. "#EF4444")
    var orderIndex: Int = 0         // To maintain sorting order in lists
    
    // Powerlifting validation for Wilks/DOTS calculations
    var isPowerlift: Bool = false       // Participate in Wilks/DOTS?
    var powerliftType: String? = nil  // "squat" | "bench" | "deadlift"

    // Optional overrides (nil = use the Settings default). Optional + defaulted keeps
    // this a lightweight SwiftData migration and CloudKit-compatible.
    var restSeconds: Double? = nil    // rest timer after a set of this exercise
    var barWeight: Double? = nil      // e.g. a 55 lb trap bar for deadlifts

    init(
        name: String,
        displayName: String,
        oneRepMax: Double,
        colorHex: String,
        orderIndex: Int,
        isPowerlift: Bool = false,
        powerliftType: String? = nil
    ) {
        self.id = UUID()
        self.name = name.uppercased()
        self.displayName = displayName
        self.oneRepMax = oneRepMax
        self.colorHex = colorHex
        self.orderIndex = orderIndex
        self.isPowerlift = isPowerlift
        self.powerliftType = powerliftType
    }
}

extension Array where Element == CustomExercise {
    /// First exercise per canonical key, order preserved ("Bench Press" and "BENCH" collapse).
    var uniqued: [CustomExercise] {
        var seen = Set<String>()
        return filter { seen.insert(LiftMath.exerciseKey($0.name)).inserted }
    }
}
