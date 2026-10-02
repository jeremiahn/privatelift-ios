import SwiftUI
import SwiftData
import Charts

struct HistoryView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.colorScheme) private var colorScheme
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
    
    var uniqueExercises: [CustomExercise] {
        var seen = Set<String>()
        return exercises.filter { exercise in
            let normalized = exercise.name.uppercased().replacingOccurrences(of: " ", with: "")
            let key: String
            if normalized == "BENCH" || normalized == "BENCHPRESS" {
                key = "BENCH"
            } else if normalized == "SQUAT" {
                key = "SQUAT"
            } else if normalized == "DEADLIFT" {
                key = "DEADLIFT"
            } else {
                key = normalized
            }
            if seen.contains(key) {
                return false
            }
            seen.insert(key)
            return true
        }
    }
    
    var themeStyle: ThemeStyle {
        ThemeStyle(rawValue: activePrefs.theme) ?? .system
    }
    
    var brandColors: BrandColors {
        BrandColors(theme: themeStyle)
    }
    
    var isDark: Bool {
        switch themeStyle {
        case .light:
            return false
        case .dark, .night:
            return true
        case .system:
            return colorScheme == .dark
        }
    }
    
    var boxBackgroundColor: Color {
        isDark ? Color.black.opacity(0.2) : Color.plGray100
    }
    
    var notesBackgroundColor: Color {
        isDark ? Color.black.opacity(0.3) : Color.plGray100
    }
    
    // MARK: - e1RM Chart Data Structures
    struct ChartDataPoint: Identifiable {
        let id = UUID()
        let date: Date
        let liftName: String
        let e1RM: Double
    }
    
    private func makeDayFormatter() -> DateFormatter {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        if let tz = TimeZone(identifier: activePrefs.timeZoneIdentifier) {
            f.timeZone = tz
        }
        return f
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

        let formatter = makeDayFormatter()

        // Pre-build name -> displayName map for O(1) lookup in the loop below
        var displayNameMap: [String: String] = [:]
        for ex in uniqueExercises {
            displayNameMap[ex.name] = ex.displayName
        }

        var points: [ChartDataPoint] = []
        for dateStr in dailyMaxes.keys.sorted() {
            guard let date = formatter.date(from: dateStr),
                  let lifts = dailyMaxes[dateStr] else { continue }
            for (lift, val) in lifts {
                let displayName = displayNameMap[lift] ?? lift.capitalized
                points.append(ChartDataPoint(date: date, liftName: displayName, e1RM: val))
            }
        }
        return points
    }
    
    var chartColorScaleDomain: [String] {
        var domain = ["Squat", "Bench Press", "Deadlift"]
        for ex in uniqueExercises {
            if !domain.contains(ex.displayName) {
                domain.append(ex.displayName)
            }
        }
        for point in chartPoints {
            if !domain.contains(point.liftName) {
                domain.append(point.liftName)
            }
        }
        return domain
    }
    
    var chartColorScaleRange: [Color] {
        let domain = chartColorScaleDomain
        var scale: [String: Color] = [
            "Squat": brandColors.red,
            "Bench Press": brandColors.blue,
            "Deadlift": brandColors.green
        ]
        for ex in uniqueExercises {
            scale[ex.displayName] = themeStyle == .night ? Color.plGray400 : Color(hex: ex.colorHex)
        }
        return domain.map { liftName in
            scale[liftName] ?? (themeStyle == .night ? Color.plGray400 : brandColors.blue)
        }
    }
    
    private func calculateE1RM(weight: Double, reps: Int, formula: String) -> Double {
        if reps <= 1 { return weight }
        switch formula {
        case "brzycki":
            let denom = 1.0278 - (0.0278 * Double(reps))
            return weight / max(0.01, denom)
        case "lander":
            let denom = 101.3 - (2.6712 * Double(reps))
            return (100.0 * weight) / max(0.01, denom)
        default: // epley
            return weight * (1.0 + Double(reps) / 30.0)
        }
    }
    
    @ViewBuilder
    private var progressionChartCard: some View {
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
                .chartForegroundStyleScale(domain: chartColorScaleDomain, range: chartColorScaleRange)
                .frame(height: 220)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Estimated 1RM Progression Chart")
                .accessibilityValue(chartPoints.isEmpty ? "No data available." : "Showing 1RM trends over time for your lifts.")
            }
        }
        .padding(20)
        .glassCard(style: themeStyle)
    }
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    
                    // e1RM Progression Swift Chart Card
                    progressionChartCard
                    
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
                        Text("PERSONAL")
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
        let totalVolume = (session.sets ?? []).reduce(0.0) { $0 + ($1.weight * Double($1.reps)) }
        
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
                            Text("\((session.sets ?? []).count) sets")
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
                            let loggedExercises = Array(Set((session.sets ?? []).map { $0.exercise })).sorted()
                            ForEach(loggedExercises, id: \.self) { exName in
                                if let ex = uniqueExercises.first(where: { $0.name == exName }) {
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
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(formatSessionDate(session.dateString)) workout session")
            .accessibilityValue("\((session.sets ?? []).count) sets, total volume \(Int(totalVolume)) \(activePrefs.weightUnit). Exercises completed: \(Array(Set((session.sets ?? []).map { item in uniqueExercises.first(where: { $0.name == item.exercise })?.displayName ?? item.exercise })).joined(separator: ", "))")
            .accessibilityHint(isExpanded ? "Double tap to collapse details" : "Double tap to expand details")
            
            // Expanded detail section
            if isExpanded {
                Divider()
                    .background(brandColors.whiteText.opacity(0.08))
                
                VStack(alignment: .leading, spacing: 14) {
                    
                    // Display set listings
                    VStack(spacing: 8) {
                        ForEach(session.sets ?? []) { item in
                            let rawColor = Color(hex: uniqueExercises.first(where: { $0.name == item.exercise })?.colorHex ?? "#8b5cf6")
                            let itemColor = themeStyle == .night ? Color.plGray400 : rawColor
                            HStack {
                                Text(item.exercise)
                                    .font(.system(size: 13, weight: .black))
                                    .foregroundColor(brandColors.whiteText)
                                    .frame(width: 80, alignment: .leading)
                                    .accessibilityLabel(uniqueExercises.first(where: { $0.name == item.exercise })?.displayName ?? item.exercise)
                                
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
                                .accessibilityLabel("Set type")
                                .accessibilityValue(item.setType == "drop" || item.setType == "failed" ? "failed" : item.setType)
                                .accessibilityHint("Double tap to change set type")
                                
                                Spacer()
                                
                                Text("\(Int(item.weight)) \(activePrefs.weightUnit) x \(item.reps)")
                                    .font(.system(size: 13, weight: .black, design: .monospaced))
                                    .foregroundColor(brandColors.whiteText)
                                    .accessibilityLabel("Weight and reps")
                                    .accessibilityValue("\(Int(item.weight)) \(activePrefs.weightUnit) for \(item.reps) repetitions")
                                
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
                                .accessibilityLabel("Rate of perceived exertion")
                                .accessibilityValue("RPE \(String(format: "%.1f", item.rpe))")
                                .accessibilityHint("Double tap to change RPE value")
                                
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
                                 .accessibilityLabel("Delete set")
                                 .accessibilityHint("Double tap to permanently remove this set from history")
                            }
                            .padding(.vertical, 8)
                            .padding(.horizontal, 12)
                            .background(boxBackgroundColor)
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
                            .background(notesBackgroundColor)
                            .cornerRadius(10)
                            .overlay(
                                RoundedRectangle(cornerRadius: 10)
                                    .stroke(brandColors.whiteText.opacity(0.08), lineWidth: 1.0)
                            )
                            .focused($isNotesFocused)
                            .accessibilityLabel("Session notes")
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
                        .accessibilityLabel("Delete entire workout session")
                        .accessibilityHint("Permanently deletes this entire workout session from your logs")
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
            if (session.sets ?? []).count <= 1 { // SwiftData cache might not have updated count yet, check array directly
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
