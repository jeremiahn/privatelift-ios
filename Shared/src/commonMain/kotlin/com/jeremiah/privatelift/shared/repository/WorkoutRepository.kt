package com.jeremiah.privatelift.shared.repository

import com.jeremiah.privatelift.shared.model.WorkoutSession
import com.jeremiah.privatelift.shared.model.UserPreferences
import com.jeremiah.privatelift.shared.model.CustomExercise
import kotlinx.coroutines.flow.Flow

interface WorkoutRepository {
    fun getWorkouts(): Flow<List<WorkoutSession>>
    suspend fun saveWorkout(workout: WorkoutSession)
    suspend fun deleteWorkout(dateString: String)
    
    fun getUserPreferences(): Flow<UserPreferences>
    suspend fun saveUserPreferences(prefs: UserPreferences)
    
    fun getCustomExercises(): Flow<List<CustomExercise>>
    suspend fun saveCustomExercise(exercise: CustomExercise)
    suspend fun saveCustomExercises(exercises: List<CustomExercise>)
    suspend fun deleteCustomExercise(id: String)
}

