// Shared data models (additional)
package com.jeremiah.privatelift.shared.model

import kotlinx.serialization.Serializable

@Serializable
data class UserPreferences(
    var squatMax: Double = 315.0,
    var benchMax: Double = 225.0,
    var deadliftMax: Double = 405.0,
    var bodyWeight: Double = 180.0,
    var gender: String = "other", // "male" | "female" | "non_binary" | "other"
    var formula: String = "epley", // "epley" | "brzycki"
    var weightUnit: String = "lbs", // "lbs" | "kg"
    var showRestTimer: Boolean = true,
    var appleHealthEnabled: Boolean = false,
    var iCloudSyncEnabled: Boolean = false,
    var hapticsEnabled: Boolean = true,
    var pushNotificationsEnabled: Boolean = true,
    var defaultRestDuration: Double = 180.0, // in seconds
    var isOnboarded: Boolean = false,
    var hasMigratedWebData: Boolean = false,
    var lastIntensity: Int = 85,
    var theme: String = "system", // "system" | "light" | "dark" | "night"
    var useGridMode: Boolean = false,
    var timeZoneIdentifier: String = "UTC",
    var startOfWeekDay: Int = 1 // 1 = Sunday, 2 = Monday
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
    val id: String, // String UUID
    val name: String, // E.g., "SQUAT", "BENCH"
    val displayName: String,
    var oneRepMax: Double,
    val colorHex: String,
    val orderIndex: Int,
    val isPowerlift: Boolean = false,
    val powerliftType: String? = null
)

