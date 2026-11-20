import Foundation

/// Pure weight/strength math shared by the views. Foundation-only so
/// `scripts/LiftMathCheck/main.swift` can compile and assert against it.
enum LiftMath {
    nonisolated static let kgPerLb = 0.45359237

    // MARK: Units

    /// Converts a stored weight to "lbs" or "kg". Deliberately unrounded: any
    /// rounding grid applied in both directions drifts on repeated switches;
    /// unrounded doubles round-trip to within 1e-12 and `format` hides the tail.
    // ponytail: weights are stored in the user's current unit and rewritten on a
    // unit switch. Upgrade path: store kg only and convert at display time.
    nonisolated static func convert(_ value: Double, to unit: String) -> Double {
        unit == "kg" ? value * kgPerLb : value / kgPerLb
    }

    /// Standard Olympic bar. Users can override it globally (Settings) or per exercise.
    nonisolated static func barWeight(unit: String) -> Double { unit == "kg" ? 20 : 45 }

    /// Smallest jump a pair of plates normally makes (5 lb or 2.5 kg).
    nonisolated static func plateStep(unit: String) -> Double { unit == "kg" ? 2.5 : 5 }

    /// Fine adjustment used by a long press (1 lb or 0.5 kg).
    nonisolated static func fineStep(unit: String) -> Double { unit == "kg" ? 0.5 : 1 }

    /// `percent` of a 1RM, rounded to the nearest plate step, never below the empty bar.
    nonisolated static func target(oneRepMax: Double, percent: Double, unit: String, bar: Double? = nil) -> Double {
        let step = plateStep(unit: unit)
        let rounded = (oneRepMax * percent / 100 / step).rounded() * step
        return max(bar ?? barWeight(unit: unit), rounded)
    }

    /// Locale-tolerant number parse: the decimal pad types "142,5" in many regions.
    nonisolated static func parse(_ text: String) -> Double? {
        Double(text.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ",", with: "."))
    }

    /// Weight for display: up to two decimals, trailing zeros dropped ("102.5", "225").
    nonisolated static func format(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(0...2)))
    }

    // MARK: Plates

    nonisolated static let lbPlates: [Double] = [45, 35, 25, 10, 5, 2.5, 1]
    nonisolated static let kgPlates: [Double] = [25, 20, 15, 10, 5, 2.5, 1.25]

    /// Greedy per-side plate list for `total`, plus the total weight that can't be loaded.
    nonisolated static func plates(total: Double, unit: String, bar: Double? = nil) -> (perSide: [Double], unloadable: Double) {
        let bar = bar ?? barWeight(unit: unit)
        guard total > bar else { return ([], 0) }
        var side = (total - bar) / 2
        var result: [Double] = []
        for plate in unit == "kg" ? kgPlates : lbPlates {
            while side >= plate - 0.0001 {
                result.append(plate)
                side -= plate
            }
        }
        let unloadable = (side * 2 * 1000).rounded() / 1000
        return (result, max(0, unloadable))
    }

    // MARK: Rest

    nonisolated static let restChoices: [Double] = [60, 90, 120, 150, 180, 240, 300]

    /// "1:30", "3:00".
    nonisolated static func formatRest(_ seconds: Double) -> String {
        let total = Int(seconds)
        return String(format: "%d:%02d", total / 60, total % 60)
    }

    // MARK: Strength

    nonisolated static func e1RM(weight: Double, reps: Int, formula: String) -> Double {
        if reps <= 1 { return weight }
        switch formula {
        case "brzycki":
            return weight / max(0.01, 1.0278 - 0.0278 * Double(reps))
        case "lander":
            return 100 * weight / max(0.01, 101.3 - 2.6712 * Double(reps))
        default: // epley
            return weight * (1 + Double(reps) / 30)
        }
    }

    /// Whether a set counts toward PRs and progression (completed, at least one rep).
    nonisolated static func countsTowardRecords(setType: String, reps: Int) -> Bool {
        reps > 0 && setType != "failed" && setType != "drop"
    }

    /// Rough active energy for one set: ~0.1 kcal per rep per 45 kg lifted, floored at 3 kcal.
    nonisolated static func estimatedKcal(weight: Double, reps: Int, unit: String) -> Double {
        let kg = unit == "kg" ? weight : weight * kgPerLb
        return max(3, kg / 45 * Double(reps) * 0.1)
    }

    // MARK: Exercises

    /// Canonical key for de-duplicating exercises ("Bench Press" and "BENCH" are the same lift).
    nonisolated static func exerciseKey(_ name: String) -> String {
        let normalized = name.uppercased().replacingOccurrences(of: " ", with: "")
        return normalized == "BENCHPRESS" ? "BENCH" : normalized
    }
}
