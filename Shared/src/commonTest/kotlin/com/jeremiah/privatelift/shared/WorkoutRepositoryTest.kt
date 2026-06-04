package com.jeremiah.privatelift.shared

import com.jeremiah.privatelift.shared.model.WorkoutSession
import com.jeremiah.privatelift.shared.repository.WorkoutRepository
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.flowOf
import kotlinx.coroutines.test.runTest
import kotlin.test.Test
import kotlin.test.assertEquals

class WorkoutRepositoryTest {

    private val mockRepository = object : WorkoutRepository {
        private val workouts = mutableListOf<WorkoutSession>()
        override fun getWorkouts(): Flow<List<WorkoutSession>> = flowOf(workouts)
        override suspend fun saveWorkout(workout: WorkoutSession) {
            workouts.add(workout)
        }
    }

    @Test
    fun testSaveAndGetWorkouts() = runTest {
        val workout = WorkoutSession(dateString = "2024-06-04", notes = "Test workout")
        mockRepository.saveWorkout(workout)
        
        mockRepository.getWorkouts().collect { savedWorkouts ->
            assertEquals(1, savedWorkouts.size)
            assertEquals("Test workout", savedWorkouts[0].notes)
        }
    }
}
