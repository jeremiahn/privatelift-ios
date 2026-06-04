// Shared data models (additional)
package com.jeremiah.privatelift.shared.model

import kotlinx.serialization.Serializable

@Serializable
data class UserPreferences(
    val iCloudSyncEnabled: Boolean = false,
    val notificationsEnabled: Boolean = true
)

@Serializable
data class RoutineExerciseTarget(
    val exerciseName: String,
    val targetReps: Int,
    val targetWeightKg: Double? = null
)

@Serializable
data class RoutineTemplate(
    val id: String,
    val name: String,
    val exercises: List<RoutineExerciseTarget>
)

@Serializable
data class CustomExercise(
    val name: String,
    val description: String = "",
    val defaultWeightKg: Double? = null
)
