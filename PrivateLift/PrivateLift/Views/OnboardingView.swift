import SwiftUI
import SwiftData
import HealthKit
import WatchConnectivity

struct OnboardingView: View {
    @Binding var isPresented: Bool
    @Environment(\.modelContext) private var modelContext
    @Query private var preferences: [UserPreferences]
    
    @State private var currentStep = 0
    @State private var isLightMode = false
    @Environment(\.colorScheme) private var colorScheme
    
    // Intermediate onboarding fields
    @State private var squatMax: Double = 315.0
    @State private var benchMax: Double = 225.0
    @State private var deadliftMax: Double = 405.0
    @State private var bodyWeight: Double = 180.0
    @State private var gender: String = "male"
    @State private var weightUnit: String = "lbs"
    @State private var trackWeightAndGender: Bool = true
    @State private var enableICloudSync: Bool = false
    @State private var enableAppleWatch: Bool = false
    @State private var enableAppleHealth: Bool = false
    @State private var healthAuthFailed: Bool = false
    @State private var showRestTimer: Bool = true
    @State private var defaultRestDuration: Double = 180.0
    @State private var useGridMode: Bool = false
    @State private var formula: String = "epley"
    @StateObject private var healthKitService = HealthKitService()
    @FocusState private var isInputFocused: Bool
    
    private let totalSteps = 7
    
    // Dynamic Theme Colors
    private var bgColor: Color {
        isLightMode ? Color(red: 0.96, green: 0.96, blue: 0.98) : Color.black
    }
    
    private var textColor: Color {
        isLightMode ? Color.black : Color.white
    }
    
    private var subtextColor: Color {
        isLightMode ? Color(red: 0.4, green: 0.4, blue: 0.4) : Color.plGray400
    }
    
    private var secondarySubtextColor: Color {
        isLightMode ? Color(red: 0.3, green: 0.3, blue: 0.3) : Color.plGray300
    }
    
    private var cardBgColor: Color {
        isLightMode ? Color.white : Color.white.opacity(0.04)
    }
    
    private var cardStrokeColor: Color {
        isLightMode ? Color.black.opacity(0.06) : Color.white.opacity(0.08)
    }
    
    private var textInputBgColor: Color {
        isLightMode ? Color.black.opacity(0.03) : Color.black.opacity(0.3)
    }
    
    private var textInputStrokeColor: Color {
        isLightMode ? Color.black.opacity(0.08) : Color.white.opacity(0.1)
    }

    private var backButtonBg: Color {
        isLightMode ? Color.black.opacity(0.04) : Color.white.opacity(0.05)
    }

    private var backButtonStroke: Color {
        isLightMode ? Color.black.opacity(0.08) : Color.white.opacity(0.1)
    }
    
