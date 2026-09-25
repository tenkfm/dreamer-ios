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
            WaveformBars(count: RecordViewModel.barCount, barWidth: 4, height: 40, spacing: 5, color: DS.Palette.iconSoft,
                         isAnimating: viewModel.isRecording, levels: viewModel.levels)
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
            bottomBar
                .opacity(viewModel.access == .listening || viewModel.access == .unknown ? 1 : 0)
                .enterUp(0.9)
        }
        .overlay {
            switch viewModel.access {
            case .prePrompt:
                MicrophonePrePrompt(onAllow: { Task { await viewModel.requestAccess() } },
                                    onType: viewModel.typeInstead)
                    .transition(.opacity.combined(with: .offset(y: 18)))
            case .blocked(let permission):
                MicrophoneBlocked(permission: permission, onType: viewModel.typeInstead)
                    .transition(.opacity.combined(with: .offset(y: 18)))
            case .unknown, .listening:
                EmptyView()
            }
        }
        .animation(.soft(0.5), value: viewModel.access)
        .onAppear { viewModel.appeared() }
        .onDisappear { viewModel.stop() }
        .sheet(isPresented: $viewModel.isTyping) {
            TypeDreamSheet(text: $viewModel.transcript)
                .scrollEdgeEffectsHidden()
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

/// Our explanation before the system asks for the microphone and speech recognition.
private struct MicrophonePrePrompt: View {
    var onAllow: () -> Void
    var onType: () -> Void

    var body: some View {
        PermissionCard(systemImage: "mic",
                       title: "Tell your dream out loud",
                       message: "Dreamer listens while you talk and writes your dream down for you, so you can tell it with your eyes half closed.") {
            PrimaryButton(title: "Allow microphone", systemImage: "mic", action: onAllow)
            TextLinkButton(title: "Type it instead", action: onType)
        }
    }
}

/// The microphone or speech recognition was refused (or restricted).
private struct MicrophoneBlocked: View {
    var permission: SpeechPermission
    var onType: () -> Void

    @Environment(\.openURL) private var openURL

    var body: some View {
        PermissionCard(systemImage: "mic.slash",
                       title: "The microphone is off",
                       message: permission == .restricted
                           ? "Microphone access is restricted on this iPhone. You can still type your dream."
                           : "Turn on Microphone and Speech Recognition for Dreamer in Settings, or type your dream.") {
            PrimaryButton(title: "Type it instead", systemImage: "keyboard", action: onType)
            if permission == .denied {
                TextLinkButton(title: "Open Settings") {
                    if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                }
            }
        }
    }
}

/// Glass card pinned to the bottom of the Record screen, over the orb and sky.
private struct PermissionCard<Actions: View>: View {
    var systemImage: String
    var title: String
    var message: String
    @ViewBuilder var actions: () -> Actions

    var body: some View {
        VStack {
            Spacer()
            VStack(spacing: 14) {
                Image(systemName: systemImage)
                    .font(.system(size: 24, weight: .light))
                    .foregroundStyle(DS.Palette.icon)
                    .frame(width: 54, height: 54)
                    .softFill(Circle(), opacity: 0.7)
                    .accessibilityHidden(true)
                Text(title).textStyle(.heading).multilineTextAlignment(.center).accessibilityAddTraits(.isHeader)
                Text(message)
                    .textStyle(.secondary, color: DS.Palette.textSecondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                VStack(spacing: 4) { actions() }.padding(.top, 6)
            }
            .padding(.horizontal, DS.Space.cardPaddingLarge)
            .padding(.top, 22)
            .padding(.bottom, 12)
            .glassCard(radius: DS.Radius.cardLarge, style: .selected)
            .padding(.horizontal, DS.Space.screen)
            .padding(.bottom, 12)
        }
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
