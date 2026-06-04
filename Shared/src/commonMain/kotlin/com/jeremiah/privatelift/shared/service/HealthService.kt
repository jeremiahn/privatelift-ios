package com.jeremiah.privatelift.shared.service

interface HealthService {
    suspend fun getStepCount(): Long
    suspend fun getAverageHeartRate(): Float
    suspend fun getActivityTypes(): List<String>
}
