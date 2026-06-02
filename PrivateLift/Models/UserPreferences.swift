import Foundation
import SwiftData

@Model
final class UserPreferences {
    var squatMax: Double = 315.0
    var benchMax: Double = 225.0
    var deadliftMax: Double = 405.0
    var bodyWeight: Double = 180.0
    var gender: String = "other" // "male" | "female" | "non_binary" | "other"
    var formula: String = "epley" // "epley" | "brzycki"
    var weightUnit: String = "lbs" // "lbs" | "kg"
    var showRestTimer: Bool = true
    var appleHealthEnabled: Bool = false
    var iCloudSyncEnabled: Bool = false
    var hapticsEnabled: Bool = true
    var pushNotificationsEnabled: Bool = true
    var defaultRestDuration: Double = 180.0 // Default rest in seconds (e.g. 180 = 3 mins)
    var isOnboarded: Bool = false
    var hasMigratedWebData: Bool = false
    var lastIntensity: Int = 85
    var theme: String = "system" // "system" | "light" | "dark" | "night"

    init(
        squatMax: Double = 315.0,
        benchMax: Double = 225.0,
        deadliftMax: Double = 405.0,
        bodyWeight: Double = 180.0,
        gender: String = "other",
        formula: String = "epley",
        weightUnit: String = "lbs",
        showRestTimer: Bool = true,
        appleHealthEnabled: Bool = false,
        iCloudSyncEnabled: Bool = false,
        hapticsEnabled: Bool = true,
        pushNotificationsEnabled: Bool = true,
        defaultRestDuration: Double = 180.0,
        isOnboarded: Bool = false,
        hasMigratedWebData: Bool = false,
        lastIntensity: Int = 85,
        theme: String = "system"
    ) {
        self.squatMax = squatMax
        self.benchMax = benchMax
        self.deadliftMax = deadliftMax
        self.bodyWeight = bodyWeight
        self.gender = gender
        self.formula = formula
        self.weightUnit = weightUnit
        self.showRestTimer = showRestTimer
        self.appleHealthEnabled = appleHealthEnabled
        self.iCloudSyncEnabled = iCloudSyncEnabled
        self.hapticsEnabled = hapticsEnabled
        self.pushNotificationsEnabled = pushNotificationsEnabled
        self.defaultRestDuration = defaultRestDuration
        self.isOnboarded = isOnboarded
        self.hasMigratedWebData = hasMigratedWebData
        self.lastIntensity = lastIntensity
        self.theme = theme
    }
}
