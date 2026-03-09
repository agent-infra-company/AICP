import SwiftUI

struct OnboardingFlowView: View {
    @ObservedObject var core: CompanionCore
    let onFinish: () -> Void

    @State private var currentStep = 0

    private let totalSteps = 4

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 0) {
                OnboardingProgressBar(current: currentStep, total: totalSteps)
                    .padding(.top, 48)
                    .padding(.horizontal, 48)

                Spacer()

                Group {
                    switch currentStep {
                    case 0: OnboardingWelcomeStep()
                    case 1: OnboardingNotificationStep(core: core)
                    case 2: OnboardingProfileStep(core: core)
                    case 3: OnboardingCompletionStep()
                    default: EmptyView()
                    }
                }
                .transition(.asymmetric(
                    insertion: .move(edge: .trailing).combined(with: .opacity),
                    removal: .move(edge: .leading).combined(with: .opacity)
                ))
                .animation(.spring(response: 0.4, dampingFraction: 0.85), value: currentStep)
                .id(currentStep)

                Spacer()

                OnboardingNavBar(
                    currentStep: currentStep,
                    totalSteps: totalSteps,
                    onBack: { withAnimation { currentStep -= 1 } },
                    onNext: { withAnimation { currentStep += 1 } },
                    onFinish: onFinish
                )
                .padding(.bottom, 48)
                .padding(.horizontal, 48)
            }
        }
        .frame(minWidth: 640, minHeight: 480)
    }
}
