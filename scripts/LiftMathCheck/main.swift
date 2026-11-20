// Self-check for LiftMath. Run from the repo root:
//   swiftc -o /tmp/liftmath-check PrivateLift/PrivateLift/Services/LiftMath.swift scripts/LiftMathCheck/main.swift && /tmp/liftmath-check
import Foundation

func approx(_ a: Double, _ b: Double, _ tol: Double = 1e-9) -> Bool { abs(a - b) <= tol }

// Unit round trips are lossless for typical plate-precision values, even repeated.
for original in [102.5, 101.25, 60.0, 142.5, 20.0] {
    var v = original
    for _ in 0..<10 { v = LiftMath.convert(LiftMath.convert(v, to: "lbs"), to: "kg") }
    assert(approx(v, original), "kg round trip drifted: \(original) -> \(v)")
}
for original in [225.0, 227.0, 315.0, 135.5, 45.0] {
    var v = original
    for _ in 0..<10 { v = LiftMath.convert(LiftMath.convert(v, to: "kg"), to: "lbs") }
    assert(approx(v, original), "lbs round trip drifted: \(original) -> \(v)")
}

// Targets round to the plate step and never go below the bar.
assert(LiftMath.target(oneRepMax: 315, percent: 85, unit: "lbs") == 270)   // 267.75 -> 270
assert(LiftMath.target(oneRepMax: 140, percent: 85, unit: "kg") == 120)    // 119 -> 120
assert(LiftMath.target(oneRepMax: 100, percent: 87, unit: "kg") == 87.5)
assert(LiftMath.target(oneRepMax: 20, percent: 50, unit: "kg") == 20)
assert(LiftMath.target(oneRepMax: 40, percent: 50, unit: "lbs") == 45)

// Plates: exact loads have no remainder; impossible loads report it.
let p225 = LiftMath.plates(total: 225, unit: "lbs")
assert(p225.perSide == [45, 45] && p225.unloadable == 0)
let p226 = LiftMath.plates(total: 226, unit: "lbs")
assert(p226.perSide == [45, 45] && approx(p226.unloadable, 1)) // 0.5 lb/side has no plate
let p1025 = LiftMath.plates(total: 102.5, unit: "kg")
assert(p1025.perSide == [25, 15, 1.25] && p1025.unloadable == 0)
assert(LiftMath.plates(total: 45, unit: "lbs").perSide.isEmpty)

// Custom bars: a 55 lb trap bar raises the floor and changes the plate math.
assert(LiftMath.target(oneRepMax: 100, percent: 50, unit: "lbs", bar: 55) == 55)
assert(LiftMath.plates(total: 145, unit: "lbs", bar: 55).perSide == [45])
assert(LiftMath.plates(total: 125, unit: "lbs", bar: 35).perSide == [45])

// Parsing accepts both decimal separators; rest labels.
assert(LiftMath.parse("142,5") == 142.5 && LiftMath.parse(" 225 ") == 225 && LiftMath.parse("abc") == nil)
assert(LiftMath.formatRest(90) == "1:30" && LiftMath.formatRest(180) == "3:00")

// Formatting keeps meaningful decimals and drops trailing zeros.
let fmt = { (v: Double) in LiftMath.format(v).replacingOccurrences(of: ",", with: ".") }
assert(fmt(102.5) == "102.5" && fmt(225) == "225" && fmt(101.25) == "101.25")

// e1RM and record filtering.
assert(LiftMath.e1RM(weight: 300, reps: 1, formula: "epley") == 300)
assert(approx(LiftMath.e1RM(weight: 225, reps: 5, formula: "epley"), 262.5))
assert(!LiftMath.countsTowardRecords(setType: "failed", reps: 3))
assert(!LiftMath.countsTowardRecords(setType: "working", reps: 0))
assert(LiftMath.countsTowardRecords(setType: "warmup", reps: 5))

// Exercise keys.
assert(LiftMath.exerciseKey("Bench Press") == "BENCH" && LiftMath.exerciseKey("bench") == "BENCH")
assert(LiftMath.exerciseKey("Overhead Press") == "OVERHEADPRESS")

print("LiftMath checks passed")
