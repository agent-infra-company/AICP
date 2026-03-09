@preconcurrency import RiveRuntime
import SwiftUI

struct RiveAvatarView: View {
    @StateObject private var viewModel = RiveViewModel(
        fileName: "look",
        in: Bundle.module,
        stateMachineName: nil,
        fit: .contain,
        alignment: .center,
        autoPlay: true
    )

    var body: some View {
        viewModel.view()
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
    }
}
