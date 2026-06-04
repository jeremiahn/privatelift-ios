import Foundation
import SwiftData

@Model
final class RoutineTemplate {
    var name: String
    var templateDescription: String
    
    @Relationship(deleteRule: .cascade, inverse: \RoutineExerciseTarget.template)
    var exercises: [RoutineExerciseTarget] = []

    init(name: String, templateDescription: String = "") {
        self.name = name
        self.templateDescription = templateDescription
    }
}
