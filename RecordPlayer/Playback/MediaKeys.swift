import MediaPlayer

/// The Mac's media keys and the Now Playing panel, wired to the turntable.
@MainActor
final class MediaKeys {
    private weak var turntable: TurntableModel?

    func connect(to turntable: TurntableModel) {
        guard self.turntable == nil else { return }
        self.turntable = turntable
        let center = MPRemoteCommandCenter.shared()
        let handle: (@escaping @MainActor (TurntableModel) -> Void) -> (MPRemoteCommandEvent) -> MPRemoteCommandHandlerStatus = {
            action in
            { [weak self] _ in
                Task { @MainActor in
                    if let turntable = self?.turntable { action(turntable) }
                }
                return .success
            }
        }
        center.togglePlayPauseCommand.addTarget(handler: handle { $0.togglePlay() })
        center.playCommand.addTarget(handler: handle { if !($0.isNeedleDown && $0.isMotorOn) { $0.togglePlay() } })
        center.pauseCommand.addTarget(handler: handle { if $0.isNeedleDown && $0.isMotorOn { $0.togglePlay() } })
        center.nextTrackCommand.addTarget(handler: handle { $0.nextTrack() })
        center.previousTrackCommand.addTarget(handler: handle { $0.previousTrack() })
    }

    func update(from turntable: TurntableModel) {
        let info = MPNowPlayingInfoCenter.default()
        guard let track = turntable.nowPlaying else {
            info.nowPlayingInfo = nil
            info.playbackState = .stopped
            return
        }
        info.nowPlayingInfo = [
            MPMediaItemPropertyTitle: track.title,
            MPMediaItemPropertyArtist: track.artist,
            MPMediaItemPropertyAlbumTitle: turntable.record?.title ?? "",
            MPMediaItemPropertyPlaybackDuration: track.duration,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: Double(turntable.elapsedSeconds),
            MPNowPlayingInfoPropertyPlaybackRate: turntable.isMotorOn ? 1.0 : 0.0,
        ]
        info.playbackState = turntable.isMotorOn ? .playing : .paused
    }
}
