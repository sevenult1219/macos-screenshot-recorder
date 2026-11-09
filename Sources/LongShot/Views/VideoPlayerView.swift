import AVFoundation
import AppKit
import SwiftUI

final class VideoPlaybackModel: ObservableObject {
    let player: AVPlayer
    @Published private(set) var isPlaying = false
    @Published private(set) var isReady = false
    @Published private(set) var isMuted = false
    @Published private(set) var duration: Double = 0
    @Published private(set) var currentTime: Double = 0

    private var timeObserver: Any?
    private var endObserver: NSObjectProtocol?
    private var prepared = false
    private let mixesAudioTracks: Bool

    init(url: URL, mixesAudioTracks: Bool) {
        self.mixesAudioTracks = mixesAudioTracks
        player = AVPlayer(url: url)
        player.actionAtItemEnd = .pause
    }

    deinit {
        if let timeObserver {
            player.removeTimeObserver(timeObserver)
        }
        if let endObserver {
            NotificationCenter.default.removeObserver(endObserver)
        }
    }

    func prepare() {
        guard !prepared else { return }
        prepared = true

        timeObserver = player.addPeriodicTimeObserver(
            forInterval: CMTime(seconds: 0.2, preferredTimescale: 600),
            queue: .main
        ) { [weak self] time in
            guard let self else { return }
            let seconds = time.seconds
            guard seconds.isFinite else { return }
            self.currentTime = max(0, seconds)
        }

        if let item = player.currentItem {
            endObserver = NotificationCenter.default.addObserver(
                forName: .AVPlayerItemDidPlayToEndTime,
                object: item,
                queue: .main
            ) { [weak self] _ in
                guard let self else { return }
                self.isPlaying = false
                self.currentTime = self.duration
            }

            Task { @MainActor [weak self] in
                guard let self, let item = self.player.currentItem else { return }
                let assetDuration = try? await item.asset.load(.duration)
                let seconds = assetDuration?.seconds ?? 0
                let safeDuration = seconds.isFinite ? max(0, seconds) : 0
                let audioTracks = (try? await item.asset.loadTracks(withMediaType: .audio)) ?? []
                if self.mixesAudioTracks, !audioTracks.isEmpty {
                    let audioMix = AVMutableAudioMix()
                    audioMix.inputParameters = audioTracks.map { track in
                        let parameters = AVMutableAudioMixInputParameters(track: track)
                        parameters.setVolume(1, at: .zero)
                        return parameters
                    }
                    item.audioMix = audioMix
                }
                self.duration = safeDuration
                self.isReady = true
            }
        } else {
            isReady = true
        }
    }

    func togglePlayback() {
        if isPlaying {
            pause()
        } else {
            play()
        }
    }

    func play() {
        if duration > 0, currentTime >= duration - 0.05 {
            seek(to: 0)
        }
        player.play()
        isPlaying = true
    }

    func pause() {
        player.pause()
        isPlaying = false
    }

    func stop() {
        player.pause()
        isPlaying = false
    }

    func toggleMute() {
        player.isMuted.toggle()
        isMuted = player.isMuted
    }

    func seek(to seconds: Double) {
        let upper = max(duration, 0.01)
        let clamped = min(max(0, seconds), upper)
        currentTime = clamped
        player.seek(
            to: CMTime(seconds: clamped, preferredTimescale: 600),
            toleranceBefore: .zero,
            toleranceAfter: .zero
        )
    }

    func makeTimeText(_ seconds: Double) -> String {
        guard seconds.isFinite, seconds >= 0 else { return "0:00" }
        let total = Int(seconds.rounded())
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}

struct VideoPlayerPanel: View {
    let url: URL
    let thumbnail: NSImage?
    @StateObject private var playback: VideoPlaybackModel

    init(url: URL, thumbnail: NSImage?, mixesAudioTracks: Bool = false) {
        self.url = url
        self.thumbnail = thumbnail
        _playback = StateObject(
            wrappedValue: VideoPlaybackModel(url: url, mixesAudioTracks: mixesAudioTracks)
        )
    }

    var body: some View {
        ZStack {
            Color.black

            PlayerSurface(player: playback.player)

            if !playback.isReady, let thumbnail {
                Image(nsImage: thumbnail)
                    .resizable()
                    .interpolation(.high)
                    .scaledToFit()
                    .background(Color.black)
            }

            if !playback.isReady {
                ProgressView()
                    .controlSize(.small)
                    .tint(.white)
            }

            if !playback.isPlaying, playback.isReady {
                Button {
                    playback.play()
                } label: {
                    Image(systemName: "play.fill")
                        .font(.system(size: 22, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 58, height: 58)
                        .background(Circle().fill(Color.black.opacity(0.58)))
                        .overlay(
                            Circle().strokeBorder(Color.white.opacity(0.20), lineWidth: 0.8)
                        )
                }
                .buttonStyle(.plain)
                .accessibilityLabel("播放")
            }

            VStack {
                Spacer()
                controls
            }
        }
        .background(Color.black)
        .onAppear { playback.prepare() }
        .onDisappear { playback.stop() }
    }

    private var controls: some View {
        VStack(spacing: 6) {
            HStack(spacing: 10) {
                Button {
                    playback.togglePlayback()
                } label: {
                    Image(systemName: playback.isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 26, height: 26)
                        .background(Circle().fill(Color.white.opacity(0.16)))
                }
                .buttonStyle(.plain)
                .disabled(!playback.isReady)
                .accessibilityLabel(playback.isPlaying ? "暂停" : "播放")

                Text(playback.makeTimeText(playback.currentTime))
                    .font(.system(size: 9.5, weight: .medium, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.85))
                    .frame(width: 34, alignment: .trailing)

                Slider(
                    value: Binding(
                        get: { playback.currentTime },
                        set: { playback.seek(to: $0) }
                    ),
                    in: 0...max(playback.duration, 0.01)
                )
                .tint(.white)
                .controlSize(.mini)
                .disabled(!playback.isReady || playback.duration <= 0)

                Text(playback.makeTimeText(playback.duration))
                    .font(.system(size: 9.5, weight: .medium, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.85))
                    .frame(width: 34, alignment: .leading)

                Button {
                    playback.toggleMute()
                } label: {
                    Image(systemName: playback.isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 26, height: 26)
                        .background(Circle().fill(Color.white.opacity(0.16)))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(playback.isMuted ? "取消静音" : "静音")
            }
        }
        .padding(.horizontal, 14)
        .padding(.top, 18)
        .padding(.bottom, 10)
        .background(
            LinearGradient(
                colors: [.clear, Color.black.opacity(0.72)],
                startPoint: .top,
                endPoint: .bottom
            )
        )
    }
}

private struct PlayerSurface: NSViewRepresentable {
    let player: AVPlayer

    func makeNSView(context: Context) -> PlayerLayerView {
        let view = PlayerLayerView()
        view.player = player
        return view
    }

    func updateNSView(_ nsView: PlayerLayerView, context: Context) {
        nsView.player = player
    }
}

private final class PlayerLayerView: NSView {
    private let playerLayer = AVPlayerLayer()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer = playerLayer
        playerLayer.videoGravity = .resizeAspect
        playerLayer.backgroundColor = NSColor.black.cgColor
        playerLayer.needsDisplayOnBoundsChange = true
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    var player: AVPlayer? {
        get { playerLayer.player }
        set { playerLayer.player = newValue }
    }

    override func layout() {
        super.layout()
        playerLayer.frame = bounds
    }
}
