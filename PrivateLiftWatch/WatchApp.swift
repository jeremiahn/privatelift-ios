// WatchApp.swift
import SwiftUI

@main
struct WatchApp: App {
    // Activates the WCSession on launch so it's ready before the UI appears
    @StateObject private var connectivity = WatchConnectivityManager.shared

    var body: some Scene {
        WindowGroup {
            WatchDashboardView()
        }
    }
}
