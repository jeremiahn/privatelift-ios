import SwiftUI
import SwiftData

struct ManageExercisesView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \CustomExercise.orderIndex) private var exercises: [CustomExercise]
    @Query private var preferences: [UserPreferences]
    
    @State private var showingAddSheet = false
    @State private var selectedExerciseToEdit: CustomExercise? = nil
    
    var activePrefs: UserPreferences {
        preferences.first ?? UserPreferences()
    }
    
    var themeStyle: ThemeStyle {
        ThemeStyle(rawValue: activePrefs.theme) ?? .system
    }
    
    var brandColors: BrandColors {
        BrandColors(theme: themeStyle)
    }
    
    var body: some View {
        List {
            Section(header: Text("EXERCISES & 1RM BENCHMARKS").font(.system(size: 10, weight: .black))) {
                ForEach(exercises) { exercise in
                    Button(action: {
                        HapticService.play(.medium, enabled: activePrefs.hapticsEnabled)
                        selectedExerciseToEdit = exercise
                    }) {
                        HStack(spacing: 16) {
                            Circle()
                                .fill(Color(hex: exercise.colorHex))
                                .frame(width: 14, height: 14)
                            
                            VStack(alignment: .leading, spacing: 4) {
                                Text(exercise.displayName)
                                    .fontWeight(.bold)
                                    .foregroundColor(.primary)
                                
                                if exercise.isPowerlift, let type = exercise.powerliftType {
                                    Text("Powerlifting Core (\(type.capitalized))")
                                        .font(.caption2)
                                        .foregroundColor(brandColors.blue)
                                        .fontWeight(.semibold)
                                }
                            }
                            
                            Spacer()
                            
                            Text("\(Int(exercise.oneRepMax)) \(activePrefs.weightUnit)")
                                .font(.system(.body, design: .monospaced))
                                .fontWeight(.black)
                                .foregroundColor(.secondary)
                            
                            Image(systemName: "chevron.right")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(PlainButtonStyle())
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(exercise.displayName)
                    .accessibilityValue("\(Int(exercise.oneRepMax)) \(activePrefs.weightUnit)" + (exercise.isPowerlift ? ", Powerlifting \(exercise.powerliftType ?? "") contributor" : ""))
                    .accessibilityHint("Double tap to edit this exercise")
                }
                .onDelete(perform: deleteExercises)
                .onMove(perform: moveExercises)
            }
        }
        .navigationTitle("Manage LIlllfts") // Keeping layout styling intact
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                HStack(spacing: 2) {
                    Text("MANAGE")
                        .font(.system(size: 20, weight: .black))
                        .foregroundColor(.primary)
                    Text("LIFTS")
                        .font(.system(size: 20, weight: .black))
                        .foregroundColor(brandColors.blue)
                }
                .tracking(-0.5)
            }
            
            ToolbarItem(placement: .navigationBarTrailing) {
                HStack {
                    EditButton()
                        .fontWeight(.bold)
                        .tint(brandColors.blue)
                    
                    Button(action: {
                        HapticService.play(.medium, enabled: activePrefs.hapticsEnabled)
                        showingAddSheet = true
                    }) {
                        Image(systemName: "plus")
                            .fontWeight(.bold)
                            .tint(brandColors.blue)
                    }
                }
            }
        }
        .sheet(isPresented: $showingAddSheet) {
            AddExerciseSheet(onSave: { newExercise in
                modelContext.insert(newExercise)
                enforcePowerliftingUniqueness(for: newExercise)
                
                // Sync powerlift oneRepMax back to activePrefs if it's a powerlift
                if newExercise.isPowerlift, let type = newExercise.powerliftType {
                    if type == "squat" {
                        activePrefs.squatMax = newExercise.oneRepMax
                    } else if type == "bench" {
                        activePrefs.benchMax = newExercise.oneRepMax
                    } else if type == "deadlift" {
                        activePrefs.deadliftMax = newExercise.oneRepMax
                    }
                }
                
                reorderIndexes()
                try? modelContext.save()
            }, activePrefs: activePrefs, brandColors: brandColors)
        }
        .sheet(item: $selectedExerciseToEdit) { exercise in
            EditExerciseSheet(exercise: exercise, onSave: {
                enforcePowerliftingUniqueness(for: exercise)
                
                // Sync powerlift oneRepMax back to activePrefs
                if exercise.isPowerlift, let type = exercise.powerliftType {
                    if type == "squat" {
                        activePrefs.squatMax = exercise.oneRepMax
                    } else if type == "bench" {
                        activePrefs.benchMax = exercise.oneRepMax
                    } else if type == "deadlift" {
                        activePrefs.deadliftMax = exercise.oneRepMax
                    }
                }
                
                try? modelContext.save()
            }, activePrefs: activePrefs, brandColors: brandColors)
        }
    }
    
    private func deleteExercises(offsets: IndexSet) {
        HapticService.play(.medium, enabled: activePrefs.hapticsEnabled)
        for index in offsets {
            let exercise = exercises[index]
            modelContext.delete(exercise)
        }
        reorderIndexes()
        try? modelContext.save()
    }
    
    private func moveExercises(from source: IndexSet, to destination: Int) {
        var revisedExercises = exercises
        revisedExercises.move(fromOffsets: source, toOffset: destination)
        for (index, exercise) in revisedExercises.enumerated() {
            exercise.orderIndex = index
        }
        try? modelContext.save()
    }
    
    private func reorderIndexes() {
        for (index, exercise) in exercises.enumerated() {
            exercise.orderIndex = index
        }
    }
    
    // Ensure that only one exercise is mapped to each powerlifting type at a time.
    private func enforcePowerliftingUniqueness(for exercise: CustomExercise) {
        guard exercise.isPowerlift, let type = exercise.powerliftType else { return }
        
        for other in exercises {
            if other.id != exercise.id && other.isPowerlift && other.powerliftType == type {
                other.isPowerlift = false
                other.powerliftType = nil
            }
        }
    }
}

