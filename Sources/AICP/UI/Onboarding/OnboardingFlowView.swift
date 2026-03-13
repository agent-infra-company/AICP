import SwiftUI

struct OnboardingFlowView: View {
    @ObservedObject var core: ControlPlaneCore
    let onFinish: () -> Void

    @State private var currentStep = 0

    private let totalSteps = 4

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 0) {
                // Draggable title bar area
                Color.clear
                    .frame(height: 28)

                OnboardingProgressBar(current: currentStep, total: totalSteps)
                    .padding(.horizontal, 40)

                Spacer()

                Group {
                    switch currentStep {
                    case 0: OnboardingWelcomeStep()
                    case 1:
                        OnboardingGatewayStep(
                            onEnable: {
                                await core.enableOpenClaw()
                                withAnimation { currentStep += 1 }
                            },
                            onSkip: { withAnimation { currentStep += 1 } }
                        )
                    case 2:
                        OnboardingPermissionStep(
                            icon: "bell.badge.fill",
                            title: "Notifications",
                            description: "Get notified when tasks complete, fail, or need your input.",
                            privacyNote: AppRuntimeEnvironment.current.supportsNotifications
                                ? nil
                                : "Requires the app bundle. Run `make install` first.",
                            onAllow: {
                                if AppRuntimeEnvironment.current.supportsNotifications {
                                    let result = await core.requestNotificationAuthorization()
                                    if !result {
                                        if let url = URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension") {
                                            NSWorkspace.shared.open(url)
                                        }
                                    }
                                }
                                withAnimation { currentStep += 1 }
                            },
                            onSkip: { withAnimation { currentStep += 1 } }
                        )
                    case 3: OnboardingCompletionStep()
                    default: EmptyView()
                    }
                }
                .transition(.asymmetric(
                    insertion: .opacity,
                    removal: .opacity
                ))
                .animation(.easeInOut(duration: 0.4), value: currentStep)
                .id(currentStep)

                Spacer()

                OnboardingNavBar(
                    currentStep: currentStep,
                    totalSteps: totalSteps,
                    // Hide nav buttons on permission steps (they have their own Allow/Skip)
                    hideNextButton: currentStep == 1 || currentStep == 2,
                    onBack: { withAnimation { currentStep -= 1 } },
                    onNext: { withAnimation { currentStep += 1 } },
                    onFinish: onFinish
                )
                .padding(.bottom, 36)
                .padding(.horizontal, 40)
            }
        }
        .frame(minWidth: 480, minHeight: 540)
    }
}
