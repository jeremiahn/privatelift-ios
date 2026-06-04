// Shared Kotlin models (commonMain)
package com.jeremiah.privatelift.shared.model

import kotlinx.serialization.Serializable

@Serializable
data class WorkoutSession(
    val dateString: String, // YYYY-MM-DD
    val notes: String = "",
    val sets: List<WorkoutSet> = emptyList()
) {
    val date: java.time.LocalDate
        get() = java.time.LocalDate.parse(dateString)
}

@Serializable
data class WorkoutSet(
    val reps: Int,
    val weightKg: Double,
    val exerciseName: String
)
