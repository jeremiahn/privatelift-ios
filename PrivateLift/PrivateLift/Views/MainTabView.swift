import SwiftUI
import SwiftData

struct MainTabView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var preferences: [UserPreferences]
    
    @StateObject private var timerManager = RestTimerManager.shared
    @StateObject private var healthKitService = HealthKitService.shared
    @State private var selectedTab = 0
    @State private var showOnboarding = false
    @State private var migrationManager: LegacyMigrationManager?
    
    var activePrefs: UserPreferences {
        preferences.first ?? UserPreferences()
    }
    
    var preferredColorScheme: ColorScheme? {
        switch ThemeStyle(rawValue: activePrefs.theme) ?? .system {
        case .light:
            return .light
        case .dark, .night:
            return .dark
        case .system:
            return nil
        }
    }
    
    var brandColors: BrandColors {
        BrandColors(theme: ThemeStyle(rawValue: activePrefs.theme) ?? .system)
    }
    
    var body: some View {
        ZStack {
            TabView(selection: $selectedTab) {
                DashboardView(timerManager: timerManager, healthService: healthKitService)
                    .tabItem {
                        Label("Dashboard", systemImage: "square.grid.2x2.fill")
                    }
                    .tag(0)
                    .keyboardShortcut("1", modifiers: .command)
                
                StatsView()
                    .tabItem {
                        Label("Stats", systemImage: "chart.bar.fill")
                    }
                    .tag(1)
                    .keyboardShortcut("2", modifiers: .command)
                
                HistoryView()
                    .tabItem {
                        Label("History", systemImage: "calendar")
                    }
                    .tag(2)
                    .keyboardShortcut("3", modifiers: .command)
                
                SettingsView(healthService: healthKitService)
                    .tabItem {
                        Label("Settings", systemImage: "gearshape.fill")
                    }
                    .tag(3)
                    .keyboardShortcut("4", modifiers: .command)
            }
            .tint(brandColors.blue)
            .modifier(RestTimerAccessoryModifier(
                isEnabled: timerManager.isActive && activePrefs.showRestTimer,
                timerManager: timerManager,
                brandColors: brandColors
            ))

            // Rest Timer floating overlay when active (iOS 18 – 26.0; see usesTabAccessory)
            if timerManager.isActive && activePrefs.showRestTimer && !Self.usesTabAccessory {
                VStack {
                    Spacer()
                    RestTimerFloatingCapsule(timerManager: timerManager, brandColors: brandColors)
                        .padding(.bottom, 60) // Floating right above tab bar
                }
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .plBackground(style: ThemeStyle(rawValue: activePrefs.theme) ?? .system)
        .preferredColorScheme(preferredColorScheme)
        .onAppear {
            checkOnboardingAndMigration()
            #if DEBUG
            // Screenshot/UI check helper: `-demoRestTimer YES` starts a rest timer on launch.
            if UserDefaults.standard.bool(forKey: "demoRestTimer") {
                timerManager.startTimer(duration: 150)
            }
            #endif
        }
        .fullScreenCover(isPresented: $showOnboarding) {
            OnboardingView(isPresented: $showOnboarding)
        }
    }
    
    /// iOS 26.1+ shows the rest timer in the system tab-bar accessory, which the system
    /// positions and styles. 26.0 has the accessory but can't hide it when idle
    /// (`isEnabled:` is 26.1+), so 26.0 and earlier keep the floating capsule.
    static var usesTabAccessory: Bool {
        if #available(iOS 26.1, *) { return true }
        return false
    }

    private func checkOnboardingAndMigration() {
        // Trigger silent data migration if needed
        if !UserDefaults.standard.bool(forKey: "hasMigratedWebData") {
            migrationManager = LegacyMigrationManager(modelContext: modelContext)
            migrationManager?.startMigrationIfNeeded()
        }
        
        // Trigger onboarding overlay if not completed
        if !activePrefs.isOnboarded {
            showOnboarding = true
        }
    }
}

// MARK: - Rest Timer Floating UI Component
struct RestTimerFloatingCapsule: View {
    @ObservedObject var timerManager: RestTimerManager
    var brandColors: BrandColors
    
    var body: some View {
        HStack(spacing: 12) {
            HStack(spacing: 12) {
                Image(systemName: "timer")
                    .font(.headline)
                    .foregroundColor(brandColors.darkBgText)
                    .symbolEffect(.pulse, isActive: true)
                    .accessibilityHidden(true)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text("REST TIMER")
                        .scaledFont(size: 8, weight: .black)
                        .tracking(1.5)
                        .foregroundColor(brandColors.darkBgText.opacity(0.7))
                    
                    Text(timeString(from: timerManager.timeRemaining))
                        .font(.system(.title3, design: .monospaced))
                        .fontWeight(.black)
                        .foregroundColor(brandColors.darkBgText)
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Rest Timer")
            .accessibilityValue(accessibilityTimeString(from: timerManager.timeRemaining))
            
            Spacer()

            adjustButton("-30", seconds: -30, label: "Remove 30 seconds")
            adjustButton("+30", seconds: 30, label: "Add 30 seconds")

            Button(action: {
                HapticService.play(.medium)
                timerManager.stopTimer()
            }) {
                Text("SKIP")
                    .scaledFont(size: 10, weight: .black)
                    .foregroundColor(brandColors.darkBgText)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(brandColors.darkBgText.opacity(0.2))
                    .cornerRadius(8)
            }
            .accessibilityLabel("Skip rest timer")
            .accessibilityHint("Double tap to skip the remaining rest duration")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(brandColors.timerBackground)
        .cornerRadius(20)
        .overlay(
            RoundedRectangle(cornerRadius: 20)
                .stroke(brandColors.darkBgText.opacity(0.15), lineWidth: 1.5)
        )
        .shadow(color: brandColors.timerBackground.opacity(0.3), radius: 10, y: 5)
        .padding(.horizontal, 16)
        .frame(maxWidth: 400)
    }
    
    private func adjustButton(_ title: String, seconds: TimeInterval, label: String) -> some View {
        Button {
            HapticService.play(.medium)
            timerManager.adjust(by: seconds)
        } label: {
            Text(title)
                .scaledFont(size: 10, weight: .black, design: .monospaced)
                .foregroundColor(brandColors.darkBgText)
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .background(brandColors.darkBgText.opacity(0.12))
                .cornerRadius(8)
        }
        .accessibilityLabel(label)
    }

    private func timeString(from interval: TimeInterval) -> String {
        let mins = Int(interval) / 60
        let secs = Int(interval) % 60
        return String(format: "%02d:%02d", mins, secs)
    }
    
    private func accessibilityTimeString(from interval: TimeInterval) -> String {
        let mins = Int(interval) / 60
        let secs = Int(interval) % 60
        if mins > 0 {
            return "\(mins) minute\(mins > 1 ? "s" : "") and \(secs) second\(secs != 1 ? "s" : "") remaining"
        } else {
            return "\(secs) second\(secs != 1 ? "s" : "") remaining"
        }
    }
}

// MARK: - iOS 26.1+ Tab Bar Accessory

private struct RestTimerAccessoryModifier: ViewModifier {
    var isEnabled: Bool
    @ObservedObject var timerManager: RestTimerManager
    var brandColors: BrandColors

    func body(content: Content) -> some View {
        if #available(iOS 26.1, *) {
            content.tabViewBottomAccessory(isEnabled: isEnabled) {
                RestTimerAccessoryView(timerManager: timerManager, brandColors: brandColors)
            }
        } else {
            content
        }
    }
}

/// Compact rest timer for the tab-bar accessory. The system draws the glass background,
/// so this uses plain foreground colors rather than the capsule's filled blue.
private struct RestTimerAccessoryView: View {
    @ObservedObject var timerManager: RestTimerManager
    var brandColors: BrandColors

    var body: some View {
        HStack(spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "timer")
                    .foregroundColor(brandColors.blue)
                    .symbolEffect(.pulse, isActive: true)
                Text(timeString)
                    .font(.system(.body, design: .monospaced))
                    .fontWeight(.black)
                    .monospacedDigit()
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Rest timer")
            .accessibilityValue("\(Int(timerManager.timeRemaining)) seconds remaining")

            Spacer(minLength: 4)

            control("-30", label: "Remove 30 seconds") { timerManager.adjust(by: -30) }
            control("+30", label: "Add 30 seconds") { timerManager.adjust(by: 30) }
            control("SKIP", label: "Skip rest timer") { timerManager.stopTimer() }
        }
        .padding(.horizontal, 16)
    }

    private var timeString: String {
        let total = max(0, Int(timerManager.timeRemaining))
        return String(format: "%d:%02d", total / 60, total % 60)
    }

    private func control(_ title: String, label: String, action: @escaping () -> Void) -> some View {
        Button {
            HapticService.play(.medium)
            action()
        } label: {
            Text(title)
                .scaledFont(size: 11, weight: .black, design: .monospaced)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Color.primary.opacity(0.08))
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }
}
