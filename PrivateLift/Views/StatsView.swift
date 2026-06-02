import SwiftUI
import SwiftData

struct StatsView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var preferences: [UserPreferences]
    
    // Fetch all sessions and sets to aggregate stats
    @Query private var allSessions: [WorkoutSession]
    @Query(sort: \WorkoutSet.timestamp, order: .forward) private var allSets: [WorkoutSet]
    @Query(sort: \CustomExercise.orderIndex) private var exercises: [CustomExercise]
    
    var activePrefs: UserPreferences {
        preferences.first ?? UserPreferences()
    }
    
    var themeStyle: ThemeStyle {
        ThemeStyle(rawValue: activePrefs.theme) ?? .system
    }
    
    var brandColors: BrandColors {
        BrandColors(theme: themeStyle)
    }
    
    // MARK: - Aggregated Metrics
    var totalTonnage: Double {
        allSets.reduce(0.0) { $0 + ($1.weight * Double($1.reps)) }
    }
    
    var totalSessions: Int {
        allSessions.count
    }
    
    var squatPR: Double {
        let squatEx = exercises.first(where: { $0.isPowerlift && $0.powerliftType == "squat" })
        let name = squatEx?.name ?? "SQUAT"
        let loggedMax = allSets.filter { $0.exercise == name }.map { $0.weight }.max() ?? 0.0
        return max(loggedMax, squatEx?.oneRepMax ?? activePrefs.squatMax)
    }
    
    var benchPR: Double {
        let benchEx = exercises.first(where: { $0.isPowerlift && $0.powerliftType == "bench" })
        let name = benchEx?.name ?? "BENCH"
        let loggedMax = allSets.filter { $0.exercise == name }.map { $0.weight }.max() ?? 0.0
        return max(loggedMax, benchEx?.oneRepMax ?? activePrefs.benchMax)
    }
    
    var deadliftPR: Double {
        let deadliftEx = exercises.first(where: { $0.isPowerlift && $0.powerliftType == "deadlift" })
        let name = deadliftEx?.name ?? "DEADLIFT"
        let loggedMax = allSets.filter { $0.exercise == name }.map { $0.weight }.max() ?? 0.0
        return max(loggedMax, deadliftEx?.oneRepMax ?? activePrefs.deadliftMax)
    }
    
    var maxExerciseVolume: Int {
        let volumes = exercises.map { ex in allSets.filter { $0.exercise == ex.name }.count }
        return Swift.max(1, volumes.max() ?? 1)
    }
    
    // MARK: - Wilks & DOTS Scores
    var wilksScore: Double {
        let bodyWeightKg = activePrefs.weightUnit == "lbs" ? activePrefs.bodyWeight * 0.45359237 : activePrefs.bodyWeight
        let totalPRKg = activePrefs.weightUnit == "lbs" ? (squatPR + benchPR + deadliftPR) * 0.45359237 : (squatPR + benchPR + deadliftPR)
        
        guard bodyWeightKg > 0 else { return 0.0 }
        
        // Male Denominator
        let aM = -216.0475144
        let bM = 16.2606339
        let cM = -0.002388645
        let dM = -0.00113732
        let eM = 0.00000701863
        let fM = -0.00000001291
        let denomM = aM + bM * bodyWeightKg + cM * pow(bodyWeightKg, 2) + dM * pow(bodyWeightKg, 3) + eM * pow(bodyWeightKg, 4) + fM * pow(bodyWeightKg, 5)
        
        // Female Denominator
        let aF = 594.31747775582
        let bF = -27.23842536447
        let cF = 0.82112226871
        let dF = -0.00930733913
        let eF = 0.00004731582
        let fF = -0.00000009054
        let denomF = aF + bF * bodyWeightKg + cF * pow(bodyWeightKg, 2) + dF * pow(bodyWeightKg, 3) + eF * pow(bodyWeightKg, 4) + fF * pow(bodyWeightKg, 5)
        
        let coeffM = denomM != 0 ? 500.0 / denomM : 0.0
        let coeffF = denomF != 0 ? 500.0 / denomF : 0.0
        
        let coeff: Double
        if activePrefs.gender == "female" {
            coeff = coeffF
        } else if activePrefs.gender == "male" {
            coeff = coeffM
        } else {
            // Non-binary and other categories are calculated using the average coefficient
            coeff = (coeffM + coeffF) / 2.0
        }
        
        return totalPRKg * coeff
    }
    
    var dotsScore: Double {
        let bodyWeightKg = activePrefs.weightUnit == "lbs" ? activePrefs.bodyWeight * 0.45359237 : activePrefs.bodyWeight
        let totalPRKg = activePrefs.weightUnit == "lbs" ? (squatPR + benchPR + deadliftPR) * 0.45359237 : (squatPR + benchPR + deadliftPR)
        
        guard bodyWeightKg > 0 else { return 0.0 }
        
        // Male Denominator
        let aM = -0.0000010930
        let bM = 0.0007391293
        let cM = -0.1918759221
        let dM = 24.0900756
        let eM = -307.75076
        let denomM = aM * pow(bodyWeightKg, 4) + bM * pow(bodyWeightKg, 3) + cM * pow(bodyWeightKg, 2) + dM * bodyWeightKg + eM
        
        // Female Denominator
        let aF = -0.0000010706
        let bF = 0.0005158568
        let cF = -0.1126655495
        let dF = 13.6175032
        let eF = -57.96288
        let denomF = aF * pow(bodyWeightKg, 4) + bF * pow(bodyWeightKg, 3) + cF * pow(bodyWeightKg, 2) + dF * bodyWeightKg + eF
        
        let coeffM = denomM != 0 ? 500.0 / denomM : 0.0
        let coeffF = denomF != 0 ? 500.0 / denomF : 0.0
        
        let coeff: Double
        if activePrefs.gender == "female" {
            coeff = coeffF
        } else if activePrefs.gender == "male" {
            coeff = coeffM
        } else {
            // Non-binary and other categories are calculated using the average coefficient
            coeff = (coeffM + coeffF) / 2.0
        }
        
        return totalPRKg * coeff
    }
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    
                    // 1. Lifetime Totals Grid
                    VStack(alignment: .leading, spacing: 16) {
                        Text("LIFETIME TOTALS")
                            .font(.system(size: 11, weight: .black))
                            .foregroundColor(brandColors.blue)
                            .tracking(2.0)
                        
                        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                            statBox(title: "TOTAL VOLUME", value: String(format: "%.0f", totalTonnage), unit: activePrefs.weightUnit, color: brandColors.blue)
                            statBox(title: "SESSIONS", value: "\(totalSessions)", unit: "COMPLETED", color: brandColors.purple)
                            
                            if activePrefs.gender != "other" {
                                statBox(title: "WILKS SCORE", value: String(format: "%.1f", wilksScore), unit: "PTS", color: brandColors.teal)
                                statBox(title: "DOTS SCORE", value: String(format: "%.1f", dotsScore), unit: "PTS", color: brandColors.green)
                            }
                        }
                    }
                    .padding(20)
                    .glassCard(style: themeStyle)
                    
                    // 2. Personal Records Grid (Dynamic)
                    VStack(alignment: .leading, spacing: 16) {
                        Text("PERSONAL RECORDS")
                            .font(.system(size: 11, weight: .black))
                            .foregroundColor(brandColors.purple)
                            .tracking(2.0)
                        
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 12) {
                                ForEach(exercises) { exercise in
                                    let loggedMax = allSets.filter { $0.exercise == exercise.name }.map { $0.weight }.max() ?? 0.0
                                    let prVal = max(loggedMax, exercise.oneRepMax)
                                    prMetric(title: exercise.displayName.uppercased(), value: prVal, unit: activePrefs.weightUnit, color: Color(hex: exercise.colorHex))
                                        .frame(width: 100)
                                }
                            }
                        }
                    }
                    .padding(20)
                    .glassCard(style: themeStyle)
                    
                    // 4. Volume Breakdown bars (Dynamic)
                    VStack(alignment: .leading, spacing: 16) {
                        Text("WEEKLY VOLUME BREAKDOWN")
                            .font(.system(size: 11, weight: .black))
                            .foregroundColor(brandColors.green)
                            .tracking(2.0)
                        
                        VStack(spacing: 12) {
                            ForEach(exercises) { exercise in
                                let sets = allSets.filter { $0.exercise == exercise.name }
                                let count = sets.count
                                let reps = sets.reduce(0) { $0 + $1.reps }
                                let weight = sets.reduce(0.0) { $0 + ($1.weight * Double($1.reps)) }
                                volumeBar(title: exercise.displayName.uppercased(), count: count, reps: reps, weight: weight, color: Color(hex: exercise.colorHex))
                            }
                        }
                    }
                    .padding(20)
                    .glassCard(style: themeStyle)
                    
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
            .plBackground(style: themeStyle)
        }
    }
    
    // Sub-view component helpers
    private func statBox(title: String, value: String, unit: String, color: Color) -> some View {
        let textColor = themeStyle == .night ? .plGray400 : color
        
        return VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 8, weight: .black))
                .foregroundColor(textColor)
                .tracking(1.0)
            
            HStack(alignment: .lastTextBaseline, spacing: 4) {
                Text(value)
                    .font(.system(size: 26, weight: .black, design: .monospaced))
                    .foregroundColor(brandColors.whiteText)
                
                Text(unit)
                    .font(.system(size: 10, weight: .black))
                    .foregroundColor(.plGray400)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(brandColors.whiteText.opacity(0.02))
        .cornerRadius(16)
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(brandColors.whiteText.opacity(0.06), lineWidth: 1.0)
        )
    }
    
    private func prMetric(title: String, value: Double, unit: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 9, weight: .black))
                .foregroundColor(color)
                .tracking(1.0)
            
            HStack(alignment: .lastTextBaseline, spacing: 2) {
                Text("\(Int(value))")
                    .font(.system(size: 20, weight: .black, design: .monospaced))
                    .foregroundColor(brandColors.whiteText)
                
                Text(unit)
                    .font(.system(size: 9, weight: .bold))
                    .foregroundColor(.plGray400)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(brandColors.whiteText.opacity(0.02))
        .cornerRadius(16)
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(brandColors.whiteText.opacity(0.06), lineWidth: 1.0)
        )
    }
    
    private func volumeBar(title: String, count: Int, reps: Int, weight: Double, color: Color) -> some View {
        let pct = Double(count) / Double(maxExerciseVolume)
        
        return VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title)
                    .font(.system(size: 11, weight: .black))
                    .foregroundColor(brandColors.whiteText)
                Spacer()
                Text("\(count) sets • \(reps) reps • \(Int(weight)) \(activePrefs.weightUnit)")
                    .font(.system(size: 11, weight: .black, design: .monospaced))
                    .foregroundColor(color)
            }
            
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(brandColors.whiteText.opacity(0.04))
                        .frame(height: 8)
                    
                    RoundedRectangle(cornerRadius: 4)
                        .fill(color)
                        .frame(width: geo.size.width * CGFloat(pct), height: 8)
                        .shadow(color: color.opacity(0.3), radius: 4, y: 0)
                }
            }
            .frame(height: 8)
        }
    }
}
