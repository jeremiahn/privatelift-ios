import Foundation
import Combine
import UserNotifications
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
    
    #if canImport(ActivityKit)
    private var activeActivity: Activity<RestTimerAttributes>?
    #endif
    
    func startTimer(duration: TimeInterval = 180, allowNotifications: Bool = true) {
        timerEndTime = Date().addingTimeInterval(duration)
        isActive = true
        timeRemaining = duration
        
        cancellable = Timer.publish(every: 1.0, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] now in
                guard let self = self, let endTime = self.timerEndTime else { return }
                let remaining = endTime.timeIntervalSince(now)
                if remaining <= 0 {
                    self.stopTimer()
                    self.triggerNotification()
                } else {
                    self.timeRemaining = remaining
                }
            }
            
        if allowNotifications {
            scheduleRestNotification(in: duration)
        }
        
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
    }
    
    private func scheduleRestNotification(in seconds: TimeInterval) {
        let content = UNMutableNotificationContent()
        content.title = "Rest Completed!"
        content.body = "Time for your next set."
        content.sound = .default
        
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: seconds, repeats: false)
        let request = UNNotificationRequest(identifier: "rest_timer_end", content: content, trigger: trigger)
        
        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                print("Error scheduling local rest notification: \(error.localizedDescription)")
            }
        }
    }
    
    private func triggerNotification() {
        HapticService.play(.success, enabled: true)
    }
    
    #if canImport(ActivityKit)
    private func startLiveActivity(endTime: Date) {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        
        let attributes = RestTimerAttributes(timerName: "Rest Time")
        let state = RestTimerAttributes.ContentState(endTime: endTime)
        
        do {
            activeActivity = try Activity.request(
                attributes: attributes,
                content: .init(state: state, staleDate: nil)
            )
            print("Live Activity started successfully.")
        } catch {
            print("Failed to start Live Activity: \(error.localizedDescription)")
        }
    }
    
    private func endLiveActivity() {
        guard let activity = activeActivity else { return }
        Task {
            await activity.end(nil, dismissalPolicy: .immediate)
            print("Live Activity ended successfully.")
        }
        activeActivity = nil
    }
    #endif
}

#if canImport(AppIntents) && canImport(ActivityKit)
@available(iOS 17.0, macOS 14.0, watchOS 10.0, tvOS 17.0, *)
struct SkipTimerIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "Skip Rest Timer"
    
    init() {}
    
    func perform() async throws -> some IntentResult {
        await MainActor.run {
            RestTimerManager.shared.stopTimer()
        }
        return .result()
    }
}
#endif

