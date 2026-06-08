import Foundation
import SwiftData

@Model
final class WorkoutSession {
    var dateString: String = "" // Format: YYYY-MM-DD
    var notes: String = ""
    
    @Relationship(deleteRule: .cascade, inverse: \WorkoutSet.session)
    var sets: [WorkoutSet]? = []

    init(dateString: String, notes: String = "") {
        self.dateString = dateString
        self.notes = notes
        self.sets = []
    }
    
    var date: Date {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.date(from: dateString) ?? Date()
    }
}
