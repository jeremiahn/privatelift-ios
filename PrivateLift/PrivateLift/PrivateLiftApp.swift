//
//  PrivateLiftApp.swift
//  PrivateLift
//
//  Created by Jeremiah Nelson on 5/31/26.
//

import SwiftUI
import SwiftData
import UserNotifications
#if canImport(UIKit)
import UIKit
#endif

@inline(__always)
func debugLog(_ message: @autoclosure () -> String) {
    #if DEBUG
    print(message())
    #endif
}

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
        debugLog("[Notification] willPresent fired: \(notification.request.content.title) — \(notification.request.content.body)")
        // Show banner + sound + list (Notification Center) even when the app is in the foreground
        completionHandler([.banner, .sound, .list])
    }
}

@main
struct PersonalLiftApp: App {
    let container: ModelContainer?
    let databaseError: String?

    init() {
        // Set up notification delegate before anything else
        _ = NotificationDelegate.shared
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in }

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

        var resolvedContainer: ModelContainer? = nil
        var failureMessage: String? = nil

        do {
            resolvedContainer = try ModelContainer(for: schema, configurations: [config])
            debugLog("ModelContainer initialized successfully. iCloud Sync: \(iCloudEnabled)")
            // Clear any previous sync error now that we loaded cleanly
            UserDefaults.standard.removeObject(forKey: "iCloudSyncError")
        } catch {
            if iCloudEnabled {
                // iCloud init failed — record the error and fall back to local-only
                // on the same file so data is never lost.
                let nsError = error as NSError
                let detail = "Error: \(nsError.localizedDescription) (Code \(nsError.code), Domain: \(nsError.domain))"
                debugLog("iCloud ModelContainer failed: \(detail). Falling back to local-only...")
                UserDefaults.standard.set(detail, forKey: "iCloudSyncError")
                UserDefaults.standard.set(false, forKey: "iCloudSyncEnabled")

                let fallback = ModelConfiguration(url: storeURL, cloudKitDatabase: .none)
                do {
                    resolvedContainer = try ModelContainer(for: schema, configurations: [fallback])
                    debugLog("Local-only ModelContainer fallback initialized successfully.")
                } catch {
                    failureMessage = "Could not initialize fallback database: \(error.localizedDescription)"
                    debugLog(failureMessage ?? "")
                }
            } else {
                failureMessage = "Could not initialize local database: \(error.localizedDescription)"
                debugLog(failureMessage ?? "")
            }
        }

        self.container = resolvedContainer
        self.databaseError = failureMessage

        // Configure context-dependent services if container initialized successfully
        if let container = resolvedContainer {
            let context = container.mainContext
            WatchConnectivityManager.shared.configure(context: context)
            
            let fetchDescriptor = FetchDescriptor<UserPreferences>()
            if let prefs = (try? context.fetch(fetchDescriptor))?.first {
                if prefs.iCloudSyncEnabled != iCloudEnabled {
                    prefs.iCloudSyncEnabled = iCloudEnabled
                    try? context.save()
                    debugLog("Synchronized DB iCloudSyncEnabled → \(iCloudEnabled)")
                }
            }
        }
    }

    var body: some Scene {
        WindowGroup {
            if let container = container {
                ContentView()
                    .modelContainer(container)
            } else {
                DatabaseRecoveryView(errorMessage: databaseError ?? "Unknown storage error.")
            }
        }
    }
}

struct DatabaseRecoveryView: View {
    let errorMessage: String
    @State private var copied = false

    var body: some View {
        VStack(spacing: 24) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 54))
                .foregroundColor(.red)

            Text("Database Error")
                .font(.title)
                .fontWeight(.black)

            Text("PersonalLift encountered an unrecoverable database initialization error. You can copy the diagnostic details or reset your local database to recover.")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)

            Text(errorMessage)
                .font(.system(.caption, design: .monospaced))
                .padding()
                .background(Color.secondary.opacity(0.1))
                .cornerRadius(8)
                .padding(.horizontal)

            VStack(spacing: 12) {
                Button(action: {
                    #if canImport(UIKit)
                    UIPasteboard.general.string = errorMessage
                    copied = true
                    #endif
                }) {
                    Label(copied ? "Copied to Clipboard" : "Copy Diagnostic Details", systemImage: copied ? "checkmark" : "doc.on.doc")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.blue.opacity(0.15))
                        .foregroundColor(.blue)
                        .cornerRadius(12)
                }

                Button(role: .destructive, action: {
                    resetDatabaseFiles()
                }) {
                    Label("Reset Database & Restart", systemImage: "trash.fill")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.red)
                        .foregroundColor(.white)
                        .cornerRadius(12)
                }
            }
            .padding(.horizontal)
        }
        .padding()
    }

    private func resetDatabaseFiles() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let storeURL = appSupport.appendingPathComponent("PrivateLift.store")
        let shmURL = appSupport.appendingPathComponent("PrivateLift.store-shm")
        let walURL = appSupport.appendingPathComponent("PrivateLift.store-wal")

        try? FileManager.default.removeItem(at: storeURL)
        try? FileManager.default.removeItem(at: shmURL)
        try? FileManager.default.removeItem(at: walURL)
        UserDefaults.standard.removeObject(forKey: "iCloudSyncError")
        UserDefaults.standard.removeObject(forKey: "iCloudSyncEnabled")

        exit(0)
    }
}
