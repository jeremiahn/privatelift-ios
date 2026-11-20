import SwiftUI
import SwiftData

struct DashboardView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var preferences: [UserPreferences]
    
    // Fetch all sessions to access today's notes
    @Query private var allSessions: [WorkoutSession]
    
    // Fetch dynamic exercises
    @Query(sort: \CustomExercise.orderIndex) private var exercises: [CustomExercise]
    
    @ObservedObject var timerManager: RestTimerManager
    @ObservedObject var healthService: HealthKitService
    
    @State private var intensity: Double = 85.0
    
    // Log Form Fields
    @AppStorage("dashboard.selectedExercise") private var selectedExercise = "SQUAT"
    @AppStorage("dashboard.selectedSetType") private var selectedSetType = "working"
    @AppStorage("dashboard.weightInput") private var weightInput = ""
    @AppStorage("dashboard.repsInput") private var repsInput = "5"
    @AppStorage("dashboard.rpeInput") private var rpeInput = 8.0
    
    // Calculator Field
    @State private var calcWeight = 225.0
    /// Exercise whose bar the plate calculator uses; nil follows the selected exercise.
    @State private var calcExercise: String? = nil
    /// Scroll target; only set by the DEBUG `-screenshotScroll log|today|plates` launch argument.
    @State private var scrollTarget: String? = nil
    @FocusState private var isFieldFocused: Bool
    
    @State private var pendingUndo: DeletedSet? = nil
    /// Bumped after a log, delete or undo so `lastSetForSelected` (a direct fetch) re-runs.
    @State private var refreshToken = 0

    private struct DeletedSet {
        let id = UUID()
        let exercise: String
        let weight: Double
        let reps: Int
        let rpe: Double
        let setType: String
        let timestamp: Date
        let session: WorkoutSession?
    }
    
    var activePrefs: UserPreferences {
        preferences.first ?? UserPreferences()
    }
    
    var uniqueExercises: [CustomExercise] { exercises.uniqued }
    
    private func makeDayFormatter() -> DateFormatter {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        if let timeZone = TimeZone(identifier: activePrefs.timeZoneIdentifier) {
            f.timeZone = timeZone
        }
        return f
    }

    var todayString: String {
        return makeDayFormatter().string(from: Date())
    }
    
    var todaySets: [WorkoutSet] {
        (todaySession?.sets ?? []).sorted { $0.timestamp < $1.timestamp }
    }
    
    var todaySession: WorkoutSession? {
        let dateStr = todayString
        return allSessions.first { $0.dateString == dateStr }
    }
    
    var todayNotesBinding: Binding<String> {
        Binding(
            get: { todaySession?.notes ?? "" },
            set: { newValue in
                fetchOrCreateTodaySession().notes = newValue
                try? modelContext.save()
            }
        )
    }
    
    // Target weight for an exercise at the current intensity, rounded to a loadable plate step
    private func calculateTargetWeight(for exerciseName: String) -> Double {
        let max = exercises.first(where: { $0.name == exerciseName })?.oneRepMax ?? 0.0
        return LiftMath.target(oneRepMax: max, percent: intensity, unit: activePrefs.weightUnit, bar: barWeight(for: exerciseName))
    }

    /// Exercise override, else the Settings bar, else a standard bar for the unit.
    private func barWeight(for exerciseName: String) -> Double {
        exercises.first(where: { $0.name == exerciseName })?.barWeight
            ?? activePrefs.barWeight
            ?? LiftMath.barWeight(unit: activePrefs.weightUnit)
    }

    private var calcBar: Double { barWeight(for: calcExercise ?? selectedExercise) }
    
    var themeStyle: ThemeStyle {
        ThemeStyle(rawValue: activePrefs.theme) ?? .system
    }
    
    var brandColors: BrandColors {
        BrandColors(theme: themeStyle)
    }
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    
                    // 1. Intensity Header Card
                    VStack(alignment: .leading, spacing: 16) {
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("WEEKLY PROGRAM")
                                    .scaledFont(size: 11, weight: .black)
                                    .foregroundColor(brandColors.blue)
                                    .tracking(2.0)
                                
                                Text("Target Intensity: \(Int(intensity))%")
                                    .scaledFont(size: 22, weight: .black)
                                    .foregroundColor(brandColors.whiteText)
                            }
                            Spacer()
                        }
                        
                        Slider(value: $intensity, in: 50...100, step: 5)
                            .tint(brandColors.blue)
                            .onChange(of: intensity) { oldValue, newValue in
                                HapticService.play(.medium, enabled: activePrefs.hapticsEnabled)
                                activePrefs.lastIntensity = Int(newValue)
                                updateWeightInputForSelectedExercise()
                            }
                            .accessibilityLabel("Target intensity percentage")
                            .accessibilityValue("\(Int(intensity)) percent")
                    }
                    .padding(20)
                    .glassCard(style: themeStyle)
                    
                    // 2. Program Targets Row (Dynamic Custom Exercises)
                    programTargetsSection
                    
                    // 3. Log New Set Form
                    VStack(alignment: .leading, spacing: 16) {
                        Text("Log New Set")
                            .scaledFont(size: 15, weight: .black)
                            .foregroundColor(brandColors.purple)
                            .tracking(2.0)
                        
                        VStack(spacing: 14) {
                            // Exercise pills row (Dynamic)
                            VStack(alignment: .leading, spacing: 6) {
                                Text("EXERCISE")
                                    .scaledFont(size: 9, weight: .black)
                                    .foregroundColor(.plSecondaryLabel)
                                    .tracking(1.5)
                                
                                exerciseSelectionSection
                            }
                            .padding(.bottom, 4)
                            
                            // Set Type pills row
                            VStack(alignment: .leading, spacing: 6) {
                                Text("SET TYPE")
                                    .scaledFont(size: 9, weight: .black)
                                    .foregroundColor(.plSecondaryLabel)
                                    .tracking(1.5)
                                
                                HStack(spacing: 8) {
                                    setTypePill(title: "Warmup", tag: "warmup", activeColor: brandColors.purple)
                                    setTypePill(title: "Working", tag: "working", activeColor: brandColors.purple)
                                    setTypePill(title: "Failed", tag: "failed", activeColor: brandColors.purple)
                                }
                            }
                            
                            // Weight + Reps textfields (tap -/+ for a plate step, long press for a fine step)
                            HStack(spacing: 12) {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Weight (\(activePrefs.weightUnit.uppercased()))")
                                        .scaledFont(size: 9, weight: .black)
                                        .foregroundColor(.plSecondaryLabel)
                                    HStack(spacing: 4) {
                                        stepButton("minus", label: "Decrease weight", height: 48) { fine in
                                            adjustWeight(direction: -1, fine: fine)
                                        }

                                        TextField("0", text: $weightInput)
                                            .focused($isFieldFocused)
                                            .keyboardType(.decimalPad)
                                            .font(.system(.body, design: .monospaced))
                                            .fontWeight(.black)
                                            .foregroundColor(brandColors.whiteText)
                                            .multilineTextAlignment(.center)
                                            .frame(height: 48)
                                            .background(brandColors.whiteText.opacity(0.04))
                                            .cornerRadius(8)
                                            .overlay(
                                                RoundedRectangle(cornerRadius: 8)
                                                    .stroke(brandColors.whiteText.opacity(0.08), lineWidth: 1.5)
                                            )
                                            .accessibilityLabel("Weight")
                                            .accessibilityValue("\(weightInput) \(activePrefs.weightUnit)")

                                        stepButton("plus", label: "Increase weight", height: 48) { fine in
                                            adjustWeight(direction: 1, fine: fine)
                                        }
                                    }
                                }

                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Reps")
                                        .scaledFont(size: 9, weight: .black)
                                        .foregroundColor(.plSecondaryLabel)
                                    HStack(spacing: 4) {
                                        stepButton("minus", label: "Decrease reps", height: 48) { fine in
                                            adjustReps(by: -1, fine: fine)
                                        }

                                        TextField("5", text: $repsInput)
                                            .focused($isFieldFocused)
                                            .keyboardType(.numberPad)
                                            .font(.system(.body, design: .monospaced))
                                            .fontWeight(.bold)
                                            .foregroundColor(brandColors.whiteText)
                                            .multilineTextAlignment(.center)
                                            .frame(height: 48)
                                            .background(brandColors.whiteText.opacity(0.04))
                                            .cornerRadius(8)
                                            .overlay(
                                                RoundedRectangle(cornerRadius: 8)
                                                    .stroke(brandColors.whiteText.opacity(0.08), lineWidth: 1.5)
                                            )
                                            .accessibilityLabel("Reps")
                                            .accessibilityValue("\(repsInput)")

                                        stepButton("plus", label: "Increase reps", height: 48) { fine in
                                            adjustReps(by: 1, fine: fine)
                                        }
                                    }
                                }
                            }
                            
                            // RPE Selector
                            VStack(alignment: .leading, spacing: 6) {
                                HStack {
                                    Text("RPE (Intensity of effort)")
                                        .scaledFont(size: 12, weight: .black)
                                        .foregroundColor(.plSecondaryLabel)
                                    Spacer()
                                    Text(String(format: "@ %.1f", rpeInput))
                                        .font(.system(.caption, design: .monospaced))
                                        .fontWeight(.black)
                                        .foregroundColor(brandColors.purple)
                                }
                                
                                Slider(value: $rpeInput, in: 5...10, step: 0.5)
                                    .tint(brandColors.purple)
                                    .accessibilityLabel("RPE rating")
                                    .accessibilityValue(String(format: "%.1f", rpeInput))
                            }
                            
                            lastTimeRow

                            // Save Button
                            Button(action: saveLoggedSet) {
                                HStack {
                                    Image(systemName: "plus.circle.fill")
                                    Text("Log Completed Set")
                                        .scaledFont(size: 12, weight: .black)
                                        .tracking(1.5)
                                }
                                .foregroundColor(themeStyle == .night ? .black : .white)
                                .frame(maxWidth: .infinity)
                                .frame(height: 48)
                                .background(brandColors.purple)
                                .cornerRadius(12)
                                .shadow(color: brandColors.purple.opacity(0.3), radius: 8, y: 4)
                            }
                            .accessibilityLabel("Log Completed Set")
                            .accessibilityHint("Saves this workout set to your log database")
                            .padding(.top, 8)
                        }
                    }
                    .padding(20)
                    .glassCard(style: themeStyle)
                    .id("log")
                    
                    // 4. Today's Logs List
                    todayLogSection
                        .id("today")

                    // 5. Barbell Plate Calculator Widget
                    VStack(alignment: .leading, spacing: 16) {
                        Text("PLATE CALCULATOR")
                            .scaledFont(size: 11, weight: .black)
                            .foregroundColor(brandColors.teal)
                            .tracking(2.0)
                        
                        plateCalculatorAutofillSection
                        .padding(.bottom, 4)
                        
                        VStack(spacing: 20) {
                            HStack {
                                Text("BAR LOAD WEIGHT:")
                                    .scaledFont(size: 9, weight: .black)
                                    .foregroundColor(.plSecondaryLabel)
                                    .tracking(1.0)
                                
                                HStack(spacing: 4) {
                                    stepButton("minus", label: "Decrease calculator weight", height: 52) { fine in
                                        adjustCalcWeight(direction: -1, fine: fine)
                                    }
                                    
                                    TextField("Weight", value: $calcWeight, format: .number.precision(.fractionLength(0...2)))
                                        .focused($isFieldFocused)
                                        .keyboardType(.decimalPad)
                                        .font(.system(.title2, design: .monospaced))
                                        .fontWeight(.black)
                                        .foregroundColor(brandColors.whiteText)
                                        .multilineTextAlignment(.center)
                                        .frame(height: 52)
                                        .background(brandColors.whiteText.opacity(0.04))
                                        .cornerRadius(8)
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 8)
                                                .stroke(brandColors.whiteText.opacity(0.08), lineWidth: 1.5)
                                        )
                                        .accessibilityLabel("Plate calculator weight")
                                        .accessibilityValue("\(LiftMath.format(calcWeight)) \(activePrefs.weightUnit)")
                                    
                                    stepButton("plus", label: "Increase calculator weight", height: 52) { fine in
                                        adjustCalcWeight(direction: 1, fine: fine)
                                    }
                                }
                                    
                                Text(activePrefs.weightUnit.uppercased())
                                    .scaledFont(size: 12, weight: .black)
                                    .foregroundColor(.plSecondaryLabel)
                            }
                            
                            // Visual Barbell Drawing
                            BarbellPlateGraphic(weight: calcWeight, bar: calcBar, isLbs: activePrefs.weightUnit == "lbs", isNight: themeStyle == .night)
                                .frame(height: 120)

                            plateLoadNote
                        }
                    }
                    .padding(20)
                    .glassCard(style: themeStyle)
                    .id("plates")
                    
                    
                }
                .padding(.horizontal, 16)
                .padding(.top, 16)
                .padding(.bottom, 100) // Padding for Rest Timer + Tabbar
                .scrollTargetLayout()
                .plReadableWidth()
            }
            .scrollPosition(id: $scrollTarget, anchor: .top)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    PLWordmark(accent: brandColors.blue)
                }
                
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") {
                        isFieldFocused = false
                    }
                }
            }
            .plBackground(style: themeStyle)
            .onAppear {
                #if DEBUG
                if let target = UserDefaults.standard.string(forKey: "screenshotScroll") {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { scrollTarget = target }
                }
                #endif
                // Initialize default intensity
                intensity = Double(activePrefs.lastIntensity)
                if let firstExercise = uniqueExercises.first, !uniqueExercises.contains(where: { $0.name == selectedExercise }) {
                    selectedExercise = firstExercise.name
                }
                if weightInput.isEmpty {
                    updateWeightInputForSelectedExercise()
                }
            }
            .onChange(of: uniqueExercises) { oldValue, newValue in
                if let firstExercise = newValue.first, !newValue.contains(where: { $0.name == selectedExercise }) {
                    selectedExercise = firstExercise.name
                    updateWeightInputForSelectedExercise()
                }
            }
            .onChange(of: weightInput) { oldValue, newValue in
                if let parsed = LiftMath.parse(newValue) {
                    calcWeight = parsed
                } else if newValue.isEmpty {
                    calcWeight = 0.0
                }
            }
            .onChange(of: selectedExercise) { _, _ in calcExercise = nil }
            .overlay(alignment: .bottom) { undoToast }
        }
    }
    
    @ViewBuilder
    private var programTargetsSection: some View {
        if activePrefs.useGridMode {
            VStack(spacing: 12) {
                let chunks = chunkedExercises(by: 2)
                ForEach(0..<chunks.count, id: \.self) { index in
                    let chunk = chunks[index]
                    HStack(spacing: 12) {
                        ForEach(chunk) { exercise in
                            TargetCard(
                                title: exercise.displayName,
                                weight: calculateTargetWeight(for: exercise.name),
                                unit: activePrefs.weightUnit,
                                color: themeStyle == .night ? .plGray300 : Color(hex: exercise.colorHex),
                                whiteText: brandColors.whiteText,
                                isSelected: selectedExercise == exercise.name,
                                isSquare: false
                            ) {
                                HapticService.play(.medium, enabled: activePrefs.hapticsEnabled)
                                selectedExercise = exercise.name
                                updateWeightInputForSelectedExercise()
                                calcWeight = calculateTargetWeight(for: exercise.name)
                            }
                            .frame(minWidth: 125, maxWidth: .infinity)
                        }
                    }
                }
            }
            .padding(.horizontal, 16)
        } else {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(uniqueExercises) { exercise in
                        TargetCard(
                            title: exercise.displayName,
                            weight: calculateTargetWeight(for: exercise.name),
                            unit: activePrefs.weightUnit,
                            color: themeStyle == .night ? .plGray300 : Color(hex: exercise.colorHex),
                            whiteText: brandColors.whiteText,
                            isSelected: selectedExercise == exercise.name,
                            isSquare: false
                        ) {
                            HapticService.play(.medium, enabled: activePrefs.hapticsEnabled)
                            selectedExercise = exercise.name
                            updateWeightInputForSelectedExercise()
                            calcWeight = calculateTargetWeight(for: exercise.name)
                        }
                        .frame(minWidth: 125, maxWidth: .infinity)
                    }
                }
                .padding(.horizontal, 16)
            }
        }
    }
    
    @ViewBuilder
    private var exerciseSelectionSection: some View {
        if activePrefs.useGridMode {
            VStack(spacing: 8) {
                let chunks = chunkedExercises(by: 3)
                ForEach(0..<chunks.count, id: \.self) { index in
                    let chunk = chunks[index]
                    HStack(spacing: 8) {
                        ForEach(chunk) { exercise in
                            exercisePill(title: exercise.displayName, tag: exercise.name, activeColor: Color(hex: exercise.colorHex), isSquare: false)
                        }
                    }
                }
            }
        } else {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(uniqueExercises) { exercise in
                        exercisePill(title: exercise.displayName, tag: exercise.name, activeColor: Color(hex: exercise.colorHex), isSquare: false)
                    }
                }
            }
        }
    }
    
    @ViewBuilder
    private var plateCalculatorAutofillSection: some View {
        if activePrefs.useGridMode {
            VStack(spacing: 10) {
                let chunks = chunkedExercises(by: 3)
                ForEach(0..<chunks.count, id: \.self) { index in
                    let chunk = chunks[index]
                    HStack(spacing: 10) {
                        ForEach(chunk) { exercise in
                            plateAutofillButton(exercise: exercise.displayName, name: exercise.name, value: calculateTargetWeight(for: exercise.name), isSquare: false)
                                .frame(minWidth: 95, maxWidth: .infinity, minHeight: 48, maxHeight: .infinity)
                        }
                    }
                }
            }
        } else {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(uniqueExercises) { exercise in
                        plateAutofillButton(exercise: exercise.displayName, name: exercise.name, value: calculateTargetWeight(for: exercise.name), isSquare: false)
                            .frame(minWidth: 95, maxWidth: .infinity, minHeight: 48, maxHeight: .infinity)
                    }
                }
            }
        }
    }
    
    private func plateAutofillButton(exercise: String, name: String, value: Double, isSquare: Bool = false) -> some View {
        Button(action: {
            HapticService.play(.medium, enabled: activePrefs.hapticsEnabled)
            calcWeight = value
            calcExercise = name
        }) {
            VStack(spacing: 2) {
                Spacer(minLength: 0)
                Text(exercise.uppercased())
                    .scaledFont(size: 8, weight: .black)
                    .foregroundColor(brandColors.whiteText)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 4)
                
                Spacer(minLength: 0)
                Text(LiftMath.format(value))
                    .scaledFont(size: 11, weight: .black, design: .monospaced)
                    .foregroundColor(brandColors.teal)
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(brandColors.teal.opacity(0.2))
            .cornerRadius(6)
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(brandColors.teal.opacity(0.3), lineWidth: 1.0)
            )
        }
        .accessibilityLabel("Autofill weight for \(exercise)")
        .accessibilityValue("\(LiftMath.format(value)) \(activePrefs.weightUnit)")
        .accessibilityHint("Loads \(LiftMath.format(value)) \(activePrefs.weightUnit) into the plate calculator")
    }
    
    private func chunkedExercises(by size: Int) -> [[CustomExercise]] {
        var chunks: [[CustomExercise]] = []
        var currentChunk: [CustomExercise] = []
        for exercise in uniqueExercises {
            currentChunk.append(exercise)
            if currentChunk.count == size {
                chunks.append(currentChunk)
                currentChunk = []
            }
        }
        if !currentChunk.isEmpty {
            chunks.append(currentChunk)
        }
        return chunks
    }
    
    private func updateWeightInputForSelectedExercise() {
        weightInput = inputString(calculateTargetWeight(for: selectedExercise))
    }

    /// Field text for a weight: POSIX "%g" so `LiftMath.parse` always reads it back.
    private func inputString(_ value: Double) -> String {
        String(format: "%g", (value * 100).rounded() / 100)
    }

    private func fetchOrCreateTodaySession() -> WorkoutSession {
        if let session = todaySession { return session }
        let dateStr = todayString
        let fetch = FetchDescriptor<WorkoutSession>(predicate: #Predicate { $0.dateString == dateStr })
        if let existing = try? modelContext.fetch(fetch).first { return existing }
        let session = WorkoutSession(dateString: dateStr)
        modelContext.insert(session)
        return session
    }

    private func syncHealth(_ session: WorkoutSession?) {
        guard activePrefs.appleHealthEnabled, let session else { return }
        healthService.syncSession(dateString: session.dateString, sets: session.sets ?? [], unit: activePrefs.weightUnit)
    }

    private func saveLoggedSet() {
        guard let weight = LiftMath.parse(weightInput), weight >= 0, weight <= 2000,
              let reps = Int(repsInput.trimmingCharacters(in: .whitespaces)), reps > 0, reps <= 1000 else {
            HapticService.play(.error, enabled: activePrefs.hapticsEnabled)
            return
        }

        do {
            let session = fetchOrCreateTodaySession()
            let newSet = WorkoutSet(
                exercise: selectedExercise,
                weight: weight,
                reps: reps,
                rpe: rpeInput,
                setType: selectedSetType
            )
            newSet.session = session
            modelContext.insert(newSet)
            try modelContext.save()
            refreshToken += 1

            syncHealth(session)
            HapticService.play(.success, enabled: activePrefs.hapticsEnabled)

            if activePrefs.showRestTimer {
                timerManager.startTimer(
                    // Per-exercise rest (e.g. 4:00 after deadlifts) falls back to the Settings default.
                    duration: exercises.first(where: { $0.name == selectedExercise })?.restSeconds ?? activePrefs.defaultRestDuration,
                    allowNotifications: activePrefs.pushNotificationsEnabled,
                    hapticsEnabled: activePrefs.hapticsEnabled
                )
            }
        } catch {
            debugLog("Failed to save logged set: \(error)")
        }
    }

    /// Deletes immediately and offers Undo for 5 seconds instead of a confirmation alert.
    private func deleteSet(_ set: WorkoutSet) {
        HapticService.play(.heavy, enabled: activePrefs.hapticsEnabled)
        let snapshot = DeletedSet(
            exercise: set.exercise, weight: set.weight, reps: set.reps, rpe: set.rpe,
            setType: set.setType, timestamp: set.timestamp, session: set.session
        )
        withAnimation {
            modelContext.delete(set)
            try? modelContext.save()
            pendingUndo = snapshot
        }
        refreshToken += 1
        syncHealth(snapshot.session)
    }

    private func restoreDeletedSet() {
        guard let undo = pendingUndo else { return }
        HapticService.play(.medium, enabled: activePrefs.hapticsEnabled)
        let restored = WorkoutSet(
            exercise: undo.exercise, weight: undo.weight, reps: undo.reps,
            rpe: undo.rpe, setType: undo.setType, timestamp: undo.timestamp
        )
        withAnimation {
            restored.session = undo.session ?? fetchOrCreateTodaySession()
            modelContext.insert(restored)
            try? modelContext.save()
            pendingUndo = nil
        }
        refreshToken += 1
        syncHealth(restored.session)
    }

    private func adjustWeight(direction: Double, fine: Bool) {
        HapticService.play(.medium, enabled: activePrefs.hapticsEnabled)
        let unit = activePrefs.weightUnit
        let step = fine ? LiftMath.fineStep(unit: unit) : LiftMath.plateStep(unit: unit)
        weightInput = inputString(max(0, (LiftMath.parse(weightInput) ?? 0) + direction * step))
    }

    private func adjustCalcWeight(direction: Double, fine: Bool) {
        HapticService.play(.medium, enabled: activePrefs.hapticsEnabled)
        let unit = activePrefs.weightUnit
        let step = fine ? LiftMath.fineStep(unit: unit) : LiftMath.plateStep(unit: unit)
        calcWeight = max(0, calcWeight + direction * step)
    }

    private func adjustReps(by delta: Int, fine: Bool) {
        HapticService.play(.medium, enabled: activePrefs.hapticsEnabled)
        repsInput = "\(max(1, (Int(repsInput) ?? 0) + delta))"
    }

    /// Tap runs `action(false)`; long press runs `action(true)` (fine step). VoiceOver gets both.
    private func stepButton(_ systemImage: String, label: String, height: CGFloat, action: @escaping (_ fine: Bool) -> Void) -> some View {
        Image(systemName: systemImage)
            .scaledFont(size: 12, weight: .bold)
            .foregroundColor(brandColors.whiteText)
            .frame(width: 40, height: height)
            .background(brandColors.whiteText.opacity(0.04))
            .cornerRadius(8)
            .contentShape(Rectangle())
            .onTapGesture { action(false) }
            .onLongPressGesture(minimumDuration: 0.4) { action(true) }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(label)
            .accessibilityAddTraits(.isButton)
            .accessibilityHint("Long press for a smaller step")
            .accessibilityAction { action(false) }
            .accessibilityAction(named: "Small step") { action(true) }
    }

    // MARK: - Last Time / Repeat

    /// Today: the previous set of the selected exercise, whatever its type. Earlier days:
    /// the last working set (warmups aren't what you'd repeat), else the last set of any type.
    /// Limit-1 fetches instead of querying every set.
    private var lastSetForSelected: WorkoutSet? {
        _ = refreshToken
        let name = selectedExercise
        var any = FetchDescriptor<WorkoutSet>(
            predicate: #Predicate { $0.exercise == name },
            sortBy: [SortDescriptor(\.timestamp, order: .reverse)]
        )
        any.fetchLimit = 1
        guard let latest = try? modelContext.fetch(any).first else { return nil }
        if latest.session?.dateString == todayString || latest.setType == "working" { return latest }
        var working = FetchDescriptor<WorkoutSet>(
            predicate: #Predicate { $0.exercise == name && $0.setType == "working" },
            sortBy: [SortDescriptor(\.timestamp, order: .reverse)]
        )
        working.fetchLimit = 1
        return (try? modelContext.fetch(working).first) ?? latest
    }

    @ViewBuilder
    private var lastTimeRow: some View {
        if let last = lastSetForSelected {
            let isToday = last.session?.dateString == todayString
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(isToday ? "PREVIOUS SET" : "LAST TIME")
                        .scaledFont(size: 9, weight: .black)
                        .foregroundColor(.plSecondaryLabel)
                        .tracking(1.5)
                    Text(lastSetSummary(last, includeDate: !isToday))
                        .scaledFont(size: 13, weight: .black, design: .monospaced)
                        .foregroundColor(brandColors.whiteText)
                }
                Spacer()
                Button {
                    repeatSet(last)
                } label: {
                    Label("Repeat", systemImage: "arrow.counterclockwise")
                        .scaledFont(size: 12, weight: .black)
                        .foregroundColor(brandColors.purple)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                        .background(brandColors.purple.opacity(0.15))
                        .cornerRadius(10)
                }
                .buttonStyle(.plain)
                .accessibilityHint("Fills the form with this set's weight, reps, and RPE")
            }
            .padding(12)
            .background(brandColors.whiteText.opacity(0.04))
            .cornerRadius(12)
        }
    }

    private func lastSetSummary(_ set: WorkoutSet, includeDate: Bool) -> String {
        var text = "\(LiftMath.format(set.weight)) \(activePrefs.weightUnit) × \(set.reps) @ \(String(format: "%.1f", set.rpe))"
        if includeDate, let date = set.session?.date {
            text += " · " + date.formatted(.dateTime.month(.abbreviated).day())
        }
        return text
    }

    private func repeatSet(_ set: WorkoutSet) {
        HapticService.play(.medium, enabled: activePrefs.hapticsEnabled)
        weightInput = inputString(set.weight)
        repsInput = "\(set.reps)"
        rpeInput = set.rpe
        selectedSetType = (set.setType == "failed" || set.setType == "drop") ? "working" : set.setType
    }

    // MARK: - Today's Log

    private var todayLogSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("TODAY'S WORKOUT LOG")
                    .scaledFont(size: 11, weight: .black)
                    .foregroundColor(brandColors.green)
                    .tracking(2.0)
                Spacer()
                if activePrefs.appleHealthEnabled {
                    HStack(spacing: 4) {
                        Image(systemName: "heart.fill")
                            .scaledFont(size: 8)
                            .foregroundColor(.plRed)
                        Text("Apple Health")
                            .scaledFont(size: 9, weight: .bold)
                            .foregroundColor(.plSecondaryLabel)
                    }
                }
            }

            VStack(spacing: 12) {
                if todaySets.isEmpty {
                    Text("No sets logged yet today.")
                        .scaledFont(size: 12, weight: .bold)
                        .foregroundColor(.plSecondaryLabel)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                ForEach(todaySets) { loggedSet in
                    todaySetRow(loggedSet)
                }

                Divider()
                    .background(brandColors.whiteText.opacity(0.08))
                    .padding(.vertical, 8)

                VStack(alignment: .leading, spacing: 6) {
                    Text("TODAY'S SESSION NOTES")
                        .scaledFont(size: 9, weight: .black)
                        .foregroundColor(.plSecondaryLabel)
                        .tracking(1.5)

                    TextField("Enter notes, mood, accessories...", text: todayNotesBinding, axis: .vertical)
                        .scaledFont(size: 13, weight: .bold)
                        .foregroundColor(brandColors.whiteText)
                        .padding(12)
                        .background(Color.black.opacity(themeStyle == .night ? 0.4 : 0.2))
                        .cornerRadius(10)
                        .overlay(
                            RoundedRectangle(cornerRadius: 10)
                                .stroke(brandColors.whiteText.opacity(0.08), lineWidth: 1.0)
                        )
                        .accessibilityLabel("Today's session notes")
                }
            }
        }
        .padding(20)
        .glassCard(style: themeStyle)
    }

    private func todaySetRow(_ loggedSet: WorkoutSet) -> some View {
        let matchedExercise = exercises.first(where: { $0.name == loggedSet.exercise })
        let rawColor = Color(hex: matchedExercise?.colorHex ?? "#8b5cf6")
        let exerciseColor = themeStyle == .night ? Color.plGray300 : rawColor
        let typeColor = loggedSet.setType == "working" ? exerciseColor : Color.plSecondaryLabel
        let typeLabel = (loggedSet.setType == "drop" || loggedSet.setType == "failed") ? "FAILED" : loggedSet.setType.uppercased()

        return HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(matchedExercise?.displayName ?? loggedSet.exercise)
                    .scaledFont(size: 14, weight: .black)
                    .foregroundColor(brandColors.whiteText)
                Menu {
                    ForEach([("Warmup", "warmup"), ("Working", "working"), ("Failed", "failed")], id: \.1) { title, tag in
                        Button(title) {
                            HapticService.play(.medium, enabled: activePrefs.hapticsEnabled)
                            withAnimation {
                                loggedSet.setType = tag
                                try? modelContext.save()
                            }
                        }
                    }
                } label: {
                    HStack(spacing: 2) {
                        Text("\(typeLabel) SET")
                            .scaledFont(size: 9, weight: .black)
                        Image(systemName: "chevron.up.chevron.down")
                            .scaledFont(size: 7, weight: .black)
                    }
                    .foregroundColor(typeColor)
                }
                .buttonStyle(PlainButtonStyle())
                .accessibilityLabel("Set type")
                .accessibilityValue(typeLabel.lowercased())
            }

            Spacer()

            HStack(spacing: 8) {
                Text("\(LiftMath.format(loggedSet.weight)) \(activePrefs.weightUnit)")
                    .scaledFont(size: 14, weight: .black, design: .monospaced)
                    .foregroundColor(brandColors.whiteText)

                Text("x\(loggedSet.reps)")
                    .scaledFont(size: 14, weight: .black, design: .monospaced)
                    .foregroundColor(brandColors.whiteText)

                Menu {
                    ForEach(Array(stride(from: 5.0, through: 10.0, by: 0.5)), id: \.self) { val in
                        Button(String(format: "@ RPE %.1f", val)) {
                            HapticService.play(.medium, enabled: activePrefs.hapticsEnabled)
                            withAnimation {
                                loggedSet.rpe = val
                                try? modelContext.save()
                            }
                        }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Text("@ RPE \(String(format: "%.1f", loggedSet.rpe))")
                            .scaledFont(size: 10, weight: .black, design: .monospaced)
                        Image(systemName: "chevron.up.chevron.down")
                            .scaledFont(size: 7, weight: .black)
                    }
                    .foregroundColor(brandColors.purple)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(brandColors.purple.opacity(0.15))
                    .cornerRadius(6)
                }
                .buttonStyle(PlainButtonStyle())
                .accessibilityLabel("Rate of perceived exertion")
                .accessibilityValue(String(format: "%.1f", loggedSet.rpe))
            }

            Button {
                deleteSet(loggedSet)
            } label: {
                Image(systemName: "trash")
                    .foregroundColor(brandColors.red)
                    .frame(width: 36, height: 36)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Delete set")
            .accessibilityHint("Deletes this set. Undo is offered for a few seconds.")
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 14)
        .background(brandColors.whiteText.opacity(0.02))
        .cornerRadius(12)
    }

    @ViewBuilder
    private var undoToast: some View {
        if let undo = pendingUndo {
            HStack {
                Text("Set deleted")
                    .scaledFont(size: 13, weight: .bold)
                Spacer()
                Button("UNDO", action: restoreDeletedSet)
                    .scaledFont(size: 13, weight: .black)
            }
            .foregroundColor(.white)
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(Color.plGray800)
            .cornerRadius(14)
            .padding(.horizontal, 16)
            // Clear the floating rest timer (pre-26.1); the tab-bar accessory insets the safe area itself.
            .padding(.bottom, timerManager.isActive && activePrefs.showRestTimer && !MainTabView.usesTabAccessory ? 90 : 12)
            .transition(.move(edge: .bottom).combined(with: .opacity))
            .task(id: undo.id) {
                try? await Task.sleep(for: .seconds(5))
                withAnimation {
                    if pendingUndo?.id == undo.id { pendingUndo = nil }
                }
            }
        }
    }

    // MARK: - Plate Calculator

    @ViewBuilder
    private var plateLoadNote: some View {
        let unit = activePrefs.weightUnit
        let bar = calcBar
        let unloadable = LiftMath.plates(total: calcWeight, unit: unit, bar: bar).unloadable
        if bar != LiftMath.barWeight(unit: unit) {
            Text("On a \(LiftMath.format(bar)) \(unit) bar")
                .scaledFont(size: 11, weight: .bold)
                .foregroundColor(.plSecondaryLabel)
        }
        if calcWeight > 0 && calcWeight < bar {
            Text("Below the empty \(LiftMath.format(bar)) \(unit) bar")
                .scaledFont(size: 11, weight: .bold)
                .foregroundColor(.orange)
        } else if unloadable > 0 {
            Text("\(LiftMath.format(unloadable)) \(unit) can't be loaded with standard plates")
                .scaledFont(size: 11, weight: .bold)
                .foregroundColor(.orange)
        }
    }
    
    private func exercisePill(title: String, tag: String, activeColor: Color, isSquare: Bool = false) -> some View {
        let isActive = (selectedExercise == tag)
        let resolvedActiveColor = (themeStyle == .night) ? Color.plGray300 : activeColor
        let pillBg = isActive ? resolvedActiveColor : brandColors.whiteText.opacity(0.04)
        let pillBorder = isActive ? resolvedActiveColor : brandColors.whiteText.opacity(0.08)
        let pillText = isActive ? (themeStyle == .night ? .black : .white) : brandColors.whiteText.opacity(0.6)
        
        return Button(action: {
            HapticService.play(.medium, enabled: activePrefs.hapticsEnabled)
            withAnimation(.spring(response: 0.25, dampingFraction: 0.75)) {
                selectedExercise = tag
                updateWeightInputForSelectedExercise()
                calcWeight = calculateTargetWeight(for: tag)
            }
        }) {
            VStack {
                if isSquare {
                    Spacer(minLength: 0)
                }
                Text(title)
                    .scaledFont(size: 12, weight: .black)
                    .foregroundColor(pillText)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 8)
                if isSquare {
                    Spacer(minLength: 0)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: isSquare ? nil : 38)
            .padding(.vertical, isSquare ? 8 : 0)
            .background(pillBg)
            .cornerRadius(10)
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(pillBorder, lineWidth: 1.5)
            )
        }
        .buttonStyle(PlainButtonStyle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityAddTraits(isActive ? [.isButton, .isSelected] : [.isButton])
        .accessibilityHint("Selects \(title) for logging")
    }
    
    private func setTypePill(title: String, tag: String, activeColor: Color) -> some View {
        let isActive = (selectedSetType == tag)
        let pillBg = isActive ? activeColor : brandColors.whiteText.opacity(0.04)
        let pillBorder = isActive ? activeColor : brandColors.whiteText.opacity(0.08)
        let pillText = isActive ? (themeStyle == .night ? .black : .white) : brandColors.whiteText.opacity(0.6)
        
        return Button(action: {
            HapticService.play(.medium, enabled: activePrefs.hapticsEnabled)
            withAnimation(.spring(response: 0.25, dampingFraction: 0.75)) {
                selectedSetType = tag
            }
        }) {
            Text(title)
                .scaledFont(size: 12, weight: .black)
                .foregroundColor(pillText)
                .frame(maxWidth: .infinity)
                .frame(height: 38)
                .background(pillBg)
                .cornerRadius(10)
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(pillBorder, lineWidth: 1.5)
                )
        }
        .buttonStyle(PlainButtonStyle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityAddTraits(isActive ? [.isButton, .isSelected] : [.isButton])
        .accessibilityHint("Selects \(title) set type")
    }
}

