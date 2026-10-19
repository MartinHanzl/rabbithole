import SwiftUI

struct OnboardingView: View {
    @State var viewModel: OnboardingViewModel
    let onFinish: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Co tě zajímá?")
                        .font(.readingTitle(.largeTitle))
                    Text("Vyber si aspoň tři témata. Podle nich ti budeme nabízet krátké články z Wikipedie. Výběr můžeš kdykoli změnit v nastavení.")
                        .foregroundStyle(.secondary)
                }
                TopicPickerGrid(selection: $viewModel.selection)
            }
            .padding()
            .frame(maxWidth: Theme.readingWidth)
            .frame(maxWidth: .infinity)
        }
        .background(Theme.screenBackground)
        .safeAreaInset(edge: .bottom) {
            Button {
                viewModel.finish()
                onFinish()
            } label: {
                Group {
                    if viewModel.canContinue {
                        Text("Pokračovat")
                    } else {
                        Text("Vyber ještě \(viewModel.remaining)")
                    }
                }
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
            }
            .buttonStyle(.borderedProminent)
            .disabled(!viewModel.canContinue)
            .padding()
            .frame(maxWidth: Theme.readingWidth)
            .background(.bar)
        }
    }
}
