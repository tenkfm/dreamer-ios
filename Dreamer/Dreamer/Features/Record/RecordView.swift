import SwiftUI

/// 08 Record.
struct RecordView: View {
    @Bindable var viewModel: RecordViewModel
    var onClose: () -> Void
    var onDone: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            header.enterUp(0.1)
            OrbView(glyph: .mic, size: .record, isActive: viewModel.isRecording)
                .padding(.top, 30)
                .enterUp(0.25)
                .accessibilityHidden(true)
            WaveformBars(count: 24, barWidth: 4, height: 40, spacing: 5, color: DS.Palette.iconSoft, isAnimating: viewModel.isRecording)
                .padding(.top, 34)
                .enterUp(0.4)
            // Short text sits right under the waveform; long text keeps its newest line in view.
            GeometryReader { geo in
                ScrollView {
                    CaretText(text: viewModel.transcript, style: .lead, showsCaret: viewModel.isRecording)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity)
                        .padding(.horizontal, DS.Space.cta)
                        .padding(.vertical, 8)
                        .frame(minHeight: geo.size.height, alignment: .top)
                }
                .defaultScrollAnchor(.bottom)
                .scrollIndicators(.hidden)
            }
            .padding(.top, 22)
            .enterUp(0.5)
            .accessibilityLabel(viewModel.transcript.isEmpty ? "Listening" : viewModel.transcript)
            bottomBar.enterUp(0.9)
        }
        .onAppear { viewModel.start() }
        .onDisappear { viewModel.stop() }
        .sheet(isPresented: $viewModel.isTyping) {
            TypeDreamSheet(text: $viewModel.transcript)
        }
    }

    private var header: some View {
        HeaderBar {
            GlassIconButton(systemImage: "xmark", accessibilityLabel: "Close", action: onClose)
        } center: {
            HStack(spacing: 10) {
                PulsingDot()
                    .opacity(viewModel.isRecording ? 1 : 0.4)
                Text(viewModel.isRecording ? "Recording" : "Paused")
                    .font(DreamerFont.fixed(12))
                Text(viewModel.timerText)
                    .font(DreamerFont.fixed(12))
                    .monospacedDigit()
            }
            .foregroundStyle(DS.Palette.textPrimary)
            .padding(.horizontal, 16)
            .frame(height: 34)
            .glassCapsule()
            .accessibilityElement(children: .combine)
        }
    }

    private var bottomBar: some View {
        HStack(spacing: 14) {
            GlassIconButton(systemImage: "keyboard", accessibilityLabel: "Type instead",
                            size: DS.Size.primaryButton, style: .selected) {
                viewModel.switchToTyping()
            }
            PrimaryButton(title: "I’m done", systemImage: "checkmark", action: onDone)
                .disabled(viewModel.trimmedTranscript.isEmpty)
                .opacity(viewModel.trimmedTranscript.isEmpty ? 0.6 : 1)
        }
        .padding(.horizontal, DS.Space.cta)
        .padding(.bottom, 8)
    }
}

/// Keyboard fallback: type or correct the dream.
private struct TypeDreamSheet: View {
    @Binding var text: String
    @Environment(\.dismiss) private var dismiss
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Your dream").textStyle(.heading)
                Spacer()
                Button("Done") { dismiss() }
                    .font(TextStyle.bodyStrong.font)
                    .foregroundStyle(DS.Palette.cta)
                    .frame(minHeight: 44)
            }
            TextEditor(text: $text)
                .textStyle(.body)
                .scrollContentBackground(.hidden)
                .focused($focused)
                .padding(12)
                .glassCard()
        }
        .padding(DS.Space.screen)
        .background(DS.Palette.background.ignoresSafeArea())
        .presentationDetents([.medium, .large])
        .presentationCornerRadius(DS.Radius.sheet)
        .onAppear { focused = true }
    }
}

#Preview {
    ZStack {
        SkyBackground(kind: .full)
        RecordView(viewModel: RecordViewModel(speech: MockSpeechService()), onClose: {}, onDone: {})
    }
}
