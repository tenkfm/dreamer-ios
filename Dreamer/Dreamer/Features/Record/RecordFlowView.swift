import SwiftUI

/// Full-screen cover hosting Record -> Details -> Analysis over one sky.
struct RecordFlowView: View {
    @State private var viewModel: RecordFlowViewModel

    init(viewModel: RecordFlowViewModel) {
        _viewModel = State(initialValue: viewModel)
    }

    var body: some View {
        ZStack {
            SkyBackground(kind: .full)
                .scaleEffect(viewModel.step == .details ? 1.06 : 1)
                .blur(radius: viewModel.step == .details ? 6 : 0)
                .overlay {
                    DS.Palette.skyDim
                        .opacity(viewModel.step == .details ? 0.14 : 0)
                        .ignoresSafeArea()
                }

            content
                .id(viewModel.step)
                .transition(.stepChange)
        }
        .animation(.soft(0.7), value: viewModel.step)
    }

    @ViewBuilder private var content: some View {
        switch viewModel.step {
        case .record:
            RecordView(viewModel: viewModel.record,
                       onClose: viewModel.cancel,
                       onDone: { Task { await viewModel.finishRecording() } })
        case .details:
            if let details = viewModel.details {
                DetailsView(viewModel: details,
                            onInterpret: { viewModel.interpret(includeDetails: true) },
                            onSkip: { viewModel.interpret(includeDetails: false) })
            }
        case .analysis:
            if let analysis = viewModel.analysis {
                AnalysisView(viewModel: analysis, onContinue: viewModel.showInterpretation, onClose: viewModel.cancel)
            }
        }
    }
}

#Preview {
    RecordFlowView(viewModel: RecordFlowViewModel(
        speech: MockSpeechService(), analysisService: MockDreamAnalysisService(),
        store: InMemoryDreamStore(), onFinish: { _ in }, onCancel: {}))
}
