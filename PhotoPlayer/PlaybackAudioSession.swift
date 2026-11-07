@preconcurrency import AVFoundation
import Foundation

enum PlaybackAudioSession {
    // Session changes can block. Serialize them away from the UI, including close/reopen races.
    private static let queue = DispatchQueue(label: "PhotoPlayer.audio-session")

    static func setActive(_ active: Bool, completion: @escaping @Sendable (String?) -> Void = { _ in }) {
        queue.async {
            do {
                let session = AVAudioSession.sharedInstance()
                if active {
                    try session.setCategory(.playback, mode: .moviePlayback)
                    try session.setActive(true)
                } else {
                    try session.setActive(false, options: .notifyOthersOnDeactivation)
                }
                completion(nil)
            } catch {
                completion(PlaybackPolicy.errorCode(error))
            }
        }
    }
}