// MARK: - Core Metric Card Subview
struct TargetCard: View {
    var title: String
    var weight: Double
    var unit: String
    var color: Color
    var whiteText: Color
    var isSelected: Bool
    var isSquare: Bool = false
    var onTap: () -> Void
    
    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 8) {
                Text(title)
                    .scaledFont(size: 10, weight: .black)
                    .foregroundColor(color)
                    .tracking(1.0)
                
                if isSquare {
                    Spacer(minLength: 0)
                }
                
                HStack(alignment: .lastTextBaseline, spacing: 2) {
                    Text(LiftMath.format(weight))
                        .scaledFont(size: 20, weight: .black, design: .monospaced)
                        .foregroundColor(whiteText)
                    
                    Text(unit)
                        .scaledFont(size: 11, weight: .black)
                        .foregroundColor(.plSecondaryLabel)
                }
            }
            .padding(.horizontal, isSquare ? 8 : 12)
            .padding(.vertical, isSquare ? 10 : 14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(maxHeight: isSquare ? .infinity : nil, alignment: .leading)
            .background(isSelected ? color.opacity(0.12) : whiteText.opacity(0.04))
            .cornerRadius(16)
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(isSelected ? color : whiteText.opacity(0.08), lineWidth: 1.5)
            )
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityValue("\(LiftMath.format(weight)) \(unit)")
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : [.isButton])
        .accessibilityHint("Double tap to select \(title) for logging, and load this weight into the plate calculator.")
    }
}

