package com.jeremiah.privatelift.shared.repository

import com.jeremiah.privatelift.shared.model.WorkoutSession
import kotlinx.coroutines.flow.Flow

interface WorkoutRepository {
    fun getWorkouts(): Flow<List<WorkoutSession>>
    suspend fun saveWorkout(workout: WorkoutSession)
}
