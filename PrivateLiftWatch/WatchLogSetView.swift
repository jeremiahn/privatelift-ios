// WatchLogSetView.swift
import SwiftUI

/// A compact set-logging form for the Apple Watch.
struct WatchLogSetView: View {
    @ObservedObject private var connectivity = WatchConnectivityManager.shared
    @State private var selectedExercise = ""
    @State private var weight: Double = 135
    @State private var reps: Int = 5
    @State private var setType = "working"
    @State private var saved = false

    private let setTypes = ["warmup", "working", "failed"]

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                if saved {
                    savedConfirmation
                } else {
                    logForm
                }
            }
            .padding(.horizontal, 4)
        }
        .navigationTitle("Log Set")
        .onAppear {
            initializeSelection()
        }
    }

    private func initializeSelection() {
        if selectedExercise.isEmpty, let first = connectivity.exercises.first {
            selectedExercise = first["name"] ?? ""
        }
        if weight == 135 && connectivity.weightUnit == "kg" {
            weight = 60
        }
    }

    private var savedConfirmation: some View {
        VStack(spacing: 10) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 36))
                .foregroundStyle(.green)
            Text("Set Logged!")
                .font(.system(size: 15, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
            Text(displayNameFor(selectedExercise))
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text("\(Int(weight)) \(connectivity.weightUnit) × \(reps)")
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(.blue)

            Button("Log Another") {
                saved = false
            }
            .buttonStyle(.bordered)
            .tint(.blue)
            .font(.caption2)
            .padding(.top, 4)
        }
    }

    private var logForm: some View {
        VStack(spacing: 10) {
            // Exercise picker
            VStack(alignment: .leading, spacing: 2) {
                Text("EXERCISE")
                    .font(.system(size: 9, weight: .heavy))
                    .foregroundStyle(.secondary)
                    .tracking(1)
                
                if connectivity.exercises.isEmpty {
                    Text("No exercises found. Please launch the iPhone app to sync.")
                        .font(.caption2)
                        .foregroundStyle(.orange)
                } else {
                    Picker("Exercise", selection: $selectedExercise) {
                        ForEach(connectivity.exercises, id: \.self) { ex in
                            Text(ex["displayName"] ?? ex["name"] ?? "")
                                .tag(ex["name"] ?? "")
                        }
                    }
                    .pickerStyle(.navigationLink)
                }
            }

            Divider().overlay(Color.gray.opacity(0.3))

            // Weight
            VStack(alignment: .leading, spacing: 2) {
                Text("WEIGHT (\(connectivity.weightUnit.uppercased()))")
                    .font(.system(size: 9, weight: .heavy))
                    .foregroundStyle(.secondary)
                    .tracking(1)
                HStack {
                    Button {
                        weight = max(0, weight - 5)
                    } label: {
                        Image(systemName: "minus")
                            .font(.system(size: 14, weight: .bold))
                            .frame(width: 32, height: 32)
                    }
                    .buttonStyle(.bordered)
                    .tint(.gray)

                    Text("\(Int(weight))")
                        .font(.system(size: 20, weight: .black, design: .rounded))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)

                    Button {
                        weight += 5
                    } label: {
                        Image(systemName: "plus")
                            .font(.system(size: 14, weight: .bold))
                            .frame(width: 32, height: 32)
                    }
                    .buttonStyle(.bordered)
                    .tint(.gray)
                }
            }

            Divider().overlay(Color.gray.opacity(0.3))

            // Reps
            VStack(alignment: .leading, spacing: 2) {
                Text("REPS")
                    .font(.system(size: 9, weight: .heavy))
                    .foregroundStyle(.secondary)
                    .tracking(1)
                HStack {
                    Button {
                        reps = max(1, reps - 1)
                    } label: {
                        Image(systemName: "minus")
                            .font(.system(size: 14, weight: .bold))
                            .frame(width: 32, height: 32)
                    }
                    .buttonStyle(.bordered)
                    .tint(.gray)

                    Text("\(reps)")
                        .font(.system(size: 20, weight: .black, design: .rounded))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)

                    Button {
                        reps += 1
                    } label: {
                        Image(systemName: "plus")
                            .font(.system(size: 14, weight: .bold))
                            .frame(width: 32, height: 32)
                    }
                    .buttonStyle(.bordered)
                    .tint(.gray)
                }
            }

            Divider().overlay(Color.gray.opacity(0.3))

            // Set type
            VStack(alignment: .leading, spacing: 4) {
                Text("SET TYPE")
                    .font(.system(size: 9, weight: .heavy))
                    .foregroundStyle(.secondary)
                    .tracking(1)
                HStack(spacing: 4) {
                    ForEach(setTypes, id: \.self) { type in
                        Button {
                            setType = type
                        } label: {
                            Text(type.capitalized)
                                .font(.system(size: 11, weight: .bold))
                                .foregroundStyle(setType == type ? .white : .secondary)
                                .frame(maxWidth: .infinity)
                                .frame(height: 32)
                                .background(setType == type ? Color.blue : Color.white.opacity(0.12))
                                .cornerRadius(8)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            // Save button
            Button(action: logSet) {
                HStack(spacing: 4) {
                    Image(systemName: "plus.circle.fill")
                        .font(.caption)
                    Text("Log Set")
                        .font(.system(size: 13, weight: .heavy))
                }
                .frame(maxWidth: .infinity)
                .frame(height: 40)
            }
            .buttonStyle(.borderedProminent)
            .tint(.blue)
            .disabled(selectedExercise.isEmpty)
            .padding(.top, 4)
        }
    }

    private func displayNameFor(_ name: String) -> String {
        connectivity.exercises.first(where: { $0["name"] == name })?["displayName"] ?? name
    }

    private func logSet() {
        guard !selectedExercise.isEmpty else { return }
        connectivity.logSet(exercise: selectedExercise, weight: weight, reps: reps, setType: setType)
        saved = true
    }
}

#Preview {
    NavigationStack {
        WatchLogSetView()
    }
}