// MARK: - Barbell Plate Drawing Widget
struct BarbellPlateGraphic: View {
    var weight: Double
    var bar: Double
    var isLbs: Bool
    var isNight: Bool
    
    struct IdentifiablePlate: Identifiable {
        let id: Int
        let weight: Double
    }
    
    var plates: [Double] {
        LiftMath.plates(total: weight, unit: isLbs ? "lbs" : "kg", bar: bar).perSide
    }
    
    private var leftPlates: [IdentifiablePlate] {
        plates.reversed().enumerated().map { IdentifiablePlate(id: $0.offset, weight: $0.element) }
    }
    
    private var rightPlates: [IdentifiablePlate] {
        plates.enumerated().map { IdentifiablePlate(id: $0.offset, weight: $0.element) }
    }
    
    private var barbellAccessibilityValue: String {
        let unitStr = isLbs ? "pounds" : "kilograms"
        if weight <= bar {
            return "Empty \(LiftMath.format(bar)) \(unitStr) barbell."
        }
        
        let plateCounts = plates.reduce(into: [Double: Int]()) { counts, p in
            counts[p, default: 0] += 1
        }
        
        let sortedPlates = plateCounts.keys.sorted().reversed()
        let plateDescriptionList = sortedPlates.map { p in
            let count = plateCounts[p] ?? 0
            let pStr = p == Double(Int(p)) ? "\(Int(p))" : "\(p)"
            return "\(count) \(pStr) \(unitStr) plate\(count > 1 ? "s" : "")"
        }
        
        let platesText = plateDescriptionList.joined(separator: ", ")
        return "Total weight \(LiftMath.format(weight)) \(unitStr). Loaded with \(platesText) per side on a \(LiftMath.format(bar)) \(unitStr) barbell."
    }
    
