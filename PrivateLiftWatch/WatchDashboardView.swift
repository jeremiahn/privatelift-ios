// WatchDashboardView.swift
import SwiftUI
import WatchConnectivity
import Combine

/// Displays today's workout summary, fetched from the companion iPhone app.
struct WatchDashboardView: View {
    @State private var setCount: Int = 0
    @State private var totalWeight: Double = 0.0
    @State private var loading = true
    @State private var failed = false

    // Polling timer — refreshes every 30 s while the watch face is visible
    let timer = Timer.publish(every: 30, on: .main, in: .common).autoconnect()

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 12) {
                        if loading {
                            VStack(spacing: 8) {
                                ProgressView()
                                    .progressViewStyle(.circular)
                                    .tint(.blue)
                                Text("Loading…")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.top, 20)
                        } else if failed {
                            VStack(spacing: 6) {
                                Image(systemName: "iphone.slash")
                                    .font(.title2)
                                    .foregroundStyle(.orange)
                                Text("Open PersonalLift\non your iPhone")
                                    .font(.caption2)
                                    .multilineTextAlignment(.center)
                                    .foregroundStyle(.secondary)
                                Button("Retry") { requestSummary() }
                                    .buttonStyle(.bordered)
                                    .tint(.blue)
                                    .font(.caption2)
                            }
                            .padding(.top, 12)
                        } else {
                            VStack(alignment: .leading, spacing: 0) {
                                // Header
                                HStack {
                                    Image(systemName: "flame.fill")
                                        .foregroundStyle(.orange)
                                        .font(.caption2)
                                    Text("TODAY")
                                        .font(.system(size: 11, weight: .black))
                                        .foregroundStyle(.orange)
                                    Spacer()
                                }
                                .padding(.bottom, 8)

                                // Set count
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("\(setCount)")
                                        .font(.system(size: 36, weight: .black, design: .rounded))
                                        .foregroundStyle(.white)
                                    Text("sets logged")
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }

                                Divider()
                                    .overlay(.gray.opacity(0.4))
                                    .padding(.vertical, 6)

                                // Total volume
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("\(Int(totalWeight).formatted())")
                                        .font(.system(size: 24, weight: .bold, design: .rounded))
                                        .foregroundStyle(.blue)
                                    Text("lbs total volume")
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .padding(.horizontal, 4)
                        }

                        // Log Set button — always visible
                        NavigationLink {
                            WatchLogSetView()
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "plus.circle.fill")
                                    .font(.caption)
                                Text("Log Set")
                                    .font(.system(size: 14, weight: .heavy))
                            }
                            .frame(maxWidth: .infinity)
                            .frame(height: 44)
                            .background(.blue)
                            .foregroundStyle(.white)
                            .cornerRadius(12)
                        }
                        .buttonStyle(.plain)
                        .padding(.top, 4)
                    }
                }
            }
            .onAppear { requestSummary() }
            .onReceive(timer) { _ in requestSummary() }
        }
    }

    // MARK: - Data fetch

    private func requestSummary() {
        guard WCSession.isSupported() else {
            failed = true
            loading = false
            return
        }
        let session = WCSession.default
        guard session.activationState == .activated else {
            failed = true
            loading = false
            return
        }
        guard session.isReachable else {
            // Phone not reachable — show last data if we have it, else show fail
            if loading { failed = true; loading = false }
            return
        }

        loading = true
        failed = false

        session.sendMessage(["request": "todaySummary"], replyHandler: { reply in
            DispatchQueue.main.async {
                // The iOS side returns: ["summary": ["setCount": Int, "totalWeight": Double]]
                if let summary = reply["summary"] as? [String: Any] {
                    self.setCount = summary["setCount"] as? Int ?? 0
                    self.totalWeight = summary["totalWeight"] as? Double ?? 0.0
                    self.failed = false
                } else {
                    self.failed = true
                }
                self.loading = false
            }
        }, errorHandler: { _ in
            DispatchQueue.main.async {
                self.failed = true
                self.loading = false
            }
        })
    }
}

#Preview {
    WatchDashboardView()
}
