import SwiftUI

struct OnboardingProgressBar: View {
    let current: Int
    let total: Int

    var body: some View {
        HStack(spacing: 6) {
            ForEach(0..<total, id: \.self) { index in
                Capsule()
                    .fill(index <= current ? Color.red : Color.white.opacity(0.1))
                    .frame(height: 3)
                    .frame(maxWidth: .infinity)
                    .animation(.spring(response: 0.4), value: current)
            }
        }
    }
}

struct OnboardingNavBar: View {
    let currentStep: Int
    let totalSteps: Int
    var hideNextButton: Bool = false
    let onBack: () -> Void
    let onNext: () -> Void
    let onFinish: () -> Void

    var body: some View {
        HStack {
            if currentStep > 0 {
                Button("Back") { onBack() }
                    .buttonStyle(.plain)
                    .foregroundStyle(.white.opacity(0.5))
                    .font(.system(size: 13))
            }

            Spacer()

            if currentStep < totalSteps - 1 {
                if !hideNextButton {
                    Button("Continue") { onNext() }
                        .buttonStyle(.borderedProminent)
                        .tint(.red)
                        .controlSize(.regular)
                }
            } else {
                Button("Get Started") {
                    DispatchQueue.main.async { onFinish() }
                }
                .buttonStyle(.borderedProminent)
                .tint(.red)
                .controlSize(.regular)
            }
        }
    }
}