    private func plateColor(for wt: Double, isNight: Bool) -> Color {
        if isNight {
            if isLbs {
                switch wt {
                case 45: return .white
                case 35: return .plGray200
                case 25: return .plGray300
                case 10: return .plGray400
                case 5: return .plGray500
                default: return .plGray700
                }
            } else {
                switch wt {
                case 25: return .white
                case 20: return .plGray200
                case 15: return .plGray300
                case 10: return .plGray400
                case 5: return .plGray500
                case 2.5: return .plGray700
                default: return .plGray800
                }
            }
        }
        
        if isLbs {
            switch wt {
            case 45: return .plRed
            case 35: return .plBlue
            case 25: return Color(red: 0.95, green: 0.75, blue: 0.1) // yellow
            case 10: return .plGreen
            case 5: return .plGray400
            default: return .black
            }
        } else {
            switch wt {
            case 25: return .plRed
            case 20: return .plBlue
            case 15: return Color(red: 0.95, green: 0.75, blue: 0.1)
            case 10: return .plGreen
            case 5: return .plGray400
            case 2.5: return .black
            default: return .plGray500
            }
        }
    }
    
    private func plateTextColor(for wt: Double, isNight: Bool) -> Color {
        if isNight {
            if isLbs {
                switch wt {
                case 45, 35, 25: return .black
                default: return .white
                }
            } else {
                switch wt {
                case 25, 20, 15: return .black
                default: return .white
                }
            }
        }
        if isLbs {
            switch wt {
            case 25: return .black
            case 5: return .black
            default: return .white
            }
        } else {
            switch wt {
            case 15: return .black
            case 5: return .black
            default: return .white
            }
        }
    }
    
