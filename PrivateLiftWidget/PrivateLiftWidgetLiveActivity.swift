import WidgetKit
import SwiftUI
import ActivityKit
import AppIntents

// MARK: - Rest Timer Attributes
// Matches the structure defined in the main app to enable serialization
struct RestTimerAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        var endTime: Date
    }
    var timerName: String
}

// MARK: - Skip Timer Intent
// Executes in the main app process when clicked from the Lock Screen / Dynamic Island
@available(iOS 17.0, *)
struct SkipTimerIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "Skip Rest Timer"
    
    init() {}
    
    func perform() async throws -> some IntentResult {
        NotificationCenter.default.post(name: Notification.Name("SkipRestTimerNotification"), object: nil)
        return .result()
    }
}

// MARK: - Live Activity Widget Configuration
struct PrivateLiftWidgetLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: RestTimerAttributes.self) { context in
            // Lock Screen and Notification Center banner UI
            LiveActivityLockScreenView(context: context)
                .activityBackgroundTint(Color.black.opacity(0.85))
                .activitySystemActionForegroundColor(Color.white)
            
        } dynamicIsland: { context in
            let safeInterval: ClosedRange<Date> = {
                let now = Date.now
                return now >= context.state.endTime ? now...now : now...context.state.endTime
            }()
            
            return DynamicIsland {
                // Expanded Leading Region (Icon & Title)
                DynamicIslandExpandedRegion(.leading) {
                    HStack(spacing: 6) {
                        Image(systemName: "timer")
                            .foregroundColor(Color.blue)
                        Text("Resting")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundColor(.blue)
                    }
                    .padding(.leading, 8)
                }
                
                // Expanded Trailing Region (Countdown)
                DynamicIslandExpandedRegion(.trailing) {
                    Text(timerInterval: safeInterval, countsDown: true)
                        .font(.system(size: 20, weight: .black, design: .monospaced))
                        .monospacedDigit()
                        .foregroundColor(.blue)
                        .padding(.trailing, 8)
                }
                
                // Expanded Bottom Region (Actions/Button)
                DynamicIslandExpandedRegion(.bottom) {
                    HStack {
                        Spacer()
                        Button(intent: SkipTimerIntent()) {
                            HStack(spacing: 4) {
                                Text("SKIP REST")
                                    .font(.system(size: 11, weight: .black))
                                    .tracking(0.5)
                            }
                            .foregroundColor(.white)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                            .background(Color.blue)
                            .cornerRadius(10)
                        }
                        .buttonStyle(.plain)
                        .padding(.top, 4)
                        .padding(.bottom, 4)
                    }
                }
            } compactLeading: {
                Image(systemName: "timer")
                    .foregroundColor(.blue)
            } compactTrailing: {
                Text(timerInterval: safeInterval, countsDown: true)
                    .font(.system(size: 13, weight: .black, design: .monospaced))
                    .monospacedDigit()
                    .foregroundColor(.blue)
                    .frame(width: 48)
            } minimal: {
                Image(systemName: "timer")
                    .foregroundColor(.blue)
            }
            .keylineTint(Color.blue.opacity(0.5))
        }
    }
}

// MARK: - Lock Screen View
struct LiveActivityLockScreenView: View {
    let context: ActivityViewContext<RestTimerAttributes>
    
    var safeInterval: ClosedRange<Date> {
        let now = Date.now
        return now >= context.state.endTime ? now...now : now...context.state.endTime
    }
    
    var body: some View {
        HStack(spacing: 16) {
            // Left Column: Timer Icon and Label
            HStack(spacing: 12) {
                Image(systemName: "timer")
                    .font(.system(size: 24))
                    .foregroundColor(.blue)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text("REST TIMER")
                        .font(.system(size: 8, weight: .black))
                        .tracking(1.5)
                        .foregroundColor(.white.opacity(0.6))
                    
                    Text(timerInterval: safeInterval, countsDown: true)
                        .font(.system(size: 24, weight: .black, design: .monospaced))
                        .monospacedDigit()
                        .foregroundColor(.white)
                }
            }
            
            Spacer()
            
            // Right Column: Skip Button
            Button(intent: SkipTimerIntent()) {
                Text("SKIP")
                    .font(.system(size: 11, weight: .black))
                    .foregroundColor(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(Color.white.opacity(0.15))
                    .cornerRadius(8)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color.white.opacity(0.1), lineWidth: 1)
                    )
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
        .background(Color(red: 0.05, green: 0.05, blue: 0.05)) // Beautiful deep AMOLED background
    }
}
