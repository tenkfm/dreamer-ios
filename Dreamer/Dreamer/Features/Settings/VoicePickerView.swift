import SwiftUI

/// Settings -> Voice: All / Male / Female, the voices with a play button each, the checkmark on
/// the picked one, and a line on what the pick changes.
struct VoicePickerView: View {
    @State private var viewModel: VoicePickerViewModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase

    init(viewModel: VoicePickerViewModel) {
        _viewModel = State(initialValue: viewModel)
    }

    var body: some View {
        ZStack {
            ScreenBackground()
            ScrollView {
                VStack(spacing: 16) {
                    HeaderBar(leading: {
                        GlassIconButton(systemImage: "chevron.left", accessibilityLabel: "Back") { dismiss() }
                    }, center: {
                        ScreenTitle(text: "Voice")
                    })
                    .padding(.horizontal, -DS.Space.screen)

                    DreamerSegmented(options: VoicePickerViewModel.Filter.allCases, selection: $viewModel.filter) { $0.title }
                        .padding(.top, 8)
                    content
                }
                .padding(.horizontal, DS.Space.screen)
                .padding(.bottom, 40)
            }
            .scrollIndicators(.hidden)
        }
        .toast($viewModel.toastMessage)
        .haptic(viewModel.haptic)
        .sensoryFeedback(.selection, trigger: viewModel.selectedID)
        .task { await viewModel.load() }
        // No preview keeps talking behind another screen or the lock screen.
        .onDisappear { viewModel.stopPreview() }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active { viewModel.stopPreview() }
        }
    }

    @ViewBuilder private var content: some View {
        switch viewModel.loadState {
        case .loading where viewModel.voices.isEmpty:
            ProgressView().tint(DS.Palette.icon).padding(.top, 40)
        case .failed:
            ErrorStateCard(systemImage: "wifi.slash", title: "Voices didn’t load",
                           message: "Check your connection and try again.", actionTitle: "Try again") {
                Task { await viewModel.load() }
            }
        default:
            SettingsGroup {
                ForEach(Array(viewModel.visibleVoices.enumerated()), id: \.element.id) { index, voice in
                    if index > 0 { SettingsDivider() }
                    VoiceRow(voice: voice,
                             isSelected: voice.id == viewModel.selectedID,
                             isPlaying: voice.id == viewModel.playingID,
                             onPlay: { viewModel.togglePreview(voice) },
                             onSelect: { Task { await viewModel.select(voice) } })
                }
            }
            .animation(.soft(0.35), value: viewModel.filter)
            Text("New dreams will be read in this voice.")
                .textStyle(.secondary, color: DS.Palette.textTertiary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
                .padding(.top, 4)
        }
    }
}

/// Play on the left (listening only), the rest of the row picks the voice.
private struct VoiceRow: View {
    var voice: Voice
    var isSelected: Bool
    var isPlaying: Bool
    var onPlay: () -> Void
    var onSelect: () -> Void

    var body: some View {
        HStack(spacing: 14) {
            Button(action: onPlay) {
                Image(systemName: isPlaying ? "stop.fill" : "play.fill")
                    .font(.system(size: 13, weight: .regular))
                    .foregroundStyle(DS.Palette.icon)
                    .frame(width: 36, height: 36)
                    .background(Circle().fill(DS.Palette.surface))
                    .frame(width: 44, height: 44)
                    .contentShape(Circle())
            }
            .buttonStyle(PressableButtonStyle())
            .disabled(voice.previewURL == nil)
            .opacity(voice.previewURL == nil ? 0.4 : 1)
            .accessibilityLabel(isPlaying ? "Stop \(voice.name)" : "Listen to \(voice.name)")

            Button(action: onSelect) {
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 8) {
                            Text(voice.name).textStyle(.bodyStrong)
                            if voice.isDefault {
                                Text("Default")
                                    .font(DreamerFont.fixed(11))
                                    .foregroundStyle(DS.Palette.textSecondary)
                                    .padding(.horizontal, 8)
                                    .frame(height: 20)
                                    .background(Capsule().fill(DS.Palette.surface.opacity(0.9)))
                            }
                        }
                        Text(voice.description)
                            .textStyle(.secondary, color: DS.Palette.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                        Text(voice.previewURL == nil ? String(localized: "Preview coming soon") : voice.accent.capitalized)
                            .textStyle(.label, color: DS.Palette.textTertiary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    Image(systemName: "checkmark")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(DS.Palette.icon)
                        .opacity(isSelected ? 1 : 0)
                        .scaleEffect(isSelected ? 1 : 0.6)
                        .animation(.pop, value: isSelected)
                }
                .padding(.vertical, 12)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(isSelected ? [.isSelected] : [])
        }
        .padding(.leading, 10)
        .padding(.trailing, 18)
    }
}

#Preview {
    VoicePickerView(viewModel: VoicePickerViewModel(appState: .preview(), service: MockVoiceService(), player: AVVoicePlayback()))
}
