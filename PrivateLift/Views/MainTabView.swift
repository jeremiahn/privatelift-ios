import SwiftUI
import SwiftData

struct MainTabView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var preferences: [UserPreferences]
    
    @StateObject private var timerManager = RestTimerManager()
    @StateObject private var healthKitService = HealthKitService()
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
                
                StatsView()
                    .tabItem {
                        Label("Stats", systemImage: "chart.bar.fill")
                    }
                    .tag(1)
                
                HistoryView()
                    .tabItem {
                        Label("History", systemImage: "calendar")
                    }
                    .tag(2)
                
                SettingsView(healthService: healthKitService)
                    .tabItem {
                        Label("Settings", systemImage: "gearshape.fill")
                    }
                    .tag(3)
            }
            .tint(brandColors.blue)
            
            // Rest Timer floating overlay when active
            if timerManager.isActive && activePrefs.showRestTimer {
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
        }
        .fullScreenCover(isPresented: $showOnboarding) {
            OnboardingView(isPresented: $showOnboarding)
        }
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
                        .font(.system(size: 8, weight: .black))
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
            
            Button(action: {
                HapticService.play(.medium)
                timerManager.stopTimer()
            }) {
                Text("SKIP")
                    .font(.system(size: 10, weight: .black))
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


