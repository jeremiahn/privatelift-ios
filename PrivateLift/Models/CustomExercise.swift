import Foundation
import SwiftData

@Model
final class CustomExercise {
    @Attribute(.unique) var id: UUID
    var name: String            // Unique key, e.g. "SQUAT", "BENCH", "DEADLIFT", "OHP"
    var displayName: String     // User-friendly name, e.g., "Overhead Press"
    var oneRepMax: Double       // 1RM value used for targets
    var colorHex: String        // Custom card & label styling color (e.g. "#EF4444")
    var orderIndex: Int         // To maintain sorting order in lists
    
    // Powerlifting validation for Wilks/DOTS calculations
    var isPowerlift: Bool       // Participate in Wilks/DOTS?
    var powerliftType: String?  // "squat" | "bench" | "deadlift"

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
