// WatchLogSetView.swift
import SwiftUI
import WatchConnectivity

/// A compact set-logging form for the Apple Watch.
/// Sends the logged set to the iPhone via WatchConnectivity for persistence.
struct WatchLogSetView: View {
    @State private var exercises: [[String: String]] = []
    @State private var selectedExercise = ""
    @State private var weight: Double = 135
    @State private var reps: Int = 5
    @State private var setType = "working"
    @State private var saving = false
    @State private var saved = false
    @State private var loadingExercises = true

    private let setTypes = ["warmup", "working", "failed"]

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                if loadingExercises {
                    ProgressView()
                        .progressViewStyle(.circular)
                        .tint(.blue)
                    Text("Loading exercises…")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                } else if saved {
                    savedConfirmation
                } else {
                    logForm
                }
            }
            .padding(.horizontal, 4)
        }
        .navigationTitle("Log Set")
        .onAppear { fetchExercises() }
    }

    // MARK: - Saved Confirmation

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
            Text("\(Int(weight)) lbs × \(reps)")
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

    // MARK: - Log Form

    private var logForm: some View {
        VStack(spacing: 10) {
            // Exercise picker
            VStack(alignment: .leading, spacing: 2) {
                Text("EXERCISE")
                    .font(.system(size: 9, weight: .heavy))
                    .foregroundStyle(.secondary)
                    .tracking(1)
                Picker("Exercise", selection: $selectedExercise) {
                    ForEach(exercises, id: \.self) { ex in
                        Text(ex["displayName"] ?? ex["name"] ?? "")
                            .tag(ex["name"] ?? "")
                    }
                }
                .pickerStyle(.navigationLink)
            }

            Divider().overlay(Color.gray.opacity(0.3))

            // Weight
            VStack(alignment: .leading, spacing: 2) {
                Text("WEIGHT (LBS)")
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
                    if saving {
                        ProgressView()
                            .progressViewStyle(.circular)
                            .scaleEffect(0.7)
                    } else {
                        Image(systemName: "plus.circle.fill")
                            .font(.caption)
                    }
                    Text("Log Set")
                        .font(.system(size: 13, weight: .heavy))
                }
                .frame(maxWidth: .infinity)
                .frame(height: 40)
            }
            .buttonStyle(.borderedProminent)
            .tint(.blue)
            .disabled(saving || selectedExercise.isEmpty)
            .padding(.top, 4)
        }
    }

    // MARK: - Helpers

    private func displayNameFor(_ name: String) -> String {
        exercises.first(where: { $0["name"] == name })?["displayName"] ?? name
    }

    // MARK: - Networking

    private func fetchExercises() {
        guard WCSession.isSupported() else {
            loadingExercises = false
            return
        }
        let session = WCSession.default
        guard session.activationState == .activated, session.isReachable else {
            loadingExercises = false
            return
        }

        session.sendMessage(["request": "exercises"], replyHandler: { reply in
            DispatchQueue.main.async {
                if let list = reply["exercises"] as? [[String: Any]] {
                    self.exercises = list.map { dict in
                        [
                            "name": dict["name"] as? String ?? "",
                            "displayName": dict["displayName"] as? String ?? "",
                            "colorHex": dict["colorHex"] as? String ?? ""
                        ]
                    }
                    if self.selectedExercise.isEmpty, let first = self.exercises.first {
                        self.selectedExercise = first["name"] ?? ""
                    }
                }
                self.loadingExercises = false
            }
        }, errorHandler: { _ in
            DispatchQueue.main.async {
                self.loadingExercises = false
            }
        })
    }

    private func logSet() {
        guard !selectedExercise.isEmpty else { return }
        saving = true

        let session = WCSession.default
        guard session.activationState == .activated, session.isReachable else {
            saving = false
            return
        }

        let payload: [String: Any] = [
            "request": "logSet",
            "exercise": selectedExercise,
            "weight": weight,
            "reps": reps,
            "rpe": 8.0,          // sensible default for Watch — no slider to save space
            "setType": setType
        ]

        session.sendMessage(payload, replyHandler: { reply in
            DispatchQueue.main.async {
                self.saving = false
                if reply["success"] as? Bool == true {
                    self.saved = true
                }
            }
        }, errorHandler: { _ in
            DispatchQueue.main.async {
                self.saving = false
            }
        })
    }
}

#Preview {
    NavigationStack {
        WatchLogSetView()
    }
}
