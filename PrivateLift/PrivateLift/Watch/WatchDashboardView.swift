// WatchDashboardView.swift
import SwiftUI
import WatchConnectivity

/// Simple watch UI that displays today's workout summary.
struct WatchDashboardView: View {
    @State private var setCount: Int = 0
    @State private var totalWeight: Double = 0.0
    @State private var loading = true

    var body: some View {
        VStack(spacing: 8) {
            if loading {
                ProgressView()
            } else {
                Text("Today's Workout")
                    .font(.headline)
                Text("Sets: \(setCount)")
                Text("Weight: \(Int(totalWeight)) lb")
            }
        }
        .onAppear {
            requestSummary()
        }
    }

    private func requestSummary() {
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        if session.isPaired && session.isWatchAppInstalled {
            session.sendMessage(["request": "todaySummary"], replyHandler: { reply in
                if let count = reply["summary"] as? [String: Any] {
                    DispatchQueue.main.async {
                        self.setCount = count["setCount"] as? Int ?? 0
                        self.totalWeight = count["totalWeight"] as? Double ?? 0.0
                        self.loading = false
                    }
                }
            }, errorHandler: { _ in })
        }
    }
}

struct WatchDashboardView_Previews: PreviewProvider {
    static var previews: some View {
        WatchDashboardView()
    }
}
