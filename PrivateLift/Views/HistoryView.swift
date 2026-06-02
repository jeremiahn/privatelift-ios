import SwiftUI
import SwiftData
import Charts

struct HistoryView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var preferences: [UserPreferences]
    
    // Query all workout sessions, sorting descending (most recent first)
    @Query(sort: \WorkoutSession.dateString, order: .reverse) private var sessions: [WorkoutSession]
    
    // Query all workout sets to calculate E1RM progression
    @Query(sort: \WorkoutSet.timestamp, order: .forward) private var allSets: [WorkoutSet]
    
    // Query all custom exercises
    @Query(sort: \CustomExercise.orderIndex) private var exercises: [CustomExercise]
    
    @State private var expandedSessionDate: String? = nil
    @State private var sessionNotesText = ""
    
    @State private var showDeleteSetConfirmation = false
    @State private var setToDelete: WorkoutSet? = nil
    @State private var sessionToDeleteFrom: WorkoutSession? = nil
    
    @State private var showDeleteSessionConfirmation = false
    @State private var sessionToDelete: WorkoutSession? = nil
    @FocusState private var isNotesFocused: Bool
    
    var activePrefs: UserPreferences {
        preferences.first ?? UserPreferences()
    }
    
    var themeStyle: ThemeStyle {
        ThemeStyle(rawValue: activePrefs.theme) ?? .system
    }
    
    var brandColors: BrandColors {
        BrandColors(theme: themeStyle)
    }
    
    // MARK: - e1RM Chart Data Structures
    struct ChartDataPoint: Identifiable {
        let id = UUID()
        let date: Date
        let liftName: String
        let e1RM: Double
    }
    
    var chartPoints: [ChartDataPoint] {
        let formula = activePrefs.formula
        var dailyMaxes: [String: [String: Double]] = [:] // YYYY-MM-DD -> [LIFT -> MAX_E1RM]
        
        for set in allSets {
            guard let dateStr = set.session?.dateString else { continue }
            let e1rm = calculateE1RM(weight: set.weight, reps: set.reps, formula: formula)
            
            var dayLifts = dailyMaxes[dateStr] ?? [:]
            let currentMax = dayLifts[set.exercise] ?? 0.0
            if e1rm > currentMax {
                dayLifts[set.exercise] = e1rm
                dailyMaxes[dateStr] = dayLifts
            }
        }
        
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        if let tz = TimeZone(identifier: activePrefs.timeZoneIdentifier) {
            formatter.timeZone = tz
        }
        
        var points: [ChartDataPoint] = []
        
        // Sort dates chronologically
        let sortedDates = dailyMaxes.keys.sorted()
        
        for dateStr in sortedDates {
            guard let date = formatter.date(from: dateStr),
                  let lifts = dailyMaxes[dateStr] else { continue }
            
            for (lift, val) in lifts {
                let displayName = exercises.first(where: { $0.name == lift })?.displayName ?? lift.capitalized
                points.append(ChartDataPoint(date: date, liftName: displayName, e1RM: val))
            }
        }
        
        return points
    }
    
    private func calculateE1RM(weight: Double, reps: Int, formula: String) -> Double {
        if reps <= 1 { return weight }
        switch formula {
        case "brzycki":
            return weight / (1.0278 - (0.0278 * Double(reps)))
        case "lander":
            return (100.0 * weight) / (101.3 - (2.6712 * Double(reps)))
        default: // epley
            return weight * (1.0 + Double(reps) / 30.0)
        }
    }
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    
                    // e1RM Progression Swift Chart Card
                    VStack(alignment: .leading, spacing: 16) {
                        Text("ESTIMATED 1RM PROGRESSION")
                            .font(.system(size: 11, weight: .black))
                            .foregroundColor(brandColors.teal)
                            .tracking(2.0)
                        
                        if chartPoints.isEmpty {
                            VStack(spacing: 8) {
                                Image(systemName: "chart.line.uptrend.xyaxis")
                                    .font(.system(size: 32))
                                    .foregroundColor(.plGray700)
                                Text("No progression data yet.")
                                    .font(.system(size: 12, weight: .bold))
                                    .foregroundColor(.plGray500)
                            }
                            .frame(maxWidth: .infinity)
                            .frame(height: 200)
                        } else {
                            Chart(chartPoints) { point in
                                LineMark(
                                    x: .value("Date", point.date),
                                    y: .value("e1RM", point.e1RM)
                                )
                                .foregroundStyle(by: .value("Lift", point.liftName))
                                .interpolationMethod(.catmullRom)
                                
                                PointMark(
                                    x: .value("Date", point.date),
                                    y: .value("e1RM", point.e1RM)
                                )
                                .foregroundStyle(by: .value("Lift", point.liftName))
                            }
                            .chartForegroundStyleScale([
                                "Squat": brandColors.red,
                                "Bench Press": brandColors.blue,
                                "Deadlift": brandColors.green
                            ])
                            .frame(height: 220)
                        }
                    }
                    .padding(20)
                    .glassCard(style: themeStyle)
                    
                    if sessions.isEmpty {
                        VStack(spacing: 12) {
                            Image(systemName: "calendar.badge.exclamationmark")
                                .font(.system(size: 44))
                                .foregroundColor(.plGray700)
                            Text("No logged sessions found.")
                                .font(.system(size: 15, weight: .black))
                                .foregroundColor(.plGray400)
                            Text("Your logged lift sets will appear here grouped chronologically.")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundColor(.plGray500)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, 40)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 80)
                    } else {
                        LazyVStack(spacing: 16) {
                            ForEach(sessions) { session in
                                sessionCard(session: session)
                            }
                        }
                    }
                    
                }
                .padding(.horizontal, 16)
                .padding(.top, 16)
                .padding(.bottom, 100)
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    HStack(spacing: 2) {
                        Text("PRIVATE")
                            .font(.system(size: 24, weight: .black))
                            .foregroundColor(.primary)
                        Text("LIFT")
                            .font(.system(size: 24, weight: .black))
                            .foregroundColor(brandColors.blue)
                    }
                    .tracking(-0.5)
                }
            }
            .onAppear {
                if expandedSessionDate == nil, let firstSession = sessions.first {
                    expandedSessionDate = firstSession.dateString
                    sessionNotesText = firstSession.notes
                }
            }
            .plBackground(style: themeStyle)
            .alert("Confirm Set Deletion", isPresented: $showDeleteSetConfirmation) {
                Button("Delete", role: .destructive) {
                    if let set = setToDelete, let session = sessionToDeleteFrom {
                        deleteSet(set, in: session)
                    }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Are you sure you want to permanently delete this set?")
            }
            .alert("Confirm Session Deletion", isPresented: $showDeleteSessionConfirmation) {
                Button("Delete", role: .destructive) {
                    if let session = sessionToDelete {
                        deleteEntireSession(session)
                    }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Are you sure you want to permanently delete this entire workout session?")
            }
        }
    }
    
    // MARK: - Individual Session Card UI
    private func sessionCard(session: WorkoutSession) -> some View {
        let isExpanded = expandedSessionDate == session.dateString
        let totalVolume = session.sets.reduce(0.0) { $0 + ($1.weight * Double($1.reps)) }
        
        return VStack(alignment: .leading, spacing: 0) {
            // Header bar
            Button(action: {
                HapticService.play(.medium, enabled: activePrefs.hapticsEnabled)
                withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                    if isExpanded {
                        saveSessionNotes(session: session)
                        expandedSessionDate = nil
                    } else {
                        // Collapse previous, expand current
                        if let prevDate = expandedSessionDate,
                           let prevSession = sessions.first(where: { $0.dateString == prevDate }) {
                            saveSessionNotes(session: prevSession)
                        }
                        sessionNotesText = session.notes
                        expandedSessionDate = session.dateString
                    }
                }
            }) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(formatSessionDate(session.dateString))
                            .font(.system(size: 16, weight: .black))
                            .foregroundColor(brandColors.whiteText)
                        
                        HStack(spacing: 8) {
                            Text("\(session.sets.count) sets")
                                .font(.system(size: 11, weight: .black, design: .monospaced))
                                .foregroundColor(brandColors.blue)
                            
                            Text("•")
                                .font(.system(size: 11, weight: .black))
                                .foregroundColor(.plGray700)
                            
                            Text("\(Int(totalVolume)) \(activePrefs.weightUnit)")
                                .font(.system(size: 11, weight: .black, design: .monospaced))
                                .foregroundColor(.plGray400)
                        }
                    }
                    
                    Spacer()
                    
                    HStack(spacing: 12) {
                        // Exercise badges summary
                        HStack(spacing: 4) {
                            let loggedExercises = Array(Set(session.sets.map { $0.exercise })).sorted()
                            ForEach(loggedExercises, id: \.self) { exName in
                                if let ex = exercises.first(where: { $0.name == exName }) {
                                    let firstChar = String(ex.displayName.prefix(1)).uppercased()
                                    let badgeColor = themeStyle == .night ? Color.plGray400 : Color(hex: ex.colorHex)
                                    exerciseBadge(label: firstChar, color: badgeColor)
                                } else {
                                    let firstChar = String(exName.prefix(1)).uppercased()
                                    exerciseBadge(label: firstChar, color: .secondary)
                                }
                            }
                        }
                        
                        Image(systemName: "chevron.right")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundColor(.plGray500)
                            .rotationEffect(.degrees(isExpanded ? 90 : 0))
                    }
                }
                .padding(16)
            }
            
            // Expanded detail section
            if isExpanded {
                Divider()
                    .background(brandColors.whiteText.opacity(0.08))
                
                VStack(alignment: .leading, spacing: 14) {
                    
                    // Display set listings
                    VStack(spacing: 8) {
                        ForEach(session.sets) { item in
                            let rawColor = Color(hex: exercises.first(where: { $0.name == item.exercise })?.colorHex ?? "#8b5cf6")
                            let itemColor = themeStyle == .night ? Color.plGray400 : rawColor
                            HStack {
                                Text(item.exercise)
                                    .font(.system(size: 13, weight: .black))
                                    .foregroundColor(brandColors.whiteText)
                                    .frame(width: 80, alignment: .leading)
                                
                                Menu {
                                    Button("Warmup") {
                                        HapticService.play(.medium, enabled: activePrefs.hapticsEnabled)
                                        withAnimation {
                                            item.setType = "warmup"
                                            try? modelContext.save()
                                        }
                                    }
                                    Button("Working") {
                                        HapticService.play(.medium, enabled: activePrefs.hapticsEnabled)
                                        withAnimation {
                                            item.setType = "working"
                                            try? modelContext.save()
                                        }
                                    }
                                    Button("Failed") {
                                        HapticService.play(.medium, enabled: activePrefs.hapticsEnabled)
                                        withAnimation {
                                            item.setType = "failed"
                                            try? modelContext.save()
                                        }
                                    }
                                } label: {
                                    HStack(spacing: 2) {
                                        Text(item.setType == "drop" || item.setType == "failed" ? "FAILED" : item.setType.uppercased())
                                            .font(.system(size: 8, weight: .black))
                                            .foregroundColor(item.setType == "working" ? itemColor : .plGray400)
                                        Image(systemName: "chevron.up.chevron.down")
                                            .font(.system(size: 6, weight: .black))
                                            .foregroundColor(item.setType == "working" ? itemColor : .plGray400)
                                    }
                                }
                                .buttonStyle(PlainButtonStyle())
                                
                                Spacer()
                                
                                Text("\(Int(item.weight)) \(activePrefs.weightUnit) x \(item.reps)")
                                    .font(.system(size: 13, weight: .black, design: .monospaced))
                                    .foregroundColor(brandColors.whiteText)
                                
                                Menu {
                                    ForEach(Array(stride(from: 5.0, through: 10.0, by: 0.5)), id: \.self) { val in
                                        Button(String(format: "@ RPE %.1f", val)) {
                                            HapticService.play(.medium, enabled: activePrefs.hapticsEnabled)
                                            withAnimation {
                                                item.rpe = val
                                                try? modelContext.save()
                                            }
                                        }
                                    }
                                } label: {
                                    HStack(spacing: 3) {
                                        Text("@ RPE \(String(format: "%.1f", item.rpe))")
                                            .font(.system(size: 10, weight: .black, design: .monospaced))
                                            .foregroundColor(brandColors.purple)
                                        Image(systemName: "chevron.up.chevron.down")
                                            .font(.system(size: 7, weight: .black))
                                            .foregroundColor(brandColors.purple)
                                    }
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(brandColors.purple.opacity(0.15))
                                    .cornerRadius(4)
                                }
                                .buttonStyle(PlainButtonStyle())
                                
                                Button(action: {
                                     setToDelete = item
                                     sessionToDeleteFrom = session
                                     showDeleteSetConfirmation = true
                                 }) {
                                     Image(systemName: "xmark.circle.fill")
                                         .font(.system(size: 14))
                                         .foregroundColor(brandColors.red.opacity(0.7))
                                         .padding(.leading, 6)
                                 }
                            }
                            .padding(.vertical, 8)
                            .padding(.horizontal, 12)
                            .background(Color.black.opacity(0.2))
                            .cornerRadius(10)
                        }
                    }
                    
                    // Session Notes Editor
                    VStack(alignment: .leading, spacing: 6) {
                        Text("SESSION NOTES")
                            .font(.system(size: 9, weight: .black))
                            .foregroundColor(.plGray400)
                            .tracking(1.5)
                        
                        TextField("Enter notes, mood, templates, or accessories...", text: $sessionNotesText, axis: .vertical)
                            .font(.system(size: 13, weight: .bold))
                            .foregroundColor(brandColors.whiteText)
                            .padding(12)
                            .background(Color.black.opacity(0.3))
                            .cornerRadius(10)
                            .overlay(
                                RoundedRectangle(cornerRadius: 10)
                                    .stroke(brandColors.whiteText.opacity(0.08), lineWidth: 1.0)
                            )
                            .focused($isNotesFocused)
                    }
                    
                    // Bottom actions row (Delete entire session)
                    HStack {
                        Spacer()
                        Button(action: {
                            sessionToDelete = session
                            showDeleteSessionConfirmation = true
                        }) {
                            Label("DELETE WORKOUT SESSION", systemImage: "trash")
                                .font(.system(size: 10, weight: .black))
                                .foregroundColor(brandColors.red)
                        }
                    }
                    .padding(.top, 4)
                }
                .padding(16)
                .background(brandColors.whiteText.opacity(0.01))
            }
        }
        .glassCard(style: themeStyle)
    }
    
    private func exerciseBadge(label: String, color: Color) -> some View {
        Text(label)
            .font(.system(size: 9, weight: .black))
            .foregroundColor(themeStyle == .night ? .black : .white)
            .frame(width: 14, height: 14)
            .background(color)
            .cornerRadius(4)
            .shadow(color: color.opacity(0.2), radius: 2, y: 1)
    }
    
    // MARK: - Core Logic & Data Formatting
    private func formatSessionDate(_ rawString: String) -> String {
        let formatterInput = DateFormatter()
        formatterInput.dateFormat = "yyyy-MM-dd"
        if let tz = TimeZone(identifier: activePrefs.timeZoneIdentifier) {
            formatterInput.timeZone = tz
        }
        guard let date = formatterInput.date(from: rawString) else { return rawString }
        
        let formatterOutput = DateFormatter()
        formatterOutput.dateFormat = "EEEE, MMMM d, yyyy"
        if let tz = TimeZone(identifier: activePrefs.timeZoneIdentifier) {
            formatterOutput.timeZone = tz
        }
        return formatterOutput.string(from: date).uppercased()
    }
    
    private func saveSessionNotes(session: WorkoutSession) {
        if session.notes != sessionNotesText {
            session.notes = sessionNotesText
            try? modelContext.save()
        }
    }
    
    private func deleteSet(_ set: WorkoutSet, in session: WorkoutSession) {
        HapticService.play(.heavy, enabled: activePrefs.hapticsEnabled)
        
        withAnimation {
            // Delete set
            modelContext.delete(set)
            
            // If session becomes empty, delete session too
            if session.sets.count <= 1 { // SwiftData cache might not have updated count yet, check array directly
                modelContext.delete(session)
                expandedSessionDate = nil
            }
            
            try? modelContext.save()
        }
    }
    
    private func deleteEntireSession(_ session: WorkoutSession) {
        HapticService.play(.heavy, enabled: activePrefs.hapticsEnabled)
        
        withAnimation {
            modelContext.delete(session)
            expandedSessionDate = nil
            try? modelContext.save()
        }
    }
}