// MARK: - Add Exercise Sheet
struct AddExerciseSheet: View {
    @Environment(\.dismiss) private var dismiss
    
    var onSave: (CustomExercise) -> Void
    var activePrefs: UserPreferences
    var brandColors: BrandColors
    
    @State private var displayName = ""
    @State private var oneRepMaxString = ""
    @State private var selectedColorHex = "#ef4444"
    @State private var isPowerlift = false
    @State private var powerliftType = "squat"
    
    private let colorChoices = [
        ("#ef4444", "Red"),
        ("#3b82f6", "Blue"),
        ("#10b981", "Green"),
        ("#8b5cf6", "Purple"),
        ("#f97316", "Orange"),
        ("#14b8a6", "Teal"),
        ("#ec4899", "Pink"),
        ("#eab308", "Yellow")
    ]
    
    var body: some View {
        NavigationStack {
            Form {
                Section(header: Text("EXERCISE DETAILS").font(.system(size: 10, weight: .black))) {
                    TextField("Exercise Name (e.g. Overhead Press)", text: $displayName)
                        .fontWeight(.bold)
                    
                    HStack {
                        Text("1RM Max (\(activePrefs.weightUnit.uppercased()))")
                            .fontWeight(.bold)
                        Spacer()
                        TextField("0", text: $oneRepMaxString)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .font(.system(.body, design: .monospaced))
                            .fontWeight(.black)
                            .frame(width: 100)
                    }
                }
                
                Section(header: Text("THEME COLOR").font(.system(size: 10, weight: .black))) {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 40))], spacing: 12) {
                        ForEach(colorChoices, id: \.0) { color in
                            Circle()
                                .fill(Color(hex: color.0))
                                .frame(width: 32, height: 32)
                                .overlay(
                                    Circle()
                                        .stroke(Color.primary, lineWidth: selectedColorHex == color.0 ? 3 : 0)
                                )
                                .onTapGesture {
                                    HapticService.play(.medium, enabled: activePrefs.hapticsEnabled)
                                    selectedColorHex = color.0
                                }
                                .accessibilityElement(children: .ignore)
                                .accessibilityLabel("\(color.1) color tag")
                                .accessibilityAddTraits(selectedColorHex == color.0 ? [.isButton, .isSelected] : [.isButton])
                                .accessibilityHint("Selects \(color.1) as the theme color for this exercise")
                        }
                    }
                    .padding(.vertical, 8)
                }
                
                Section(header: Text("POWERLIFTING SCORE").font(.system(size: 10, weight: .black))) {
                    Toggle("Powerlifting Score Contribution", isOn: $isPowerlift)
                        .fontWeight(.bold)
                        .tint(brandColors.blue)
                    
                    if isPowerlift {
                        Picker("Powerlift Role", selection: $powerliftType) {
                            Text("Squat").tag("squat")
                            Text("Bench Press").tag("bench")
                            Text("Deadlift").tag("deadlift")
                        }
                        .fontWeight(.bold)
                    }
                }
            }
            .navigationTitle("Add Exercise")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .fontWeight(.bold)
                    .tint(brandColors.blue)
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Save") {
                        let name = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !name.isEmpty else { return }
                        let maxWeight = Double(oneRepMaxString) ?? 0.0
                        
                        let newExercise = CustomExercise(
                            name: name.uppercased(),
                            displayName: name,
                            oneRepMax: maxWeight,
                            colorHex: selectedColorHex,
                            orderIndex: 99,
                            isPowerlift: isPowerlift,
                            powerliftType: isPowerlift ? powerliftType : nil
                        )
                        
                        onSave(newExercise)
                        dismiss()
                    }
                    .fontWeight(.black)
                    .tint(brandColors.blue)
                    .disabled(displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }
}

