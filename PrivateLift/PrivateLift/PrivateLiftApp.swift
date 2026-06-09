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
        // Show banner + sound even when the app is in the foreground
        completionHandler([.banner, .sound])
    }
}

@main
struct PersonalLiftApp: App {
    let container: ModelContainer

    init() {
        // Set up notification delegate before anything else
        _ = NotificationDelegate.shared
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }

        let schema = Schema([
            UserPreferences.self,
            WorkoutSession.self,
            WorkoutSet.self,
            RoutineTemplate.self,
            RoutineExerciseTarget.self,
            CustomExercise.self
        ])

        // ── Single store URL ──────────────────────────────────────────────────────
        // Both "local only" and "iCloud sync" modes point at the SAME SQLite file.
        // Toggling iCloud simply tells CloudKit to start/stop syncing that file.
        // No data is lost, no migration is required.
        let appSupport = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        try? FileManager.default.createDirectory(at: appSupport, withIntermediateDirectories: true)
        let storeURL = appSupport.appendingPathComponent("PrivateLift.store")

        let iCloudEnabled = UserDefaults.standard.bool(forKey: "iCloudSyncEnabled")
        let cloudKitMode: ModelConfiguration.CloudKitDatabase = iCloudEnabled ? .automatic : .none
        let config = ModelConfiguration(url: storeURL, cloudKitDatabase: cloudKitMode)

        do {
            self.container = try ModelContainer(for: schema, configurations: [config])
            print("ModelContainer initialized successfully. iCloud Sync: \(iCloudEnabled)")
            // Clear any previous sync error now that we loaded cleanly
            UserDefaults.standard.removeObject(forKey: "iCloudSyncError")
        } catch {
            if iCloudEnabled {
                // iCloud init failed — record the error and fall back to local-only
                // on the same file so data is never lost.
                let nsError = error as NSError
                let detail = "Error: \(nsError.localizedDescription) (Code \(nsError.code), Domain: \(nsError.domain))"
                print("iCloud ModelContainer failed: \(detail). Falling back to local-only...")
                UserDefaults.standard.set(detail, forKey: "iCloudSyncError")
                UserDefaults.standard.set(false, forKey: "iCloudSyncEnabled")

                let fallback = ModelConfiguration(url: storeURL, cloudKitDatabase: .none)
                do {
                    self.container = try ModelContainer(for: schema, configurations: [fallback])
                    print("Local-only ModelContainer fallback initialized successfully.")
                } catch {
                    fatalError("Could not initialize fallback ModelContainer: \(error.localizedDescription)")
                }
            } else {
                fatalError("Could not initialize local ModelContainer: \(error.localizedDescription)")
            }
        }

        // Keep SwiftData preferences in sync with the UserDefaults iCloud flag
        let context = self.container.mainContext
        
        // Configure Watch Connectivity
        WatchConnectivityManager.shared.configure(context: context)
        
        let fetchDescriptor = FetchDescriptor<UserPreferences>()
        if let prefs = (try? context.fetch(fetchDescriptor))?.first {
            if prefs.iCloudSyncEnabled != iCloudEnabled {
                prefs.iCloudSyncEnabled = iCloudEnabled
                try? context.save()
                print("Synchronized DB iCloudSyncEnabled → \(iCloudEnabled)")
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
