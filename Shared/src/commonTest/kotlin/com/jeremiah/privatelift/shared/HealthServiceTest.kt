package com.jeremiah.privatelift.shared

import com.jeremiah.privatelift.shared.service.HealthService
import kotlinx.coroutines.test.runTest
import kotlin.test.Test
import kotlin.test.assertEquals

class HealthServiceTest {

    private val mockHealthService = object : HealthService {
        override suspend fun getStepCount(): Long = 5000
        override suspend fun getAverageHeartRate(): Float = 75.0f
        override suspend fun getActivityTypes(): List<String> = listOf("Walking", "Running")
    }

    @Test
    fun testHealthStats() = runTest {
        assertEquals(5000, mockHealthService.getStepCount())
        assertEquals(75.0f, mockHealthService.getAverageHeartRate())
        assertEquals(2, mockHealthService.getActivityTypes().size)
    }
}
