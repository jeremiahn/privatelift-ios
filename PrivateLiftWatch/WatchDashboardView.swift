// WatchDashboardView.swift
import SwiftUI

/// Displays today's workout summary, fetched from the companion iPhone app.
struct WatchDashboardView: View {
    @ObservedObject private var connectivity = WatchConnectivityManager.shared

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 12) {
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
                                Text("\(connectivity.setCount)")
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
                                Text("\(Int(connectivity.totalWeight).formatted())")
                                    .font(.system(size: 24, weight: .bold, design: .rounded))
                                    .foregroundStyle(.blue)
                                Text("lbs total volume")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .padding(.horizontal, 4)

                        // Log Set button
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
        }
    }
}

#Preview {
    WatchDashboardView()
}
