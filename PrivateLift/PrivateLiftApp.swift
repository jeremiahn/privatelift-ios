//
//  PrivateLiftApp.swift
//  PrivateLift
//
//  Created by Jeremiah Nelson on 5/31/26.
//

import SwiftUI
import SwiftData
import UserNotifications

class NotificationDelegate: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationDelegate()
    
    override init() {
        super.init()
        UNUserNotificationCenter.current().delegate = self
    }
    
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        // Force banner alerts and sounds when the app is active in the foreground
        completionHandler([.banner, .sound])
    }
}

@main
struct PersonalLiftApp: App {
    let container: ModelContainer
    
    init() {
        // Initialize global notification delegate
        _ = NotificationDelegate.shared
        
        // Prompt for notification authorization on app launch
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
        
        // Dynamic SwiftData iCloud configuration at launch!
        let schema = Schema([
            UserPreferences.self,
            WorkoutSession.self,
            WorkoutSet.self,
            RoutineTemplate.self,
            RoutineExerciseTarget.self,
            CustomExercise.self
        ])
        
        let iCloudEnabled = UserDefaults.standard.bool(forKey: "iCloudSyncEnabled")
        let config: ModelConfiguration
        if iCloudEnabled {
            config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false, cloudKitDatabase: .private("iCloud.Nelson-Computers.PrivateLift"))
        } else {
            config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false, cloudKitDatabase: .none)
        }
        
        do {
            self.container = try ModelContainer(for: schema, configurations: [config])
            print("ModelContainer initialized successfully. iCloud Sync: \(iCloudEnabled)")
        } catch {
            if iCloudEnabled {
                print("iCloud ModelContainer failed to initialize: \(error.localizedDescription). Falling back to local container...")
                // Turn off iCloud sync toggle so next launch works locally
                UserDefaults.standard.set(false, forKey: "iCloudSyncEnabled")
                
                let fallbackConfig = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false, cloudKitDatabase: .none)
                do {
                    self.container = try ModelContainer(for: schema, configurations: [fallbackConfig])
                    print("Local ModelContainer fallback initialized successfully.")
                } catch {
                    fatalError("Could not initialize fallback ModelContainer: \(error.localizedDescription)")
                }
            } else {
                fatalError("Could not initialize local ModelContainer: \(error.localizedDescription)")
            }
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(container)
    }
}
