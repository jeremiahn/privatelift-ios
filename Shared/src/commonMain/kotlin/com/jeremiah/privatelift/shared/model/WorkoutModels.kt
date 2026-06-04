// Shared Kotlin models (commonMain)
package com.jeremiah.privatelift.shared.model

import kotlinx.serialization.Serializable

@Serializable
data class WorkoutSession(
    val dateString: String, // YYYY-MM-DD
    var notes: String = "",
    var sets: List<WorkoutSet> = emptyList()
)

@Serializable
data class WorkoutSet(
    val exercise: String, // "SQUAT" | "BENCH" | "DEADLIFT"
    val weight: Double,
    val reps: Int,
    val rpe: Double, // 1.0 - 10.0
    val setType: String, // "warmup" | "working" | "failed" | "drop"
    val timestamp: Long // Epoch milliseconds
)

