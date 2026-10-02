import SwiftUI
import SwiftData

struct DashboardView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var preferences: [UserPreferences]
    
    // Fetch today's workout sets
    @Query(sort: \WorkoutSet.timestamp, order: .forward) private var allSets: [WorkoutSet]
    
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
    @FocusState private var isFieldFocused: Bool
    
    @State private var showDeleteConfirmation = false
    @State private var setToDelete: WorkoutSet? = nil
    
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
        let dateStr = todayString
        return allSets.filter { $0.session?.dateString == dateStr }
    }
    
    var todaySession: WorkoutSession? {
        let dateStr = todayString
        return allSessions.first { $0.dateString == dateStr }
    }
    
    var todayNotesBinding: Binding<String> {
        Binding(
            get: { todaySession?.notes ?? "" },
            set: { newValue in
                if let session = todaySession {
                    session.notes = newValue
                    try? modelContext.save()
                }
            }
        )
    }
    
    // Dynamically calculate target weight for custom exercises
    private func calculateTargetWeight(for exerciseName: String) -> Double {
        let max = exercises.first(where: { $0.name == exerciseName })?.oneRepMax ?? 0.0
        let target = (max * (intensity / 100.0))
        return Double(Swift.max(45, Int(Foundation.round(target / 5.0) * 5.0)))
    }
    
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
                                    .font(.system(size: 11, weight: .black))
                                    .foregroundColor(brandColors.blue)
                                    .tracking(2.0)
                                
                                Text("Target Intensity: \(Int(intensity))%")
                                    .font(.system(size: 22, weight: .black))
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
                            .font(.system(size: 15, weight: .black))
                            .foregroundColor(brandColors.purple)
                            .tracking(2.0)
                        
                        VStack(spacing: 14) {
                            // Exercise pills row (Dynamic)
                            VStack(alignment: .leading, spacing: 6) {
                                Text("EXERCISE")
                                    .font(.system(size: 9, weight: .black))
                                    .foregroundColor(.plGray400)
                                    .tracking(1.5)
                                
                                exerciseSelectionSection
                            }
                            .padding(.bottom, 4)
                            
                            // Set Type pills row
                            VStack(alignment: .leading, spacing: 6) {
                                Text("SET TYPE")
                                    .font(.system(size: 9, weight: .black))
                                    .foregroundColor(.plGray400)
                                    .tracking(1.5)
                                
                                HStack(spacing: 8) {
                                    setTypePill(title: "Warmup", tag: "warmup", activeColor: brandColors.purple)
                                    setTypePill(title: "Working", tag: "working", activeColor: brandColors.purple)
                                    setTypePill(title: "Failed", tag: "failed", activeColor: brandColors.purple)
                                }
                            }
                            
                            // Weight + Reps textfields
                            HStack(spacing: 12) {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Weight (\(activePrefs.weightUnit.uppercased()))")
                                        .font(.system(size: 9, weight: .black))
                                        .foregroundColor(.plGray400)
                                    HStack(spacing: 4) {
                                        Button(action: {
                                            adjustWeight(by: -1)
                                        }) {
                                            Image(systemName: "minus")
                                                .font(.system(size: 12, weight: .bold))
                                                .foregroundColor(brandColors.whiteText)
                                                .frame(width: 32, height: 48)
                                                .background(brandColors.whiteText.opacity(0.04))
                                                .cornerRadius(8)
                                        }
                                        .buttonStyle(PlainButtonStyle())
                                        .accessibilityLabel("Decrease weight by 1")
                                        
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
                                        
                                        Button(action: {
                                            adjustWeight(by: 1)
                                        }) {
                                            Image(systemName: "plus")
                                                .font(.system(size: 12, weight: .bold))
                                                .foregroundColor(brandColors.whiteText)
                                                .frame(width: 32, height: 48)
                                                .background(brandColors.whiteText.opacity(0.04))
                                                .cornerRadius(8)
                                        }
                                        .buttonStyle(PlainButtonStyle())
                                        .accessibilityLabel("Increase weight by 1")
                                    }
                                }
                                
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Reps")
                                        .font(.system(size: 9, weight: .black))
                                        .foregroundColor(.plGray400)
                                    TextField("5", text: $repsInput)
                                        .focused($isFieldFocused)
                                        .keyboardType(.numberPad)
                                        .font(.system(.body, design: .monospaced))
                                        .fontWeight(.bold)
                                        .foregroundColor(brandColors.whiteText)
                                        .padding(.horizontal, 12)
                                        .frame(height: 48)
                                        .background(brandColors.whiteText.opacity(0.04))
                                        .cornerRadius(12)
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 12)
                                                .stroke(brandColors.whiteText.opacity(0.08), lineWidth: 1.5)
                                        )
                                        .accessibilityLabel("Reps")
                                        .accessibilityValue("\(repsInput)")
                                }
                            }
                            
                            // RPE Selector
                            VStack(alignment: .leading, spacing: 6) {
                                HStack {
                                    Text("RPE (Intensity of effort)")
                                        .font(.system(size: 12, weight: .black))
                                        .foregroundColor(.plGray400)
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
                            
                            // Save Button
                            Button(action: saveLoggedSet) {
                                HStack {
                                    Image(systemName: "plus.circle.fill")
                                    Text("Log Completed Set")
                                        .font(.system(size: 12, weight: .black))
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
                    
                    // 4. Barbell Plate Calculator Widget
                    VStack(alignment: .leading, spacing: 16) {
                        Text("PLATE CALCULATOR")
                            .font(.system(size: 11, weight: .black))
                            .foregroundColor(brandColors.teal)
                            .tracking(2.0)
                        
                        plateCalculatorAutofillSection
                        .padding(.bottom, 4)
                        
                        VStack(spacing: 20) {
                            HStack {
                                Text("BAR LOAD WEIGHT:")
                                    .font(.system(size: 9, weight: .black))
                                    .foregroundColor(.plGray400)
                                    .tracking(1.0)
                                
                                HStack(spacing: 4) {
                                    Button(action: {
                                        HapticService.play(.medium, enabled: activePrefs.hapticsEnabled)
                                        calcWeight = max(0.0, calcWeight - 1)
                                    }) {
                                        Image(systemName: "minus")
                                            .font(.system(size: 14, weight: .bold))
                                            .foregroundColor(brandColors.whiteText)
                                            .frame(width: 36, height: 52)
                                            .background(brandColors.whiteText.opacity(0.04))
                                            .cornerRadius(8)
                                    }
                                    .buttonStyle(PlainButtonStyle())
                                    .accessibilityLabel("Decrease calculator weight by 1")
                                    
                                    TextField("Weight", value: $calcWeight, format: .number)
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
                                        .accessibilityValue("\(Int(calcWeight)) \(activePrefs.weightUnit)")
                                    
                                    Button(action: {
                                        HapticService.play(.medium, enabled: activePrefs.hapticsEnabled)
                                        calcWeight = calcWeight + 1
                                    }) {
                                        Image(systemName: "plus")
                                            .font(.system(size: 14, weight: .bold))
                                            .foregroundColor(brandColors.whiteText)
                                            .frame(width: 36, height: 52)
                                            .background(brandColors.whiteText.opacity(0.04))
                                            .cornerRadius(8)
                                    }
                                    .buttonStyle(PlainButtonStyle())
                                    .accessibilityLabel("Increase calculator weight by 1")
                                }
                                    
                                Text(activePrefs.weightUnit.uppercased())
                                    .font(.system(size: 12, weight: .black))
                                    .foregroundColor(.plGray400)
                            }
                            
                            // Visual Barbell Drawing
                            BarbellPlateGraphic(weight: calcWeight, isLbs: activePrefs.weightUnit == "lbs", isNight: themeStyle == .night)
                                .frame(height: 120)
                        }
                    }
                    .padding(20)
                    .glassCard(style: themeStyle)
                    
                    // 5. Today's Logs List
                    if !todaySets.isEmpty {
                        VStack(alignment: .leading, spacing: 16) {
                            HStack {
                                Text("TODAY'S WORKOUT LOG")
                                    .font(.system(size: 11, weight: .black))
                                    .foregroundColor(brandColors.green)
                                    .tracking(2.0)
                                
                                Spacer()
                                
                                if activePrefs.appleHealthEnabled {
                                    HStack(spacing: 4) {
                                        Image(systemName: "heart.fill")
                                            .font(.system(size: 8))
                                            .foregroundColor(.plRed)
                                        Text("Apple Health")
                                            .font(.system(size: 9, weight: .bold))
                                            .foregroundColor(.plGray400)
                                    }
                                }
                            }
                            
                            VStack(spacing: 12) {
                                ForEach(todaySets) { loggedSet in
                                    let matchedExercise = exercises.first(where: { $0.name == loggedSet.exercise })
                                    let rawColor = Color(hex: matchedExercise?.colorHex ?? "#8b5cf6")
                                    let exerciseColor = themeStyle == .night ? Color.plGray300 : rawColor
                                    HStack {
                                        VStack(alignment: .leading, spacing: 4) {
                                            Text(matchedExercise?.displayName ?? loggedSet.exercise)
                                                .font(.system(size: 14, weight: .black))
                                                .foregroundColor(brandColors.whiteText)
                                            Menu {
                                                Button("Warmup") {
                                                    HapticService.play(.medium, enabled: activePrefs.hapticsEnabled)
                                                    withAnimation {
                                                        loggedSet.setType = "warmup"
                                                        try? modelContext.save()
                                                    }
                                                }
                                                Button("Working") {
                                                    HapticService.play(.medium, enabled: activePrefs.hapticsEnabled)
                                                    withAnimation {
                                                        loggedSet.setType = "working"
                                                        try? modelContext.save()
                                                    }
                                                }
                                                Button("Failed") {
                                                    HapticService.play(.medium, enabled: activePrefs.hapticsEnabled)
                                                    withAnimation {
                                                        loggedSet.setType = "failed"
                                                        try? modelContext.save()
                                                    }
                                                }
                                            } label: {
                                                HStack(spacing: 2) {
                                                    Text("\((loggedSet.setType == "drop" || loggedSet.setType == "failed" ? "FAILED" : loggedSet.setType.uppercased())) SET")
                                                        .font(.system(size: 9, weight: .black))
                                                        .foregroundColor(loggedSet.setType == "working" ? exerciseColor : .plGray400)
                                                    Image(systemName: "chevron.up.chevron.down")
                                                        .font(.system(size: 7, weight: .black))
                                                        .foregroundColor(loggedSet.setType == "working" ? exerciseColor : .plGray400)
                                                }
                                            }
                                            .buttonStyle(PlainButtonStyle())
                                        }
                                        
                                        Spacer()
                                        
                                        HStack(spacing: 8) {
                                            Text("\(Int(loggedSet.weight)) \(activePrefs.weightUnit)")
                                                .font(.system(size: 14, weight: .black, design: .monospaced))
                                                .foregroundColor(brandColors.whiteText)
                                            
                                            Text("x\(loggedSet.reps)")
                                                .font(.system(size: 14, weight: .black, design: .monospaced))
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
                                                        .font(.system(size: 10, weight: .black, design: .monospaced))
                                                        .foregroundColor(brandColors.purple)
                                                    Image(systemName: "chevron.up.chevron.down")
                                                        .font(.system(size: 7, weight: .black))
                                                        .foregroundColor(brandColors.purple)
                                                }
                                                .padding(.horizontal, 8)
                                                .padding(.vertical, 4)
                                                .background(brandColors.purple.opacity(0.15))
                                                .cornerRadius(6)
                                            }
                                            .buttonStyle(PlainButtonStyle())
                                        }
                                        
                                        Button(action: {
                                            setToDelete = loggedSet
                                            showDeleteConfirmation = true
                                        }) {
                                            Image(systemName: "trash")
                                                .foregroundColor(brandColors.red)
                                                .padding(.leading, 8)
                                        }
                                    }
                                    .padding(.vertical, 10)
                                    .padding(.horizontal, 14)
                                    .background(brandColors.whiteText.opacity(0.02))
                                    .cornerRadius(12)
                                }
                                
                                // Divider between logs and notes
                                Divider()
                                    .background(brandColors.whiteText.opacity(0.08))
                                    .padding(.vertical, 8)
                                
                                // Today's Notes Editor
                                VStack(alignment: .leading, spacing: 6) {
                                    Text("TODAY'S SESSION NOTES")
                                        .font(.system(size: 9, weight: .black))
                                        .foregroundColor(.plGray400)
                                        .tracking(1.5)
                                    
                                    TextField("Enter notes, mood, accessories...", text: todayNotesBinding, axis: .vertical)
                                        .font(.system(size: 13, weight: .bold))
                                        .foregroundColor(brandColors.whiteText)
                                        .padding(12)
                                        .background(Color.black.opacity(themeStyle == .night ? 0.4 : 0.2))
                                        .cornerRadius(10)
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 10)
                                                .stroke(brandColors.whiteText.opacity(0.08), lineWidth: 1.0)
                                        )
                                }
                            }
                        }
                        .padding(20)
                        .glassCard(style: themeStyle)
                    }
                    
                }
                .padding(.horizontal, 16)
                .padding(.top, 16)
                .padding(.bottom, 100) // Padding for Rest Timer + Tabbar
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
                
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") {
                        isFieldFocused = false
                    }
                }
            }
            .plBackground(style: themeStyle)
            .onAppear {
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
                if let parsed = Double(newValue) {
                    calcWeight = parsed
                } else if newValue.isEmpty {
                    calcWeight = 0.0
                }
            }
            .alert("Confirm Set Deletion", isPresented: $showDeleteConfirmation) {
                Button("Delete", role: .destructive) {
                    if let set = setToDelete {
                        deleteSet(set)
                    }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Are you sure you want to permanently delete this set?")
            }
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
                            plateAutofillButton(exercise: exercise.displayName, value: calculateTargetWeight(for: exercise.name), isSquare: false)
                                .frame(minWidth: 95, maxWidth: .infinity, minHeight: 48, maxHeight: .infinity)
                        }
                    }
                }
            }
        } else {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(uniqueExercises) { exercise in
                        plateAutofillButton(exercise: exercise.displayName, value: calculateTargetWeight(for: exercise.name), isSquare: false)
                            .frame(minWidth: 95, maxWidth: .infinity, minHeight: 48, maxHeight: .infinity)
                    }
                }
            }
        }
    }
    
    private func plateAutofillButton(exercise: String, value: Double, isSquare: Bool = false) -> some View {
        Button(action: {
            HapticService.play(.medium, enabled: activePrefs.hapticsEnabled)
            calcWeight = value
        }) {
            VStack(spacing: 2) {
                Spacer(minLength: 0)
                Text(exercise.uppercased())
                    .font(.system(size: 8, weight: .black))
                    .foregroundColor(brandColors.whiteText)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 4)
                
                Spacer(minLength: 0)
                Text("\(Int(value))")
                    .font(.system(size: 11, weight: .black, design: .monospaced))
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
        .accessibilityValue("\(Int(value)) \(activePrefs.weightUnit)")
        .accessibilityHint("Loads \(Int(value)) \(activePrefs.weightUnit) into the plate calculator")
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
        let weight = calculateTargetWeight(for: selectedExercise)
        weightInput = "\(Int(weight))"
    }
    
    private func saveLoggedSet() {
        guard let weight = Double(weightInput),
              let reps = Int(repsInput) else {
            HapticService.play(.error, enabled: activePrefs.hapticsEnabled)
            return
        }
        
        let dateStr = todayString
        
        // 1. Fetch or create today's Session
        let sessionFetch = FetchDescriptor<WorkoutSession>(predicate: #Predicate { $0.dateString == dateStr })
        let session: WorkoutSession
        do {
            if let existing = try modelContext.fetch(sessionFetch).first {
                session = existing
            } else {
                session = WorkoutSession(dateString: dateStr)
                modelContext.insert(session)
            }
            
            // 2. Log Set in SwiftData
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
            
            // 3. Trigger Apple Health Sync if enabled
            if activePrefs.appleHealthEnabled {
                Task {
                    _ = await healthService.saveWorkout(
                        date: Date(),
                        exercise: selectedExercise,
                        weight: weight,
                        reps: reps,
                        setType: selectedSetType,
                        rpe: rpeInput
                    )
                }
            }
            
            HapticService.play(.success, enabled: activePrefs.hapticsEnabled)
            
            // 4. Start Rest Timer if enabled
            if activePrefs.showRestTimer {
                timerManager.startTimer(
                    duration: activePrefs.defaultRestDuration,
                    allowNotifications: activePrefs.pushNotificationsEnabled,
                    hapticsEnabled: activePrefs.hapticsEnabled
                )
            }
        } catch {
            debugLog("Failed to save logged set: \(error)")
        }
    }
    
    private func deleteSet(_ set: WorkoutSet) {
        HapticService.play(.heavy, enabled: activePrefs.hapticsEnabled)
        modelContext.delete(set)
        try? modelContext.save()
    }

    private func adjustWeight(by increment: Double) {
        HapticService.play(.medium, enabled: activePrefs.hapticsEnabled)
        let currentWeight = Double(weightInput) ?? 0.0
        let newWeight = max(0.0, currentWeight + increment)
        if newWeight.truncatingRemainder(dividingBy: 1.0) == 0 {
            weightInput = String(format: "%.0f", newWeight)
        } else {
            weightInput = String(format: "%.1f", newWeight)
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
                    .font(.system(size: 12, weight: .black))
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
                .font(.system(size: 12, weight: .black))
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
                    .font(.system(size: 10, weight: .black))
                    .foregroundColor(color)
                    .tracking(1.0)
                
                if isSquare {
                    Spacer(minLength: 0)
                }
                
                HStack(alignment: .lastTextBaseline, spacing: 2) {
                    Text("\(Int(weight))")
                        .font(.system(size: 20, weight: .black, design: .monospaced))
                        .foregroundColor(whiteText)
                    
                    Text(unit)
                        .font(.system(size: 11, weight: .black))
                        .foregroundColor(.plGray400)
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
        .accessibilityValue("\(Int(weight)) \(unit)")
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : [.isButton])
        .accessibilityHint("Double tap to select \(title) for logging, and load this weight into the plate calculator.")
    }
}

// MARK: - Barbell Plate Drawing Widget
struct BarbellPlateGraphic: View {
    var weight: Double
    var isLbs: Bool
    var isNight: Bool
    
    struct IdentifiablePlate: Identifiable {
        let id: Int
        let weight: Double
    }
    
    var plates: [Double] {
        let bar = isLbs ? 45.0 : 20.0
        guard weight > bar else { return [] }
        let sideWeight = (weight - bar) / 2.0
        
        let lbsPlates = [45.0, 35.0, 25.0, 10.0, 5.0, 2.5, 1.0]
        let kgPlates = [25.0, 20.0, 15.0, 10.0, 5.0, 2.5, 1.25]
        let config = isLbs ? lbsPlates : kgPlates
        
        var remaining = sideWeight
        var resolvedPlates: [Double] = []
        
        for p in config {
            while remaining >= p {
                resolvedPlates.append(p)
                remaining -= p
            }
        }
        
        return resolvedPlates
    }
    
    private var leftPlates: [IdentifiablePlate] {
        plates.reversed().enumerated().map { IdentifiablePlate(id: $0.offset, weight: $0.element) }
    }
    
    private var rightPlates: [IdentifiablePlate] {
        plates.enumerated().map { IdentifiablePlate(id: $0.offset, weight: $0.element) }
    }
    
    private var barbellAccessibilityValue: String {
        let unitStr = isLbs ? "pounds" : "kilograms"
        let bar = isLbs ? 45.0 : 20.0
        if weight <= bar {
            return "Empty \(Int(bar)) \(unitStr) barbell."
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
        return "Total weight \(Int(weight)) \(unitStr). Loaded with \(platesText) per side on a \(Int(bar)) \(unitStr) barbell."
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
