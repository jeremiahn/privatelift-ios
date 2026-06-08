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
