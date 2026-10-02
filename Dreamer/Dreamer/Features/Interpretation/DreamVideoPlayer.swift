import AVFoundation
import Combine
import SwiftUI

/// The dream film edge to edge, with its voice-over (heard in silent mode too, like a video).
/// Its own player rather than AVKit's: the system player only fits the 9:16 film inside the taller
/// screen, which left black bands above and below. Tap to pause, a thin progress line, Close and
/// Share.
struct DreamVideoPlayer: View {
    let url: URL
    @Bindable var viewModel: InterpretationViewModel

    @Environment(\.dismiss) private var dismiss
    @State private var player = AVPlayer()
    @State private var isPlaying = false

    var body: some View {
        ZStack {
            film
            // Inside the safe area, so the buttons clear the Dynamic Island and the line the home
            // indicator. The spacer takes no taps: they reach the film.
            VStack(spacing: 0) {
                controls
                Spacer(minLength: 0)
                progressLine
            }
        }
        .animation(.soft(0.25), value: isPlaying)
        .statusBarHidden()
        .persistentSystemOverlays(.hidden)
        .toast($viewModel.toastMessage)
        .sheet(item: $viewModel.playerShareItem) { item in
            ActivityView(items: item.activityItems) { activity, completed in
                viewModel.shareSheetClosed(activity: activity, completed: completed)
            }
            .presentationDetents([.medium, .large])
            .ignoresSafeArea()
        }
        .onReceive(NotificationCenter.default.publisher(for: .AVPlayerItemDidPlayToEndTime)
            .receive(on: DispatchQueue.main)) { note in
            // Posted for any item; only this player's end matters.
            guard (note.object as? AVPlayerItem) === player.currentItem else { return }
            isPlaying = false
        }
        .onAppear {
            let session = AVAudioSession.sharedInstance()
            try? session.setCategory(.playback, mode: .moviePlayback)
            try? session.setActive(true)
            player.replaceCurrentItem(with: AVPlayerItem(url: url))
            play()
        }
        .onDisappear {
            player.pause()
            try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        }
    }

    private var film: some View {
        ZStack {
            DS.Palette.videoBackdrop
            // The poster until the first frame, so opening does not flash black.
            if let poster = viewModel.loadedImage {
                Image(uiImage: poster).resizable().scaledToFill()
            }
            PlayerLayerView(player: player)
            if !isPlaying {
                Image(systemName: "play.fill")
                    .font(.system(size: 30, weight: .semibold))
                    .foregroundStyle(DS.Palette.white)
                    .frame(width: 76, height: 76)
                    .glassCapsule()
                    .transition(.opacity.combined(with: .scale(scale: 0.85)))
                    .allowsHitTesting(false)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { togglePlayback() }
        .accessibilityElement()
        .accessibilityLabel("Your dream video")
        .accessibilityAddTraits(.startsMediaSession)
        .accessibilityAction(named: isPlaying ? "Pause" : "Play") { togglePlayback() }
        // Last: with the tap and the label after it, the film drew under the Dynamic Island and the
        // home indicator but took taps only inside the safe area.
        .ignoresSafeArea()
    }

    private var controls: some View {
        HeaderBar {
            GlassIconButton(systemImage: "xmark", accessibilityLabel: "Close") { dismiss() }
        } center: {
            EmptyView()
        } trailing: {
            GlassIconButton(systemImage: "square.and.arrow.up", accessibilityLabel: "Share") {
                pause()
                Task { await viewModel.shareFromPlayer() }
            }
            .overlay {
                if viewModel.isPreparingShare {
                    ProgressView().tint(DS.Palette.textPrimary)
                }
            }
            .disabled(viewModel.isPreparingShare)
            // The screen below has its own "Share", still in the hierarchy under the player.
            .accessibilityIdentifier("videoShare")
        }
    }

    private var progressLine: some View {
        TimelineView(.animation(paused: !isPlaying)) { _ in
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(DS.Palette.white.opacity(0.3))
                    Capsule().fill(DS.Palette.white).frame(width: geo.size.width * progress)
                }
            }
            .frame(height: 3)
        }
        .padding(.horizontal, DS.Space.screen)
        .padding(.bottom, 8)
        .accessibilityHidden(true)
    }

    private var progress: Double {
        guard let duration = player.currentItem?.duration.seconds, duration.isFinite, duration > 0 else { return 0 }
        return min(max(player.currentTime().seconds / duration, 0), 1)
    }

    private func togglePlayback() {
        isPlaying ? pause() : play()
    }

    private func play() {
        // At the end, "play" starts the film again.
        if progress >= 0.999 { player.seek(to: .zero) }
        player.play()
        isPlaying = true
    }

    private func pause() {
        player.pause()
        isPlaying = false
    }
}

/// AVPlayerLayer filling its view: aspect fill crops the film's sides a little instead of
/// letterboxing it.
private struct PlayerLayerView: UIViewRepresentable {
    let player: AVPlayer

    func makeUIView(context: Context) -> LayerView {
        let view = LayerView()
        view.playerLayer.player = player
        view.playerLayer.videoGravity = .resizeAspectFill
        // Clear until the first frame, so the poster behind shows.
        view.backgroundColor = .clear
        return view
    }

    func updateUIView(_ view: LayerView, context: Context) {}

    final class LayerView: UIView {
        override static var layerClass: AnyClass { AVPlayerLayer.self }
        var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }
    }
}
