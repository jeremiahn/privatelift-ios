package com.jeremiah.privatelift.shared

import com.jeremiah.privatelift.shared.model.CustomExercise
import com.jeremiah.privatelift.shared.model.UserPreferences
import com.jeremiah.privatelift.shared.model.WorkoutSession
import com.jeremiah.privatelift.shared.repository.WorkoutRepository
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.flow.flowOf
import kotlinx.coroutines.test.runTest
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertTrue

class WorkoutRepositoryTest {

    private val mockRepository = object : WorkoutRepository {
        private val workouts = mutableListOf<WorkoutSession>()
        private val prefsState = MutableStateFlow(UserPreferences())
        private val exercises = mutableListOf<CustomExercise>()

        override fun getWorkouts(): Flow<List<WorkoutSession>> = flowOf(workouts)
        
        override suspend fun saveWorkout(workout: WorkoutSession) {
            workouts.removeAll { it.dateString == workout.dateString }
            workouts.add(workout)
        }

        override suspend fun deleteWorkout(dateString: String) {
            workouts.removeAll { it.dateString == dateString }
        }

        override fun getUserPreferences(): Flow<UserPreferences> = prefsState

        override suspend fun saveUserPreferences(prefs: UserPreferences) {
            prefsState.value = prefs
        }

        override fun getCustomExercises(): Flow<List<CustomExercise>> = flowOf(exercises)

        override suspend fun saveCustomExercise(exercise: CustomExercise) {
            exercises.removeAll { it.id == exercise.id }
            exercises.add(exercise)
        }

        override suspend fun saveCustomExercises(exercisesList: List<CustomExercise>) {
            exercisesList.forEach { saveCustomExercise(it) }
        }

        override suspend fun deleteCustomExercise(id: String) {
            exercises.removeAll { it.id == id }
        }
    }

    @Test
    fun testSaveAndGetWorkouts() = runTest {
        val workout = WorkoutSession(dateString = "2024-06-04", notes = "Test workout")
        mockRepository.saveWorkout(workout)
        
        val savedWorkouts = mockRepository.getWorkouts().first()
        assertEquals(1, savedWorkouts.size)
        assertEquals("Test workout", savedWorkouts[0].notes)
    }

    @Test
    fun testDeleteWorkout() = runTest {
        val workout1 = WorkoutSession(dateString = "2024-06-04", notes = "Workout 1")
        val workout2 = WorkoutSession(dateString = "2024-06-05", notes = "Workout 2")
        mockRepository.saveWorkout(workout1)
        mockRepository.saveWorkout(workout2)

        mockRepository.deleteWorkout("2024-06-04")

        val savedWorkouts = mockRepository.getWorkouts().first()
        assertEquals(1, savedWorkouts.size)
        assertEquals("2024-06-05", savedWorkouts[0].dateString)
    }

    @Test
    fun testUserPreferences() = runTest {
        val newPrefs = UserPreferences(squatMax = 350.0, benchMax = 250.0, weightUnit = "kg")
        mockRepository.saveUserPreferences(newPrefs)

        val savedPrefs = mockRepository.getUserPreferences().first()
        assertEquals(350.0, savedPrefs.squatMax)
        assertEquals(250.0, savedPrefs.benchMax)
        assertEquals("kg", savedPrefs.weightUnit)
    }

    @Test
    fun testCustomExercises() = runTest {
        val exercise = CustomExercise(
            id = "test-id-1",
            name = "OHP",
            displayName = "Overhead Press",
            oneRepMax = 135.0,
            colorHex = "#FF0000",
            orderIndex = 3
        )
        mockRepository.saveCustomExercise(exercise)

        val savedExercises = mockRepository.getCustomExercises().first()
        assertEquals(1, savedExercises.size)
        assertEquals("OHP", savedExercises[0].name)
        assertEquals(135.0, savedExercises[0].oneRepMax)

        mockRepository.deleteCustomExercise("test-id-1")

        val finalExercises = mockRepository.getCustomExercises().first()
        assertTrue(finalExercises.isEmpty())
    }
}