    var body: some View {
        ZStack {
            bgColor.edgesIgnoringSafeArea(.all)
                .onTapGesture {
                    UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                }
            
            VStack(spacing: 20) {
                // Top Progress indicator bar
                HStack {
                    Text("ONBOARDING")
                        .font(.system(size: 10, weight: .black))
                        .tracking(2.0)
                        .foregroundColor(.gray)
                    
                    Spacer()
                    
                    HStack(spacing: 16) {
                        HStack(spacing: 6) {
                            ForEach(0..<totalSteps, id: \.self) { index in
                                Circle()
                                    .fill(index == currentStep ? Color.plBlue : (index < currentStep ? Color.plBlue.opacity(0.4) : (isLightMode ? Color.plGray300 : Color.plGray700)))
                                    .frame(width: 6, height: 6)
                                    .animation(.spring(), value: currentStep)
                            }
                        }
                        
                        Button(action: {
                            HapticService.play(.medium)
                            withAnimation {
                                isLightMode.toggle()
                            }
                        }) {
                            Image(systemName: isLightMode ? "moon.fill" : "sun.max.fill")
                                .font(.system(size: 13, weight: .bold))
                                .foregroundColor(isLightMode ? .plBlue : .white)
                                .frame(width: 28, height: 28)
                                .background(isLightMode ? Color.black.opacity(0.04) : Color.white.opacity(0.1))
                                .clipShape(Circle())
                        }
                        .accessibilityLabel("Toggle light mode")
                    }
                }
                .padding(.horizontal, 24)
                .padding(.top, 24)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Onboarding progress")
                .accessibilityValue("Step \(currentStep + 1) of \(totalSteps + 1)")
                
                // Content Cards
                TabView(selection: $currentStep) {
                    welcomeStep.tag(0)
                    liftMaxStep(title: "Squat 1RM Max", description: "Your estimated single rep maximum for Squats.", value: $squatMax, range: 45...800, step: 5, accentColor: .plRed, stepLabel: "Step 1 of 6").tag(1)
                    liftMaxStep(title: "Bench 1RM Max", description: "Your estimated single rep maximum for Bench Press.", value: $benchMax, range: 45...600, step: 5, accentColor: .plBlue, stepLabel: "Step 2 of 6").tag(2)
                    liftMaxStep(title: "Deadlift 1RM Max", description: "Your estimated single rep maximum for Deadlifts.", value: $deadliftMax, range: 45...1000, step: 5, accentColor: .plGreen, stepLabel: "Step 3 of 6").tag(3)
                    bodyWeightGenderStep.tag(4)
                    integrationsStep.tag(5)
                    preferencesStep.tag(6)
                    completionStep.tag(7)
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                .animation(.easeInOut, value: currentStep)
                
                // Navigation buttons
                HStack(spacing: 16) {
                    if currentStep > 0 && currentStep < 7 {
                        Button(action: {
                            HapticService.play(.medium)
                            withAnimation { currentStep -= 1 }
                        }) {
                            Text("BACK")
                                .font(.system(size: 11, weight: .black))
                                .tracking(1.5)
                                .foregroundColor(textColor)
                                .frame(width: 100, height: 50)
                                .background(backButtonBg)
                                .cornerRadius(16)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 16)
                                        .stroke(backButtonStroke, lineWidth: 1.5)
                                )
                        }
                        .accessibilityLabel("Back")
                        .accessibilityHint("Go back to the previous onboarding step")
                    }
                    
                    Button(action: {
                        HapticService.play(.medium)
                        if currentStep < 7 {
                            withAnimation { currentStep += 1 }
                        } else {
                            completeOnboarding()
                        }
                    }) {
                        Text(currentStep == 0 ? "GET STARTED" : (currentStep == 7 ? "START LIFTING" : "NEXT"))
                            .font(.system(size: 11, weight: .black))
                            .tracking(1.5)
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .frame(height: 50)
                            .background(currentStep == 7 ? Color.plGreen : Color.plBlue)
                            .cornerRadius(16)
                            .shadow(color: (currentStep == 7 ? Color.plGreen : Color.plBlue).opacity(0.3), radius: 10, y: 5)
                    }
                    .accessibilityLabel(currentStep == 0 ? "Get Started" : (currentStep == 7 ? "Start Lifting" : "Next"))
                    .accessibilityHint(currentStep == 7 ? "Completes calibration onboarding and enters the main application" : "Advance to the next onboarding step")
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 24)
            }
        }
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") {
                    isInputFocused = false
                }
            }
        }
        .onAppear {
            isLightMode = (colorScheme == .light)
        }
        .onChange(of: colorScheme) { oldValue, newValue in
            isLightMode = (newValue == .light)
        }
    }
    
    // MARK: - Welcome Step
    private var welcomeStep: some View {
        VStack(spacing: 24) {
            Spacer()
            
            // Pulsing emblem logo
            ZStack {
                Circle()
                    .fill(LinearGradient(colors: [.plBlue, .plPurple], startPoint: .topLeading, endPoint: .bottomTrailing))
                    .frame(width: 90, height: 90)
                    .shadow(color: .plBlue.opacity(0.3), radius: 15, y: 8)
                
                Image(systemName: "bolt.fill")
                    .font(.system(size: 40, weight: .black))
                    .foregroundColor(.white)
            }
            .scaleEffect(1.0)
            .accessibilityHidden(true)
            
            VStack(spacing: 8) {
                HStack(spacing: 2) {
                    Text("PERSONAL")
                        .font(.system(size: 28, weight: .black))
                        .foregroundColor(textColor)
                    Text("LIFT")
                        .font(.system(size: 28, weight: .black))
                        .foregroundColor(.plBlue)
                }
                .tracking(-0.5)
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Personal Lift")
                
                Text("Your personal, offline-first strength companion. Let's calibrate your starting profile to customize your target weight intensities.")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(secondarySubtextColor)
                    .multilineTextAlignment(.center)
                    .lineSpacing(4)
                    .padding(.horizontal, 32)
            }
            
            Spacer()
        }
    }
    
    // MARK: - Generic Lift Max Step
    private func liftMaxStep(
        title: String,
        description: String,
        value: Binding<Double>,
        range: ClosedRange<Double>,
        step: Double,
        accentColor: Color,
        stepLabel: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 20) {
            Spacer()
            
            VStack(alignment: .leading, spacing: 4) {
                Text(stepLabel)
                    .font(.system(size: 10, weight: .black))
                    .foregroundColor(accentColor)
                    .tracking(1.5)
                
                Text(title)
                    .font(.system(size: 24, weight: .black))
                    .foregroundColor(textColor)
                
                Text(description)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(subtextColor)
            }
            .padding(.horizontal, 24)
            
            // Main input card
            VStack(spacing: 32) {
                VStack(spacing: 4) {
                    TextField(title, value: value, format: .number)
                        .focused($isInputFocused)
                        .font(.system(size: 64, weight: .black, design: .monospaced))
                        .foregroundColor(textColor)
                        .multilineTextAlignment(.center)
                        .keyboardType(.numberPad)
                        .frame(maxWidth: 240)
                        .accessibilityLabel("\(title) value")
                        .accessibilityValue("\(Int(value.wrappedValue)) \(weightUnit)")
                    
                    Text(weightUnit.uppercased())
                        .font(.system(size: 14, weight: .black))
                        .foregroundColor(subtextColor)
                        .tracking(2.0)
                        .accessibilityHidden(true)
                }
                
                Slider(value: value, in: range, step: step)
                    .tint(accentColor)
                    .padding(.horizontal, 16)
                    .accessibilityLabel("\(title) slider")
                    .accessibilityValue("\(Int(value.wrappedValue)) \(weightUnit)")
            }
            .padding(.vertical, 32)
            .padding(.horizontal, 16)
            .background(cardBgColor)
            .cornerRadius(24)
            .overlay(
                RoundedRectangle(cornerRadius: 24)
                    .stroke(cardStrokeColor, lineWidth: 1.5)
            )
            .padding(.horizontal, 24)
            
            Spacer()
        }
    }
    
    // MARK: - Body Weight & Gender Step
    private var bodyWeightGenderStep: some View {
        VStack(alignment: .leading, spacing: 20) {
            Spacer()
            
            VStack(alignment: .leading, spacing: 4) {
                Text("STEP 4 OF 6")
                    .font(.system(size: 10, weight: .black))
                    .foregroundColor(.plPurple)
                    .tracking(1.5)
                
                Text("Body Weight & Gender")
                    .font(.system(size: 24, weight: .black))
                    .foregroundColor(textColor)
                
                Text("We use these metrics to calculate advanced power-to-weight lifting ratios.")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(subtextColor)
            }
            .padding(.horizontal, 24)
            
            VStack(spacing: 20) {
                Toggle("Track Weight & Gender", isOn: $trackWeightAndGender)
                    .tint(.plPurple)
                    .fontWeight(.bold)
                    .font(.system(size: 13))
                    .foregroundColor(textColor)
                    .onChange(of: trackWeightAndGender) { oldValue, newValue in
                        HapticService.play(.medium)
                        if !newValue {
                            bodyWeight = 0.0
                            gender = "other"
                        } else {
                            bodyWeight = 180.0
                            gender = "male"
                        }
                    }
                
                Divider()
                    .background(isLightMode ? Color.black.opacity(0.08) : Color.white.opacity(0.1))
                
                VStack(spacing: 24) {
                    // Weight input
                    VStack(alignment: .leading, spacing: 8) {
                        Text("BODY WEIGHT")
                            .font(.system(size: 9, weight: .black))
                            .foregroundColor(subtextColor)
                            .tracking(1.5)
                        
                        HStack {
                            TextField("Weight", value: $bodyWeight, format: .number)
                                .focused($isInputFocused)
                                .font(.system(size: 18, weight: .black, design: .monospaced))
                                .foregroundColor(textColor)
                                .keyboardType(.decimalPad)
                                .disabled(!trackWeightAndGender)
                                .accessibilityLabel("Body weight")
                                .accessibilityValue("\(bodyWeight) \(weightUnit)")
                            
                            Spacer()
                            
                            Picker("Unit", selection: $weightUnit) {
                                Text("LBS").tag("lbs")
                                Text("KG").tag("kg")
                            }
                            .pickerStyle(.segmented)
                            .frame(width: 100)
                            .disabled(!trackWeightAndGender)
                            .accessibilityLabel("Body weight unit")
                        }
                        .padding(.horizontal, 16)
                        .frame(height: 52)
                        .background(textInputBgColor)
                        .cornerRadius(12)
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(textInputStrokeColor, lineWidth: 1.5)
                        )
                    }
                    
                    // Gender Selection
                    VStack(alignment: .leading, spacing: 10) {
                        Text("GENDER")
                            .font(.system(size: 9, weight: .black))
                            .foregroundColor(subtextColor)
                            .tracking(1.5)
                        
                        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                            genderButton(label: "MALE", tag: "male")
                            genderButton(label: "FEMALE", tag: "female")
                            genderButton(label: "NON-BINARY", tag: "non_binary")
                            genderButton(label: "DON'T TRACK", tag: "other")
                        }
                    }
                    .disabled(!trackWeightAndGender)
                }
                .opacity(trackWeightAndGender ? 1.0 : 0.3)
                .animation(.easeInOut, value: trackWeightAndGender)
            }
            .padding(24)
            .background(cardBgColor)
            .cornerRadius(24)
            .overlay(
                RoundedRectangle(cornerRadius: 24)
                    .stroke(cardStrokeColor, lineWidth: 1.5)
            )
            .padding(.horizontal, 24)
            
            Spacer()
        }
    }
    
    private func genderButton(label: String, tag: String) -> some View {
        Button(action: {
            HapticService.play(.medium)
            gender = tag
        }) {
            Text(label)
                .font(.system(size: 10, weight: .black))
                .foregroundColor(gender == tag ? .white : textColor)
                .frame(maxWidth: .infinity)
                .frame(height: 44)
                .background(gender == tag ? Color.plPurple : (isLightMode ? Color.black.opacity(0.04) : Color.white.opacity(0.04)))
                .cornerRadius(12)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(gender == tag ? Color.plPurple : cardStrokeColor, lineWidth: 1.5)
                )
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
        .accessibilityAddTraits(gender == tag ? [.isButton, .isSelected] : [.isButton])
    }
    
    // MARK: - Integrations & Sync Step
    private var integrationsStep: some View {
        VStack(alignment: .leading, spacing: 20) {
            Spacer()
            
            VStack(alignment: .leading, spacing: 4) {
                Text("STEP 5 OF 6")
                    .font(.system(size: 10, weight: .black))
                    .foregroundColor(.plBlue)
                    .tracking(1.5)
                
                Text("Integrations & Sync")
                    .font(.system(size: 24, weight: .black))
                    .foregroundColor(textColor)
                
                Text("Enable optional integrations. You can always change these later in Settings.")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(subtextColor)
            }
            .padding(.horizontal, 24)
            
            VStack(spacing: 0) {
                // iCloud Sync
                integrationToggleRow(
                    icon: "icloud.fill",
                    iconColor: .plBlue,
                    title: "iCloud Backup Sync",
                    subtitle: "Sync your workout data across all your Apple devices via iCloud. A restart is required after changing this.",
                    isOn: $enableICloudSync
                )
                
                Divider()
                    .background(isLightMode ? Color.black.opacity(0.08) : Color.white.opacity(0.1))
                    .padding(.leading, 56)
                
                // Apple Watch
                integrationToggleRow(
                    icon: "applewatch",
                    iconColor: .plGreen,
                    title: "Apple Watch App",
                    subtitle: "Enable the Apple Watch companion for logging sets from your wrist during workouts.",
                    isOn: $enableAppleWatch
                )
                
                Divider()
                    .background(isLightMode ? Color.black.opacity(0.08) : Color.white.opacity(0.1))
                    .padding(.leading, 56)
                
                // Apple Health
                VStack(spacing: 0) {
                    integrationToggleRow(
                        icon: "heart.fill",
                        iconColor: .plRed,
                        title: "Apple Health Sync",
                        subtitle: "Saves each logged set to Apple Health as a Strength Training workout, including active energy burned and body mass data.",
                        isOn: $enableAppleHealth
                    )
                    
                    if healthAuthFailed {
                        HStack(spacing: 8) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .font(.system(size: 10))
                                .foregroundColor(.orange)
                            Text("Health permission was not granted. You can enable it in iOS Settings → Health → Personal Lift.")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundColor(.orange)
                                .lineSpacing(2)
                        }
                        .padding(.horizontal, 20)
                        .padding(.bottom, 16)
                        .padding(.leading, 36)
                        .transition(.opacity.combined(with: .move(edge: .top)))
                    }
                }
            }
            .padding(.vertical, 8)
            .background(cardBgColor)
            .cornerRadius(24)
            .overlay(
                RoundedRectangle(cornerRadius: 24)
                    .stroke(cardStrokeColor, lineWidth: 1.5)
            )
            .padding(.horizontal, 24)
            
            // Footer hint
            HStack(spacing: 6) {
                Image(systemName: "gearshape")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(subtextColor)
                Text("All of these can be changed anytime in the Settings tab.")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(subtextColor)
            }
            .padding(.horizontal, 28)
            
            Spacer()
        }
    }
    
    private func integrationToggleRow(
        icon: String,
        iconColor: Color,
        title: String,
        subtitle: String,
        isOn: Binding<Bool>
    ) -> some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 20, weight: .semibold))
                .foregroundColor(iconColor)
                .frame(width: 36, height: 36)
                .background(iconColor.opacity(isLightMode ? 0.1 : 0.15))
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .accessibilityHidden(true)
            
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(textColor)
                
                Text(subtitle)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(subtextColor)
                    .lineSpacing(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            
            Spacer()
            
            Toggle("", isOn: isOn)
                .labelsHidden()
                .tint(iconColor)
                .onChange(of: isOn.wrappedValue) { oldValue, newValue in
                    HapticService.play(.medium)
                }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(title)
        .accessibilityValue(isOn.wrappedValue ? "Enabled" : "Disabled")
        .accessibilityAddTraits(.isButton)
    }
    
    // MARK: - Preferences & Customization Step
    private var preferencesStep: some View {
        VStack(alignment: .leading, spacing: 20) {
            Spacer()
            
            VStack(alignment: .leading, spacing: 4) {
                Text("STEP 6 OF 6")
                    .font(.system(size: 10, weight: .black))
                    .foregroundColor(.plPurple)
                    .tracking(1.5)
                
                Text("Preferences")
                    .font(.system(size: 24, weight: .black))
                    .foregroundColor(textColor)
                
                Text("Customize your rest intervals, dashboard layouts, and calculations.")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(subtextColor)
            }
            .padding(.horizontal, 24)
            
            VStack(spacing: 0) {
                // Show Rest Timer
                integrationToggleRow(
                    icon: "timer",
                    iconColor: .plBlue,
                    title: "Show Rest Timer",
                    subtitle: "Display a rest timer countdown after completing a workout set.",
                    isOn: $showRestTimer
                )
                
                if showRestTimer {
                    Divider()
                        .background(isLightMode ? Color.black.opacity(0.08) : Color.white.opacity(0.1))
                        .padding(.leading, 56)
                    
                    // Default Rest Duration
                    HStack(spacing: 14) {
                        Image(systemName: "hourglass")
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundColor(.plTeal)
                            .frame(width: 36, height: 36)
                            .background(Color.plTeal.opacity(isLightMode ? 0.1 : 0.15))
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                            .accessibilityHidden(true)
                        
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Default Rest Duration")
                                .font(.system(size: 13, weight: .bold))
                                .foregroundColor(textColor)
                            
                            Text("Choose the length of your default rest periods.")
                                .font(.system(size: 10, weight: .medium))
                                .foregroundColor(subtextColor)
                        }
                        
                        Spacer()
                        
                        Picker("", selection: $defaultRestDuration) {
                            Text("1 Min").tag(60.0)
                            Text("1:30").tag(90.0)
                            Text("2 Min").tag(120.0)
                            Text("3 Min").tag(180.0)
                            Text("5 Min").tag(300.0)
                        }
                        .pickerStyle(.menu)
                        .tint(.plTeal)
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 14)
                }
                
                Divider()
                    .background(isLightMode ? Color.black.opacity(0.08) : Color.white.opacity(0.1))
                    .padding(.leading, 56)
                
                // Dashboard Layout (Carousel vs Grid)
                HStack(spacing: 14) {
                    Image(systemName: "square.grid.2x2.fill")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundColor(.plPurple)
                        .frame(width: 36, height: 36)
                        .background(Color.plPurple.opacity(isLightMode ? 0.1 : 0.15))
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                        .accessibilityHidden(true)
                    
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Dashboard Layout")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundColor(textColor)
                        
                        Text("Choose how your exercises are presented on the main tab.")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(subtextColor)
                    }
                    
                    Spacer()
                    
                    Picker("", selection: $useGridMode) {
                        Text("Carousel").tag(false)
                        Text("Grid").tag(true)
                    }
                    .pickerStyle(.menu)
                    .tint(.plPurple)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 14)
                
                Divider()
                    .background(isLightMode ? Color.black.opacity(0.08) : Color.white.opacity(0.1))
                    .padding(.leading, 56)
                
                // 1RM Formula (Epley vs Brzycki vs Lander)
                HStack(spacing: 14) {
                    Image(systemName: "function")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundColor(.plRed)
                        .frame(width: 36, height: 36)
                        .background(Color.plRed.opacity(isLightMode ? 0.1 : 0.15))
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                        .accessibilityHidden(true)
                    
                    VStack(alignment: .leading, spacing: 3) {
                        Text("1RM Formula")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundColor(textColor)
                        
                        Text("Formula used to calculate estimated one-rep maximums.")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(subtextColor)
                    }
                    
                    Spacer()
                    
                    Picker("", selection: $formula) {
                        Text("Epley").tag("epley")
                        Text("Brzycki").tag("brzycki")
                        Text("Lander").tag("lander")
                    }
                    .pickerStyle(.menu)
                    .tint(.plRed)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 14)
            }
            .padding(.vertical, 8)
            .background(cardBgColor)
            .cornerRadius(24)
            .overlay(
                RoundedRectangle(cornerRadius: 24)
                    .stroke(cardStrokeColor, lineWidth: 1.5)
            )
            .padding(.horizontal, 24)
            
            // Footer hint
            HStack(spacing: 6) {
                Image(systemName: "gearshape")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(subtextColor)
                Text("All of these can be changed anytime in the Settings tab.")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(subtextColor)
            }
            .padding(.horizontal, 28)
            
            Spacer()
        }
    }
    
    // MARK: - Calibration Completion Step
    private var completionStep: some View {
        VStack(spacing: 24) {
            Spacer()
            
            // Bouncing checkmark graphic
            ZStack {
                Circle()
                    .fill(LinearGradient(colors: [.plGreen, .emeraldGreen], startPoint: .topLeading, endPoint: .bottomTrailing))
                    .frame(width: 90, height: 90)
                    .shadow(color: .plGreen.opacity(0.3), radius: 15, y: 8)
                
                Image(systemName: "checkmark")
                    .font(.system(size: 36, weight: .black))
                    .foregroundColor(.white)
            }
            .accessibilityHidden(true)
            
            VStack(spacing: 8) {
                Text("CALIBRATION COMPLETE")
                    .font(.system(size: 20, weight: .black))
                    .foregroundColor(textColor)
                    .tracking(-0.5)
                
                Text("Your strength benchmarks have been established. Your workout intensity target weight plates will now adapt automatically.")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(secondarySubtextColor)
                    .multilineTextAlignment(.center)
                    .lineSpacing(4)
                    .padding(.horizontal, 32)
            }
            
            Spacer()
        }
    }
    
    // MARK: - Save and Complete Logic
    private func completeOnboarding() {
        let prefsFetch = FetchDescriptor<UserPreferences>()
        do {
            let existingPrefs = try modelContext.fetch(prefsFetch)
            let prefs = existingPrefs.first ?? UserPreferences()
            
            let finalSquat = max(45, min(squatMax, 800))
            let finalBench = max(45, min(benchMax, 600))
            let finalDeadlift = max(45, min(deadliftMax, 1000))
            
            prefs.squatMax = finalSquat
            prefs.benchMax = finalBench
            prefs.deadliftMax = finalDeadlift
            prefs.bodyWeight = bodyWeight
            prefs.gender = gender
            prefs.weightUnit = weightUnit
            prefs.isOnboarded = true
            prefs.theme = isLightMode ? "light" : "dark" // Save theme preference selected during setup
            
            // Persist integration preferences from onboarding
            prefs.iCloudSyncEnabled = enableICloudSync
            prefs.showWatchSupport = enableAppleWatch
            prefs.appleHealthEnabled = enableAppleHealth
            
            // Persist setup preferences
            prefs.showRestTimer = showRestTimer
            prefs.defaultRestDuration = defaultRestDuration
            prefs.useGridMode = useGridMode
            prefs.formula = formula
            
            // Sync iCloud flag to UserDefaults (required for ModelContainer at next launch)
            UserDefaults.standard.set(enableICloudSync, forKey: "iCloudSyncEnabled")
            
            if existingPrefs.isEmpty {
                modelContext.insert(prefs)
            }
            
            // Sync with pre-seeded CustomExercise objects
            DatabaseSeeder.seedDataIfNeeded(context: modelContext)
            
            let exerciseFetch = FetchDescriptor<CustomExercise>()
            let exercises = try modelContext.fetch(exerciseFetch)
            
            if let squatExercise = exercises.first(where: { $0.name == "SQUAT" }) {
                squatExercise.oneRepMax = finalSquat
            }
            if let benchExercise = exercises.first(where: { $0.name == "BENCH" }) {
                benchExercise.oneRepMax = finalBench
            }
            if let deadliftExercise = exercises.first(where: { $0.name == "DEADLIFT" }) {
                deadliftExercise.oneRepMax = finalDeadlift
            }
            
            try modelContext.save()
            
            // Request Apple Health authorization if user opted in
            if enableAppleHealth {
                Task {
                    let authorized = await healthKitService.requestAuthorization()
                    await MainActor.run {
                        if !authorized {
                            prefs.appleHealthEnabled = false
                            try? modelContext.save()
                            debugLog("Apple Health authorization was not granted during onboarding.")
                        }
                        HapticService.play(.success)
                        isPresented = false
                    }
                }
            } else {
                HapticService.play(.success)
                isPresented = false
            }
        } catch {
            debugLog("Failed to save onboarding benchmarks: \(error)")
        }
    }
}

// Custom emerald color extension
extension Color {
    static let emeraldGreen = Color(red: 0.05, green: 0.65, blue: 0.45)
}
