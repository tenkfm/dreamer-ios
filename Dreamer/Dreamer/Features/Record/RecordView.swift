import SwiftUI

/// 08 Record.
struct RecordView: View {
    @Bindable var viewModel: RecordViewModel
    var onClose: () -> Void
    var onDone: () -> Void

    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        VStack(spacing: 0) {
            header
            OrbView(glyph: .mic, size: .record, isActive: viewModel.isRecording)
                .contentShape(Circle())
                .onTapGesture { viewModel.resume() }
                .padding(.top, 30)
                .accessibilityHidden(!viewModel.canContinue)
                .accessibilityLabel("Continue recording")
                .accessibilityAddTraits(.isButton)
            WaveformBars(count: RecordViewModel.barCount, barWidth: 4, height: 40, spacing: 5, color: DS.Palette.iconSoft,
                         isAnimating: viewModel.isRecording, levels: viewModel.levels)
                .padding(.top, 34)
            // Short text sits right under the waveform; long text keeps its newest line in view.
            GeometryReader { geo in
                ScrollView {
                    transcriptText
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
            .accessibilityLabel(viewModel.transcript.isEmpty ? liveTextNote ?? "Listening" : viewModel.transcript)
            pauseNote
            bottomBar
                .opacity(viewModel.access == .listening || viewModel.access == .unknown ? 1 : 0)
        }
        .onChange(of: scenePhase) { _, phase in
            // Home, lock screen or app switcher: stop listening and keep the words.
            if phase == .background { viewModel.enteredBackground() }
        }
        .sensoryFeedback(.start, trigger: viewModel.isRecording) { _, recording in recording }
        .sensoryFeedback(.stop, trigger: viewModel.isRecording) { _, recording in !recording }
        .sensoryFeedback(.warning, trigger: viewModel.isNearTimeLimit) { _, near in near }
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
        .animation(.soft(0.4), value: viewModel.serverTranscription)
        .onAppear { viewModel.appeared() }
        .trackScreen(.record)
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
                if viewModel.isNearTimeLimit {
                    Text("\(viewModel.secondsLeft) s left")
                        .font(DreamerFont.fixed(12, .medium))
                        .foregroundStyle(DS.Palette.recordDot)
                        .monospacedDigit()
                        .contentTransition(.numericText(countsDown: true))
                } else {
                    Text(viewModel.timerText)
                        .font(DreamerFont.fixed(12))
                        .monospacedDigit()
                }
            }
            .foregroundStyle(DS.Palette.textPrimary)
            .padding(.horizontal, 16)
            .frame(height: 34)
            .glassCapsule()
            .accessibilityElement(children: .combine)
        }
    }

    /// The words as they are recognized; without live text, what happens to the recording instead.
    @ViewBuilder private var transcriptText: some View {
        if viewModel.transcript.isEmpty, let note = liveTextNote {
            VStack(spacing: 14) {
                if viewModel.isTranscribing {
                    ProgressView()
                        .tint(DS.Palette.textSecondary)
                }
                Text(note)
                    .textStyle(.secondary, color: DS.Palette.textSecondary)
            }
            .transition(.opacity)
        } else {
            CaretText(text: viewModel.transcript, style: .lead, showsCaret: viewModel.isRecording)
        }
    }

    private var liveTextNote: String? {
        if viewModel.isTranscribing { return "Writing down your dream…" }
        if viewModel.isLiveTextUnavailable && viewModel.serverTranscription == nil {
            return "Keep talking - your words will appear when you’re done."
        }
        return nil
    }

    /// Why the recording stopped, and the way to go on.
    @ViewBuilder private var pauseNote: some View {
        if let message = viewModel.pauseMessage {
            VStack(spacing: 6) {
                Text(message)
                    .textStyle(.secondary, color: DS.Palette.textSecondary)
                    .multilineTextAlignment(.center)
                if case .failed(let failure) = viewModel.serverTranscription, failure.canRetry {
                    PillButton(title: "Try again", action: onDone)
                } else if viewModel.canContinue {
                    PillButton(title: "Continue recording") { viewModel.resume() }
                }
            }
            .padding(.horizontal, DS.Space.cta)
            .padding(.bottom, 10)
            .transition(.opacity)
        }
    }

    private var bottomBar: some View {
        HStack(spacing: 14) {
            GlassIconButton(systemImage: "keyboard", accessibilityLabel: "Type instead",
                            size: DS.Size.primaryButton, style: .selected) {
                viewModel.switchToTyping()
            }
            PrimaryButton(title: "I’m done", systemImage: "checkmark", isLoading: viewModel.isTranscribing, action: onDone)
                .disabled(!viewModel.canFinish)
                .opacity(viewModel.canFinish || viewModel.isTranscribing ? 1 : 0.6)
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