    private func plateFontSize(for wt: Double) -> CGFloat {
        if wt >= 35 { return 9 }
        if wt >= 20 { return 8 }
        if wt >= 10 { return 7 }
        return 6
    }
    
    private func plateHeight(for wt: Double) -> CGFloat {
        if isLbs {
            switch wt {
            case 45: return 80
            case 35: return 70
            case 25: return 60
            case 10: return 50
            case 5: return 40
            case 2.5: return 30
            default: return 24
            }
        } else {
            switch wt {
            case 25: return 80
            case 20: return 70
            case 15: return 60
            case 10: return 50
            case 5: return 40
            case 2.5: return 30
            default: return 24
            }
        }
    }
    
    var body: some View {
        HStack(spacing: 2) {
            Spacer()
            
            // Bar Left side (Outer tip)
            Rectangle()
                .fill(Color.plGray500)
                .frame(width: 25, height: 8)
            
            // Left plates stacked (Lightest on outside, Heaviest on inside)
            HStack(spacing: 2) {
                ForEach(leftPlates) { plate in
                    let p = plate.weight
                    let formattedLabel = p == Double(Int(p)) ? "\(Int(p))" : "\(p)"
                    let unitStr = isLbs ? "lb" : "kg"
                    let fullLabel = "\(formattedLabel)\(unitStr)"
                    
                    RoundedRectangle(cornerRadius: 4)
                        .fill(plateColor(for: p, isNight: isNight))
                        .frame(width: 18, height: plateHeight(for: p))
                        .overlay(
                            Text(fullLabel)
                                .font(.system(size: plateFontSize(for: p), weight: .black))
                                .foregroundColor(plateTextColor(for: p, isNight: isNight))
                                .rotationEffect(.degrees(-90))
                                .fixedSize()
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 4)
                                .stroke(Color.white.opacity(0.15), lineWidth: 1.0)
                        )
                }
            }
            
            // Collar stop (Inside end of left sleeve)
            Rectangle()
                .fill(Color.plGray700)
                .frame(width: 8, height: 40)
            
            // Bar center center
            Rectangle()
                .fill(Color.plGray500)
                .frame(width: 30, height: 16)
            
            // Collar stop (Inside end of right sleeve)
            Rectangle()
                .fill(Color.plGray700)
                .frame(width: 8, height: 40)
            
            // Right plates stacked (Heaviest on inside, Lightest on outside)
            HStack(spacing: 2) {
                ForEach(rightPlates) { plate in
                    let p = plate.weight
                    let formattedLabel = p == Double(Int(p)) ? "\(Int(p))" : "\(p)"
                    let unitStr = isLbs ? "lb" : "kg"
                    let fullLabel = "\(formattedLabel)\(unitStr)"
                    
                    RoundedRectangle(cornerRadius: 4)
                        .fill(plateColor(for: p, isNight: isNight))
                        .frame(width: 18, height: plateHeight(for: p))
                        .overlay(
                            Text(fullLabel)
                                .font(.system(size: plateFontSize(for: p), weight: .black))
                                .foregroundColor(plateTextColor(for: p, isNight: isNight))
                                .rotationEffect(.degrees(-90))
                                .fixedSize()
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 4)
                                .stroke(Color.white.opacity(0.15), lineWidth: 1.0)
                        )
                }
            }
            
            // Bar Right side (Outer tip)
            Rectangle()
                .fill(Color.plGray500)
                .frame(width: 25, height: 8)
            
            Spacer()
        }
        .padding(.vertical, 8)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Visual barbell diagram")
        .accessibilityValue(barbellAccessibilityValue)
    }
}
