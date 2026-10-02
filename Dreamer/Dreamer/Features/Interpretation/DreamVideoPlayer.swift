import AVFoundation
import AVKit
import SwiftUI

/// The dream film full screen, with its voice-over (heard in silent mode too, like a video) and the
/// system controls.
struct DreamVideoPlayer: View {
    let url: URL
    @Environment(\.dismiss) private var dismiss
    @State private var player = AVPlayer()

    var body: some View {
        ZStack(alignment: .topTrailing) {
            DS.Palette.videoBackdrop.ignoresSafeArea()
            VideoPlayer(player: player)
                .ignoresSafeArea()
            GlassIconButton(systemImage: "xmark", accessibilityLabel: "Close") { dismiss() }
                .padding(.trailing, DS.Space.screen)
                .padding(.top, DS.Space.headerTop)
        }
        .onAppear {
            let session = AVAudioSession.sharedInstance()
            try? session.setCategory(.playback, mode: .moviePlayback)
            try? session.setActive(true)
            player.replaceCurrentItem(with: AVPlayerItem(url: url))
            player.play()
        }
        .onDisappear {
            player.pause()
            try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        }
    }
}
