import SwiftUI

struct OnboardingProgressBar: View {
    let current: Int
    let total: Int

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.white.opacity(0.1))
                    .frame(height: 4)
                Capsule()
                    .fill(Color.red)
                    .frame(
                        width: geo.size.width * CGFloat(current + 1) / CGFloat(total),
                        height: 4
                    )
                    .animation(.spring(response: 0.4), value: current)
            }
        }
        .frame(height: 4)
    }
}

struct OnboardingNavBar: View {
    let currentStep: Int
    let totalSteps: Int
    let onBack: () -> Void
    let onNext: () -> Void
    let onFinish: () -> Void

    var body: some View {
        HStack {
            if currentStep > 0 {
                Button("Back") { onBack() }
                    .buttonStyle(.plain)
                    .foregroundStyle(.white.opacity(0.6))
            }

            Spacer()

            if currentStep < totalSteps - 1 {
                Button("Continue") { onNext() }
                    .buttonStyle(.borderedProminent)
                    .tint(.red)
            } else {
                Button("Start Using AICP") { onFinish() }
                    .buttonStyle(.borderedProminent)
                    .tint(.red)
            }
        }
    }
}
