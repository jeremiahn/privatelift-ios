# PrivateLift iOS & watchOS

> A privacy-first, 100% on-device strength training tracker and workout companion built with SwiftUI and SwiftData.

PrivateLift is designed for lifters who want a powerful, streamlined workout tracker without subscriptions, ads, tracking, or cloud lock-in. All data lives locally on your device with optional private Apple iCloud sync.

---

## Features

### Core iOS App
- **Workout Logging**: Track sets, reps, weight, and RPE with minimal friction during workouts.
- **Live Activity & Dynamic Island Rest Timer**: Real-time rest countdown on your Lock Screen and Dynamic Island.
- **Stats & Analytics**:
  - Personal Records tracking with 1RM estimations.
  - Weekly volume breakdown by muscle group and exercise.
  - Lifetime totals with automatic **Wilks** and **DOTS** powerlifting score calculations.
- **Apple HealthKit Integration**: Seamlessly saves completed workout sessions, active energy burned, and body metrics directly to Apple Health.
- **Routines & Custom Exercises**: Build flexible workout templates or log ad-hoc exercises.
- **Plate Calculator**: Quick barbell loading math for standard Olympic bars and plates.
- **Privacy First**: Zero third-party trackers, zero external analytics, zero forced accounts.

### Apple Watch Companion (`PrivateLiftWatch`)
- Standalone or paired set logging from your wrist.
- Real-time two-way synchronization with the iPhone app via `WatchConnectivity`.
- Haptic alerts for rest timer completions.

### Widgets (`PrivateLiftWidget`)
- Interactive Lock Screen and Home Screen widgets.
- Live Activity integration for active session rest intervals.

---

## Tech Stack

- **Platform**: iOS 17.0+, watchOS 10.0+
- **Frameworks**: SwiftUI, SwiftData, WidgetKit, ActivityKit, WatchConnectivity, HealthKit
- **Language**: Swift 5.10 / Swift 6
- **Architecture**: Modern declarative SwiftUI with SwiftData `@Model` and `@Query`

---

## Project Structure

```
privatelift-ios/
├── PrivateLift/                 # Main iOS Application target
│   ├── Models/                  # SwiftData schema (WorkoutSession, WorkoutSet, UserPreferences)
│   ├── Views/                   # SwiftUI views (Dashboard, History, Stats, Settings)
│   ├── Services/                # HealthKit, RestTimer, Haptics, Migration managers
│   ├── Watch/                   # WatchConnectivity coordination
│   └── Theme/                   # Custom design system and palette
├── PrivateLiftWatch/            # watchOS Companion App target
├── PrivateLiftWidget/           # Live Activity and Lock Screen widgets
├── Shared/                      # Shared models, DTOs, and utility extensions
└── PrivateLift.xcodeproj        # Xcode project configuration
```

---

## Getting Started

### Prerequisites
- macOS Sonoma (14.0) or later
- Xcode 15.0 or later
- iOS 17.0+ Simulator or physical device

### Building & Running

1. **Clone the repository**:
   ```bash
   git clone git@github.com:jeremiahn/privatelift-ios.git
   cd privatelift-ios
   ```

2. **Open in Xcode**:
   ```bash
   open PrivateLift.xcodeproj
   ```

3. **Select Target & Destination**:
   - In Xcode's toolbar scheme selector, choose **PrivateLift** and an iOS Simulator (e.g., iPhone 16 Pro).
   - Press `Cmd + B` to build, or `Cmd + R` to run.

---

## Contributing

Contributions, bug reports, and feature requests are welcome. Feel free to open an issue or submit a pull request.

---

## License

This project is licensed under the terms of the [MIT License](LICENSE).