// MARK: - Edit Exercise Sheet
struct EditExerciseSheet: View {
    @Environment(\.dismiss) private var dismiss
    
    var exercise: CustomExercise
    var onSave: () -> Void
    var activePrefs: UserPreferences
    var brandColors: BrandColors
    
    @State private var displayName = ""
    @State private var oneRepMaxString = ""
    @State private var selectedColorHex = "#ef4444"
    @State private var isPowerlift = false
    @State private var powerliftType = "squat"
    
    private let colorChoices = [
        ("#ef4444", "Red"),
        ("#3b82f6", "Blue"),
        ("#10b981", "Green"),
        ("#8b5cf6", "Purple"),
        ("#f97316", "Orange"),
        ("#14b8a6", "Teal"),
        ("#ec4899", "Pink"),
        ("#eab308", "Yellow")
    ]
    
    init(exercise: CustomExercise, onSave: @escaping () -> Void, activePrefs: UserPreferences, brandColors: BrandColors) {
        self.exercise = exercise
        self.onSave = onSave
        self.activePrefs = activePrefs
        self.brandColors = brandColors
        
        _displayName = State(initialValue: exercise.displayName)
        _oneRepMaxString = State(initialValue: String(format: "%.1f", exercise.oneRepMax))
        _selectedColorHex = State(initialValue: exercise.colorHex)
        _isPowerlift = State(initialValue: exercise.isPowerlift)
        _powerliftType = State(initialValue: exercise.powerliftType ?? "squat")
    }
    
    var body: some View {
        NavigationStack {
            Form {
                Section(header: Text("EXERCISE DETAILS").font(.system(size: 10, weight: .black))) {
                    TextField("Exercise Name", text: $displayName)
                        .fontWeight(.bold)
                    
                    HStack {
                        Text("1RM Max (\(activePrefs.weightUnit.uppercased()))")
                            .fontWeight(.bold)
                        Spacer()
                        TextField("0", text: $oneRepMaxString)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .font(.system(.body, design: .monospaced))
                            .fontWeight(.black)
                            .frame(width: 100)
                    }
                }
                
                Section(header: Text("THEME COLOR").font(.system(size: 10, weight: .black))) {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 40))], spacing: 12) {
                        ForEach(colorChoices, id: \.0) { color in
                            Circle()
                                .fill(Color(hex: color.0))
                                .frame(width: 32, height: 32)
                                .overlay(
                                    Circle()
                                        .stroke(Color.primary, lineWidth: selectedColorHex == color.0 ? 3 : 0)
                                )
                                .onTapGesture {
                                    HapticService.play(.medium, enabled: activePrefs.hapticsEnabled)
                                    selectedColorHex = color.0
                                }
                                .accessibilityElement(children: .ignore)
                                .accessibilityLabel("\(color.1) color tag")
                                .accessibilityAddTraits(selectedColorHex == color.0 ? [.isButton, .isSelected] : [.isButton])
                                .accessibilityHint("Selects \(color.1) as the theme color for this exercise")
                        }
                    }
                    .padding(.vertical, 8)
                }
                
                Section(header: Text("POWERLIFTING SCORE").font(.system(size: 10, weight: .black))) {
                    Toggle("Powerlifting Score Contribution", isOn: $isPowerlift)
                        .fontWeight(.bold)
                        .tint(brandColors.blue)
                    
                    if isPowerlift {
                        Picker("Powerlift Role", selection: $powerliftType) {
                            Text("Squat").tag("squat")
                            Text("Bench Press").tag("bench")
                            Text("Deadlift").tag("deadlift")
                        }
                        .fontWeight(.bold)
                    }
                }
            }
            .navigationTitle("Edit Exercise")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .fontWeight(.bold)
                    .tint(brandColors.blue)
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Save") {
                        let name = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !name.isEmpty else { return }
                        let maxWeight = Double(oneRepMaxString) ?? 0.0
                        
                        exercise.displayName = name
                        exercise.name = name.uppercased()
                        exercise.oneRepMax = maxWeight
                        exercise.colorHex = selectedColorHex
                        exercise.isPowerlift = isPowerlift
                        exercise.powerliftType = isPowerlift ? powerliftType : nil
                        
                        onSave()
                        dismiss()
                    }
                    .fontWeight(.black)
                    .tint(brandColors.blue)
                    .disabled(displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }
}
