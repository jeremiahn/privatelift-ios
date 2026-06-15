import SwiftUI
import SwiftData
import UniformTypeIdentifiers
import WatchConnectivity

struct SettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var preferences: [UserPreferences]
    
    // Fetch all sessions/sets for export/reset logic
    @Query private var allSessions: [WorkoutSession]
    @Query(sort: \WorkoutSet.timestamp, order: .forward) private var allSets: [WorkoutSet]
    @Query(sort: \CustomExercise.orderIndex) private var customExercises: [CustomExercise]
    
    @ObservedObject var healthService: HealthKitService
    
    @State private var showFileImporter = false
    @State private var activeImportType: ImportType = .json
    
    enum ImportType {
        case json, csv
    }
    @State private var showResetAlert = false
    @State private var showHealthSettingsAlert = false
    @State private var showICloudAlert = false
    @State private var importSuccessAlert = false
    @State private var showImportErrorAlert = false
    @State private var importErrorMessage = ""
    @FocusState private var isFieldFocused: Bool
    

    
    var activePrefs: UserPreferences {
        preferences.first ?? UserPreferences()
    }
    
    var themeStyle: ThemeStyle {
        ThemeStyle(rawValue: activePrefs.theme) ?? .system
    }
    
    var brandColors: BrandColors {
        BrandColors(theme: themeStyle)
    }
    
    var jsonBackupString: String {
        generateJSONBackupString()
    }
    
    var csvBackupString: String {
        generateCSVBackupString()
    }
    
    // Default rest timer choices (seconds)
    private let restTimerChoices: [Double] = [60.0, 90.0, 120.0, 180.0, 300.0]
    
    var body: some View {
        NavigationStack {
            Form {
                strengthBenchmarksSection
                appPreferencesSection
                Section(header: Text("DATABASE BACKUP & RESTORE").font(.system(size: 10, weight: .black))) {
                    backupRestoreSection
                }
                dangerZoneSection
                

            }
            .onChange(of: activePrefs.bodyWeight) { oldValue, newValue in
                try? modelContext.save()
            }
            .onChange(of: activePrefs.gender) { oldValue, newValue in
                try? modelContext.save()
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
            .fileImporter(
                isPresented: $showFileImporter,
                allowedContentTypes: activeImportType == .json ? [.json] : [.commaSeparatedText],
                allowsMultipleSelection: false
            ) { result in
                switch result {
                case .success(let urls):
                    guard let url = urls.first else { return }
                    if activeImportType == .json {
                        importBackupJSON(from: url)
                    } else {
                        importBackupCSV(from: url)
                    }
                case .failure(let error):
                    triggerImportError(error.localizedDescription)
                }
            }
            .alert("Import Database Success", isPresented: $importSuccessAlert) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("All configurations and historical lift logs have been successfully imported.")
            }
            .alert("Import Failed", isPresented: $showImportErrorAlert) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(importErrorMessage)
            }
            .alert("Confirm Complete Reset", isPresented: $showResetAlert) {
                Button("DELETE ALL LIFT DATA", role: .destructive) {
                    resetLocalDatabase()
                }
                Button("CANCEL", role: .cancel) {}
            } message: {
                Text("This action will permanently delete all of your logged strength sessions and benchmarks. This action cannot be undone.")
            }
            .alert("Health Access Required", isPresented: $showHealthSettingsAlert) {
                Button("Open Settings") {
                    if let url = URL(string: "App-Prefs:root=HEALTH") {
                        UIApplication.shared.open(url, options: [:]) { success in
                            if !success {
                                if let fallbackUrl = URL(string: UIApplication.openSettingsURLString) {
                                    UIApplication.shared.open(fallbackUrl, options: [:], completionHandler: nil)
                                }
                            }
                        }
                    }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("PersonalLift requires Health permissions to sync workouts. Tap 'Open Settings' -> select 'PersonalLift' under Data Access & Devices -> and enable write/read permissions.")
            }
            .alert("Restart Required", isPresented: $showICloudAlert) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("Your iCloud sync setting has been saved. Please fully close and relaunch PersonalLift to apply the change. Your data will not be affected.")
            }

        }
    }
    
    private var strengthBenchmarksSection: some View {
        Section(header: Text("STRENGTH BENCHMARKS & PROFILE").font(.system(size: 10, weight: .black))) {
            NavigationLink(destination: ManageExercisesView()) {
                HStack {
                    Text("Manage Exercises & Maxes")
                        .fontWeight(.bold)
                    Spacer()
                }
            }
            .tint(brandColors.blue)
            
            HStack {
                Text("Body Weight")
                    .fontWeight(.bold)
                Spacer()
                TextField("lbs", value: Bindable(activePrefs).bodyWeight, format: .number)
                    .focused($isFieldFocused)
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
                    .frame(width: 100)
                    .font(.system(.body, design: .monospaced))
                    .fontWeight(.black)
                    .accessibilityLabel("Body weight")
                    .accessibilityValue("\(activePrefs.bodyWeight) \(activePrefs.weightUnit)")
            }
            
            Picker("Gender", selection: Bindable(activePrefs).gender) {
                Text("Male").tag("male")
                Text("Female").tag("female")
                Text("Non-Binary").tag("non_binary")
                Text("Don't Track").tag("other")
            }
            .fontWeight(.bold)
        }
    }
    
    private var appPreferencesSection: some View {
        Section(header: Text("APP PREFERENCES").font(.system(size: 10, weight: .black))) {
            Picker("Weight Unit", selection: Binding(
                get: { activePrefs.weightUnit },
                set: { newValue in
                    let oldValue = activePrefs.weightUnit
                    guard oldValue != newValue else { return }
                    activePrefs.weightUnit = newValue
                    convertDatabaseUnits(targetUnit: newValue)
                }
            )) {
                Text("LBS").tag("lbs")
                Text("KG").tag("kg")
            }
            .pickerStyle(.segmented)
            
            VStack(alignment: .leading, spacing: 6) {
                Toggle("Apple Health Sync", isOn: Bindable(activePrefs).appleHealthEnabled)
                    .fontWeight(.bold)
                    .tint(.plBlue)
                    .onChange(of: activePrefs.appleHealthEnabled) { oldValue, newValue in
                        if newValue {
                            Task {
                                let success = await healthService.requestAuthorization()
                                if !success {
                                    await MainActor.run {
                                        activePrefs.appleHealthEnabled = false
                                        showHealthSettingsAlert = true
                                    }
                                }
                            }
                        }
                    }
                
                if activePrefs.appleHealthEnabled {
                    VStack(alignment: .leading, spacing: 4) {
                        Label {
                            Text("Data written to Apple Health:")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundColor(.plGray400)
                        } icon: {
                            Image(systemName: "heart.fill")
                                .font(.system(size: 9))
                                .foregroundColor(.plRed)
                        }
                        VStack(alignment: .leading, spacing: 2) {
                            Text("• Strength Training Workouts")
                            Text("• Active Energy Burned (estimated calories)")
                            Text("• Body Mass (if logged)")
                        }
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.plGray400)
                        .padding(.leading, 16)
                    }
                    .padding(.top, 2)
                } else {
                    Text("When enabled, each logged set is saved as a Strength Training workout to Apple Health, including estimated active energy burned.")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.plGray400)
                        .padding(.top, 2)
                }
            }
            
            VStack(alignment: .leading, spacing: 4) {
                Toggle("iCloud Backup Sync", isOn: Bindable(activePrefs).iCloudSyncEnabled)
                    .fontWeight(.bold)
                    .tint(.plBlue)
                    .onChange(of: activePrefs.iCloudSyncEnabled) { oldValue, newValue in
                        HapticService.play(.medium, enabled: activePrefs.hapticsEnabled)
                        UserDefaults.standard.set(newValue, forKey: "iCloudSyncEnabled")
                        if newValue {
                            UserDefaults.standard.removeObject(forKey: "iCloudSyncError")
                        }
                        showICloudAlert = true
                    }
                
                if let lastError = UserDefaults.standard.string(forKey: "iCloudSyncError") {
                    Text("Last Sync Attempt Failed:\n\(lastError)")
                        .font(.caption)
                        .foregroundColor(.red)
                        .padding(.top, 2)
                }
            }
            
            // Apple Watch support toggle
            Toggle("Apple Watch Support", isOn: Bindable(activePrefs).showWatchSupport)
                .fontWeight(.bold)
                .tint(.plBlue)
                .onChange(of: activePrefs.showWatchSupport) { oldValue, newValue in
                    if newValue {
                        WatchConnectivityManager.shared.sendUserDataToWatch()
                    }
                }
            
            if activePrefs.showWatchSupport {
                if WCSession.isSupported() {
                    let session = WCSession.default
                    if !session.isWatchAppInstalled {
                        Text("Watch App is not installed. Open the Watch app on your iPhone to install PersonalLift on your Apple Watch.")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(.orange)
                            .padding(.top, -4)
                    } else {
                        Text("Watch App is connected and installed.")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(.green)
                            .padding(.top, -4)
                    }
                }
            }
            
            Toggle("Show Rest Timer", isOn: Bindable(activePrefs).showRestTimer)
                .fontWeight(.bold)
                .tint(.plBlue)
                
            if activePrefs.showRestTimer {
                Picker("Default Rest Duration", selection: Bindable(activePrefs).defaultRestDuration) {
                    Text("1 Min").tag(60.0)
                    Text("1:30 Min").tag(90.0)
                    Text("2 Min").tag(120.0)
                    Text("3 Min").tag(180.0)
                    Text("5 Min").tag(300.0)
                }
                .fontWeight(.bold)
                .tint(.plBlue)
            }
            
            Picker("Theme", selection: Bindable(activePrefs).theme) {
                Text("System").tag("system")
                Text("Light").tag("light")
                Text("Dark").tag("dark")
                Text("Night").tag("night")
            }
            .fontWeight(.bold)
            .tint(.plBlue)
            
            Picker("Dashboard Layout", selection: Bindable(activePrefs).useGridMode) {
                Text("Carousel").tag(false)
                Text("Grid").tag(true)
            }
            .fontWeight(.bold)
            .tint(.plBlue)
            
            Picker("1RM Formula", selection: Bindable(activePrefs).formula) {
                Text("Epley").tag("epley")
                Text("Brzycki").tag("brzycki")
                Text("Lander").tag("lander")
            }
            .fontWeight(.bold)
            .tint(.plBlue)



            Picker("First Day of Week", selection: Bindable(activePrefs).startOfWeekDay) {
                Text("Sunday").tag(1)
                Text("Monday").tag(2)
                Text("Tuesday").tag(3)
                Text("Wednesday").tag(4)
                Text("Thursday").tag(5)
                Text("Friday").tag(6)
                Text("Saturday").tag(7)
            }
            .fontWeight(.bold)
            .tint(.plBlue)
        }
    }
    
    private var backupRestoreSection: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
            // Export JSON ShareLink
            ShareLink(item: jsonBackupString, subject: Text("PersonalLift Backup"), message: Text("PersonalLift Backup JSON file")) {
                dbGridBox(title: "EXPORT DATABASE", format: "JSON", icon: "square.and.arrow.up", color: brandColors.blue)
            }
            .buttonStyle(PlainButtonStyle())
            
            // Import JSON Button
            Button(action: {
                HapticService.play(.medium, enabled: activePrefs.hapticsEnabled)
                activeImportType = .json
                showFileImporter = true
            }) {
                dbGridBox(title: "IMPORT DATABASE", format: "JSON", icon: "square.and.arrow.down", color: brandColors.purple)
            }
            .buttonStyle(PlainButtonStyle())
            
            // Export CSV ShareLink
            ShareLink(item: csvBackupString, subject: Text("Workout History CSV"), message: Text("PersonalLift workout logs exported in CSV format")) {
                dbGridBox(title: "EXPORT WORKOUTS", format: "CSV", icon: "tablecells", color: brandColors.green)
            }
            .buttonStyle(PlainButtonStyle())
            
            // Import CSV Button
            Button(action: {
                HapticService.play(.medium, enabled: activePrefs.hapticsEnabled)
                activeImportType = .csv
                showFileImporter = true
            }) {
                dbGridBox(title: "IMPORT WORKOUTS", format: "CSV", icon: "square.and.arrow.down.on.square", color: brandColors.teal)
            }
            .buttonStyle(PlainButtonStyle())
        }
        .listRowBackground(Color.clear)
        .listRowInsets(EdgeInsets(top: 8, leading: 0, bottom: 8, trailing: 0))
    }
    
    private var dangerZoneSection: some View {
        Section(header: Text("DANGER ZONE").font(.system(size: 10, weight: .black))) {
            Button(action: {
                HapticService.play(.heavy, enabled: activePrefs.hapticsEnabled)
                showResetAlert = true
            }) {
                HStack {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 14, weight: .bold))
                    Text("DELETE ALL WORKOUT DATA")
                        .font(.system(size: 12, weight: .black))
                        .tracking(1.0)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 10, weight: .black))
                        .foregroundColor(themeStyle == .light ? .plGray950.opacity(0.6) : brandColors.red.opacity(0.6))
                }
                .foregroundColor(themeStyle == .light ? .plGray950 : .white)
                .padding(.vertical, 12)
                .padding(.horizontal, 16)
                .background(brandColors.red.opacity(0.15))
                .cornerRadius(12)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(brandColors.red.opacity(0.5), lineWidth: 1.5)
                )
            }
            .buttonStyle(PlainButtonStyle())
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Delete all workout data")
            .accessibilityHint("Permanently deletes all of your logged strength sessions and benchmarks. This action cannot be undone.")
            .listRowBackground(Color.clear)
            .listRowInsets(EdgeInsets(top: 8, leading: 0, bottom: 8, trailing: 0))
        }
    }
    

    
    // MARK: - Unit Switch Converter
    private func convertDatabaseUnits(targetUnit: String) {
        HapticService.play(.heavy, enabled: activePrefs.hapticsEnabled)
        
        let multiplier = targetUnit == "kg" ? 0.45359237 : (1.0 / 0.45359237)
        
        // 1. Convert Benchmarks
        activePrefs.squatMax = Foundation.round(activePrefs.squatMax * multiplier)
        activePrefs.benchMax = Foundation.round(activePrefs.benchMax * multiplier)
        activePrefs.deadliftMax = Foundation.round(activePrefs.deadliftMax * multiplier)
        activePrefs.bodyWeight = Foundation.round(activePrefs.bodyWeight * multiplier)
        
        for exercise in customExercises {
            exercise.oneRepMax = Foundation.round(exercise.oneRepMax * multiplier)
        }
        
        // 2. Convert All sets
        for item in allSets {
            item.weight = Foundation.round(item.weight * multiplier)
        }
        
        try? modelContext.save()
    }
    
    // MARK: - Backup Serializers
    private func generateJSONBackupString() -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .prettyPrinted
        
        // Build export payload structure
        var exportSessions: [BackupSession] = []
        for session in allSessions {
            var setsList: [BackupSet] = []
            for s in session.sets ?? [] {
                setsList.append(BackupSet(exercise: s.exercise, weight: s.weight, reps: s.reps, rpe: s.rpe, setType: s.setType))
            }
            exportSessions.append(BackupSession(date: session.dateString, notes: session.notes, sets: setsList))
        }
        
        let settings = BackupSettings(
            squatMax: activePrefs.squatMax,
            benchMax: activePrefs.benchMax,
            deadliftMax: activePrefs.deadliftMax,
            bodyWeight: activePrefs.bodyWeight,
            gender: activePrefs.gender,
            formula: activePrefs.formula,
            weightUnit: activePrefs.weightUnit,
            showRestTimer: activePrefs.showRestTimer,
            appleHealthEnabled: activePrefs.appleHealthEnabled,
            iCloudSyncEnabled: activePrefs.iCloudSyncEnabled,
            hapticsEnabled: activePrefs.hapticsEnabled,
            pushNotificationsEnabled: activePrefs.pushNotificationsEnabled,
            defaultRestDuration: activePrefs.defaultRestDuration,
            isOnboarded: activePrefs.isOnboarded,
            hasMigratedWebData: activePrefs.hasMigratedWebData,
            lastIntensity: activePrefs.lastIntensity,
            theme: activePrefs.theme,
            timeZoneIdentifier: activePrefs.timeZoneIdentifier,
            startOfWeekDay: activePrefs.startOfWeekDay
        )
        
        let payload = BackupPayload(settings: settings, sessions: exportSessions)
        
        if let data = try? encoder.encode(payload),
           let str = String(data: data, encoding: .utf8) {
            return str
        }
        return "{}"
    }
    
    private func generateCSVBackupString() -> String {
        var csv = "Session Date,Exercise,Weight,Reps,RPE,Set Type,Session Notes\n"
        for item in allSets {
            let sDate = item.session?.dateString ?? ""
            let rawNotes = item.session?.notes ?? ""
            let escapedNotes = rawNotes.replacingOccurrences(of: "\"", with: "'")
                                      .replacingOccurrences(of: ",", with: ";")
                                      .replacingOccurrences(of: "\n", with: " ")
                                      .replacingOccurrences(of: "\r", with: " ")
            csv += "\(sDate),\(item.exercise),\(item.weight),\(item.reps),\(item.rpe),\(item.setType),\(escapedNotes)\n"
        }
        return csv
    }
    
    // MARK: - Backup Ingestor
    private func triggerImportError(_ msg: String) {
        importErrorMessage = msg
        showImportErrorAlert = true
    }
    
    private func importBackupJSON(from url: URL) {
        guard url.startAccessingSecurityScopedResource() else {
            triggerImportError("Failed to access backup file security scope.")
            return
        }
        defer { url.stopAccessingSecurityScopedResource() }
        
        do {
            let data = try Data(contentsOf: url)
            let payload = try JSONDecoder().decode(BackupPayload.self, from: data)
            
            // 1. Ingest settings
            activePrefs.squatMax = payload.settings.squatMax
            activePrefs.benchMax = payload.settings.benchMax
            activePrefs.deadliftMax = payload.settings.deadliftMax
            activePrefs.bodyWeight = payload.settings.bodyWeight
            activePrefs.gender = payload.settings.gender
            activePrefs.formula = payload.settings.formula ?? "epley"
            activePrefs.weightUnit = payload.settings.weightUnit
            activePrefs.showRestTimer = payload.settings.showRestTimer ?? true
            activePrefs.appleHealthEnabled = payload.settings.appleHealthEnabled
            activePrefs.iCloudSyncEnabled = payload.settings.iCloudSyncEnabled ?? false
            UserDefaults.standard.set(activePrefs.iCloudSyncEnabled, forKey: "iCloudSyncEnabled")
            activePrefs.hapticsEnabled = payload.settings.hapticsEnabled ?? true
            activePrefs.pushNotificationsEnabled = payload.settings.pushNotificationsEnabled ?? true
            activePrefs.defaultRestDuration = payload.settings.defaultRestDuration ?? 180.0
            activePrefs.isOnboarded = payload.settings.isOnboarded ?? true
            activePrefs.hasMigratedWebData = payload.settings.hasMigratedWebData ?? false
            activePrefs.lastIntensity = payload.settings.lastIntensity ?? 85
            activePrefs.theme = payload.settings.theme ?? "system"
            activePrefs.timeZoneIdentifier = payload.settings.timeZoneIdentifier ?? TimeZone.current.identifier
            activePrefs.startOfWeekDay = payload.settings.startOfWeekDay ?? Calendar.current.firstWeekday
            
            // Update CustomExercises with imported values for powerlifts
            for exercise in customExercises {
                if exercise.name == "SQUAT" {
                    exercise.oneRepMax = payload.settings.squatMax
                } else if exercise.name == "BENCH" {
                    exercise.oneRepMax = payload.settings.benchMax
                } else if exercise.name == "DEADLIFT" {
                    exercise.oneRepMax = payload.settings.deadliftMax
                }
            }
            
            // 2. Ingest sessions/sets
            for sessionData in payload.sessions {
                let sDate = sessionData.date
                var sessionFetch = FetchDescriptor<WorkoutSession>(predicate: #Predicate { $0.dateString == sDate })
                sessionFetch.fetchLimit = 1
                
                let session = try modelContext.fetch(sessionFetch).first ?? WorkoutSession(dateString: sDate, notes: sessionData.notes ?? "")
                session.notes = sessionData.notes ?? ""
                modelContext.insert(session)
                
                for setData in sessionData.sets {
                    // Check if identical set exists to prevent duplication on double-imports
                    let isDuplicate = (session.sets ?? []).contains {
                        $0.exercise == setData.exercise &&
                        $0.weight == setData.weight &&
                        $0.reps == setData.reps &&
                        $0.rpe == setData.rpe &&
                        $0.setType == setData.setType
                    }
                    if !isDuplicate {
                        let newSet = WorkoutSet(
                            exercise: setData.exercise,
                            weight: setData.weight,
                            reps: setData.reps,
                            rpe: setData.rpe,
                            setType: setData.setType
                        )
                        newSet.session = session
                        modelContext.insert(newSet)
                    }
                }
            }
            
            try modelContext.save()
            HapticService.play(.success, enabled: activePrefs.hapticsEnabled)
            importSuccessAlert = true
        } catch {
            triggerImportError(error.localizedDescription)
        }
    }
    
    private func importBackupCSV(from url: URL) {
        guard url.startAccessingSecurityScopedResource() else {
            triggerImportError("Failed to access backup file security scope.")
            return
        }
        defer { url.stopAccessingSecurityScopedResource() }
        
        do {
            let csvString = try String(contentsOf: url, encoding: .utf8)
            let lines = csvString.components(separatedBy: .newlines)
            
            var importedCount = 0
            
            for line in lines {
                let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
                if trimmed.isEmpty { continue }
                
                // Skip header
                if trimmed.hasPrefix("Session Date") || trimmed.hasPrefix("Date") {
                    continue
                }
                
                let columns = trimmed.components(separatedBy: ",")
                guard columns.count >= 6 else { continue }
                
                let sDate = columns[0].trimmingCharacters(in: .whitespaces)
                let exercise = columns[1].trimmingCharacters(in: .whitespaces).uppercased()
                
                guard let weight = Double(columns[2].trimmingCharacters(in: .whitespaces)),
                      let reps = Int(columns[3].trimmingCharacters(in: .whitespaces)),
                      let rpe = Double(columns[4].trimmingCharacters(in: .whitespaces)) else {
                    continue
                }
                
                let setType = columns[5].trimmingCharacters(in: .whitespaces)
                
                // Fetch or create session
                var sessionFetch = FetchDescriptor<WorkoutSession>(predicate: #Predicate { $0.dateString == sDate })
                sessionFetch.fetchLimit = 1
                let session = try modelContext.fetch(sessionFetch).first ?? WorkoutSession(dateString: sDate, notes: "")
                modelContext.insert(session)
                
                if columns.count >= 7 {
                    let notes = columns[6].trimmingCharacters(in: .whitespacesAndNewlines)
                    if !notes.isEmpty {
                        session.notes = notes
                    }
                }
                
                // Check duplicate
                let isDuplicate = (session.sets ?? []).contains {
                    $0.exercise == exercise &&
                    $0.weight == weight &&
                    $0.reps == reps &&
                    $0.rpe == rpe &&
                    $0.setType == setType
                }
                
                if !isDuplicate {
                    let newSet = WorkoutSet(
                        exercise: exercise,
                        weight: weight,
                        reps: reps,
                        rpe: rpe,
                        setType: setType
                    )
                    newSet.session = session
                    modelContext.insert(newSet)
                    importedCount += 1
                }
            }
            
            try modelContext.save()
            HapticService.play(.success, enabled: activePrefs.hapticsEnabled)
            importSuccessAlert = true
        } catch {
            triggerImportError(error.localizedDescription)
        }
    }
    
    private func resetLocalDatabase() {
        // Clear all workouts and sets
        for set in allSets { modelContext.delete(set) }
        for session in allSessions { modelContext.delete(session) }
        for exercise in customExercises { modelContext.delete(exercise) }
        
        // Reset preferences to standard defaults
        activePrefs.squatMax = 315.0
        activePrefs.benchMax = 225.0
        activePrefs.deadliftMax = 405.0
        activePrefs.bodyWeight = 180.0
        activePrefs.gender = "other"
        activePrefs.isOnboarded = false
        activePrefs.theme = "system"
        activePrefs.timeZoneIdentifier = TimeZone.current.identifier
        activePrefs.startOfWeekDay = Calendar.current.firstWeekday
        
        try? modelContext.save()
        HapticService.play(.success, enabled: activePrefs.hapticsEnabled)
    }
    
    private func dbGridBox(title: String, format: String, icon: String, color: Color) -> some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 18, weight: .bold))
                .foregroundColor(color)
                .accessibilityHidden(true)
            
            VStack(spacing: 2) {
                Text(title)
                    .font(.system(size: 8, weight: .black))
                    .foregroundColor(.plGray400)
                    .tracking(1.0)
                
                Text(format)
                    .font(.system(size: 11, weight: .black))
                    .foregroundColor(brandColors.whiteText)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
        .background(brandColors.whiteText.opacity(0.02))
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(brandColors.whiteText.opacity(0.06), lineWidth: 1.0)
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title) as \(format)")
    }
}



// MARK: - Settings Decodable Structures
private struct BackupPayload: Codable {
    let settings: BackupSettings
    let sessions: [BackupSession]
}
private struct BackupSettings: Codable {
    let squatMax: Double
    let benchMax: Double
    let deadliftMax: Double
    let bodyWeight: Double
    let gender: String
    let formula: String?
    let weightUnit: String
    let showRestTimer: Bool?
    let appleHealthEnabled: Bool
    let iCloudSyncEnabled: Bool?
    let hapticsEnabled: Bool?
    let pushNotificationsEnabled: Bool?
    let defaultRestDuration: Double?
    let isOnboarded: Bool?
    let hasMigratedWebData: Bool?
    let lastIntensity: Int?
    let theme: String?
    let timeZoneIdentifier: String?
    let startOfWeekDay: Int?
}
private struct BackupSession: Codable {
    let date: String
    let notes: String?
    let sets: [BackupSet]
}
private struct BackupSet: Codable {
    let exercise: String
    let weight: Double
    let reps: Int
    let rpe: Double
    let setType: String
}


