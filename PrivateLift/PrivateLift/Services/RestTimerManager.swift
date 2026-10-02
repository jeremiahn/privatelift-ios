import Foundation
import Combine
import UserNotifications
#if canImport(UIKit)
import UIKit
#endif
#if canImport(ActivityKit)
import ActivityKit
#endif
#if canImport(AppIntents)
import AppIntents
#endif

#if canImport(ActivityKit)
struct RestTimerAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        var endTime: Date
    }
    var timerName: String
}
#endif

class RestTimerManager: ObservableObject {
    static let shared = RestTimerManager()
    
    @Published var timeRemaining: TimeInterval = 180
    @Published var isActive = false
    
    private var cancellable: AnyCancellable?
    private var timerEndTime: Date?
    private var hapticsEnabled: Bool = true
    
    #if canImport(ActivityKit)
    private var activeActivity: Activity<RestTimerAttributes>?
    #endif
    
    #if os(iOS)
    private var backgroundTaskId: UIBackgroundTaskIdentifier = .invalid
    #endif
    
    private init() {
        #if os(iOS)
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(didEnterBackground),
            name: UIApplication.didEnterBackgroundNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(willEnterForeground),
            name: UIApplication.willEnterForegroundNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleSkipNotification),
            name: Notification.Name("SkipRestTimerNotification"),
            object: nil
        )
        #endif
    }
    
    func startTimer(duration: TimeInterval = 180, allowNotifications: Bool = true, hapticsEnabled: Bool = true) {
        self.hapticsEnabled = hapticsEnabled
        timerEndTime = Date().addingTimeInterval(duration)
        isActive = true
        timeRemaining = duration
        
        cancellable = Timer.publish(every: 1.0, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] now in
                guard let self = self, let endTime = self.timerEndTime else { return }
                let remaining = endTime.timeIntervalSince(now)
                if remaining <= 0 {
                    // Timer finished naturally: clear state without canceling the pending notification request
                    self.isActive = false
                    self.cancellable = nil
                    self.timerEndTime = nil
                    #if canImport(ActivityKit)
                    self.endLiveActivity()
                    #endif
                    #if os(iOS)
                    self.endBackgroundTask()
                    #endif
                    self.triggerNotification()
                } else {
                    self.timeRemaining = remaining
                }
            }
        
        // Always schedule the local notification for rest completion
        scheduleRestNotification(in: duration, totalDuration: duration)
        
        #if canImport(ActivityKit)
        startLiveActivity(endTime: timerEndTime!)
        #endif
    }
    
    func stopTimer() {
        isActive = false
        cancellable = nil
        timerEndTime = nil
        
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ["rest_timer_end"])
        
        #if canImport(ActivityKit)
        endLiveActivity()
        #endif
        
        #if os(iOS)
        endBackgroundTask()
        #endif
    }
    
    #if os(iOS)
    @objc private func didEnterBackground() {
        guard isActive, timerEndTime != nil else { return }
        
        // Start background task to keep timer running and update Live Activity
        backgroundTaskId = UIApplication.shared.beginBackgroundTask(withName: "RestTimerBackground") { [weak self] in
            self?.handleBackgroundExpiration()
        }
    }
    
    @objc private func willEnterForeground() {
        // End background task if it was running
        endBackgroundTask()
        
        // Re-create/update Live Activity if the timer is still active
        #if canImport(ActivityKit)
        if isActive, let endTime = timerEndTime, endTime > Date() {
            startLiveActivity(endTime: endTime)
        }
        #endif
    }
    
    private func endBackgroundTask() {
        if backgroundTaskId != .invalid {
            UIApplication.shared.endBackgroundTask(backgroundTaskId)
            backgroundTaskId = .invalid
        }
    }
    
    private func handleBackgroundExpiration() {
        // Background time ran out, end the Live Activity with a scheduled dismissal at endTime
        #if canImport(ActivityKit)
        if let endTime = timerEndTime {
            endLiveActivity(at: endTime)
        } else {
            endLiveActivity()
        }
        #endif
        endBackgroundTask()
    }
    #endif
    
    private func scheduleRestNotification(in seconds: TimeInterval, totalDuration: TimeInterval) {
        let center = UNUserNotificationCenter.current()
        
        // Check current authorization status and request if needed
        center.getNotificationSettings { settings in
            debugLog("[RestTimer] Notification auth status: \(settings.authorizationStatus.rawValue) (0=notDetermined, 1=denied, 2=authorized, 3=provisional)")
            
            switch settings.authorizationStatus {
            case .notDetermined:
                // Request permission, then schedule
                center.requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
                    debugLog("[RestTimer] Notification permission requested. Granted: \(granted), Error: \(String(describing: error))")
                    if granted {
                        self.doScheduleNotification(center: center, seconds: seconds, totalDuration: totalDuration)
                    }
                }
            case .authorized, .provisional, .ephemeral:
                self.doScheduleNotification(center: center, seconds: seconds, totalDuration: totalDuration)
            case .denied:
                debugLog("[RestTimer] Notifications are DENIED in iOS Settings. User must enable them in Settings > Personal Lift > Notifications.")
            @unknown default:
                self.doScheduleNotification(center: center, seconds: seconds, totalDuration: totalDuration)
            }
        }
    }
    
    private func doScheduleNotification(center: UNUserNotificationCenter, seconds: TimeInterval, totalDuration: TimeInterval) {
        let minutes = Int(totalDuration) / 60
        let secs = Int(totalDuration) % 60
        let durationString = minutes > 0
            ? (secs > 0 ? "\(minutes):\(String(format: "%02d", secs))" : "\(minutes) min")
            : "\(secs) sec"

        let content = UNMutableNotificationContent()
        content.title = "Rest Complete ✅"
        content.body = "Your \(durationString) rest is up — time for your next set!"
        content.sound = .default
        content.interruptionLevel = .timeSensitive
        
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: seconds, repeats: false)
        let request = UNNotificationRequest(identifier: "rest_timer_end", content: content, trigger: trigger)
        
        center.add(request) { error in
            if let error = error {
                debugLog("[RestTimer] ❌ Error scheduling notification: \(error.localizedDescription)")
            } else {
                debugLog("[RestTimer] ✅ Notification scheduled for \(seconds)s from now")
            }
        }
    }
    
    private func triggerNotification() {
        HapticService.play(.success, enabled: hapticsEnabled)
    }
    
    #if canImport(ActivityKit)
    private func startLiveActivity(endTime: Date) {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else {
            debugLog("Live Activities are not enabled.")
            return
        }
        
        let attributes = RestTimerAttributes(timerName: "Rest")
        let contentState = RestTimerAttributes.ContentState(endTime: endTime)
        let content = ActivityContent(state: contentState, staleDate: nil)
        
        do {
            // End any existing activity first to avoid multiples
            endLiveActivity()
            
            let activity = try Activity<RestTimerAttributes>.request(
                attributes: attributes,
                content: content,
                pushType: nil
            )
            self.activeActivity = activity
            debugLog("Successfully started live activity: \(activity.id)")
        } catch {
            debugLog("Failed to start live activity: \(error.localizedDescription)")
        }
    }
    
    private func endLiveActivity(at endTime: Date? = nil) {
        // Clear reference immediately so subsequent calls don't see or end this activity again
        self.activeActivity = nil
        
        let finalState = RestTimerAttributes.ContentState(endTime: endTime ?? Date())
        let finalContent = ActivityContent(state: finalState, staleDate: nil)
        
        let dismissalPolicy: ActivityUIDismissalPolicy
        if let endTime = endTime {
            dismissalPolicy = .after(endTime)
        } else {
            dismissalPolicy = .immediate
        }
        
        // Terminate all active Live Activities of this type on the system
        for activity in Activity<RestTimerAttributes>.activities {
            Task {
                await activity.end(finalContent, dismissalPolicy: dismissalPolicy)
            }
        }
    }
    #endif
    
    @objc private func handleSkipNotification() {
        Task { @MainActor in
            self.stopTimer()
        }
    }
}

#if canImport(AppIntents) && canImport(ActivityKit)
@available(iOS 17.0, macOS 14.0, watchOS 10.0, tvOS 17.0, *)
struct SkipTimerIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "Skip Rest Timer"
    
    init() {}
    
    func perform() async throws -> some IntentResult {
        NotificationCenter.default.post(name: Notification.Name("SkipRestTimerNotification"), object: nil)
        return .result()
    }
}
#endif

