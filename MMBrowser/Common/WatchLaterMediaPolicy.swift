import Foundation

/// Local rules for Watch Later / offline media (no Firebase Remote Config).
/// Matches the former Remote Config default `watch_later_blacklist = {"domains":["*"]}`: fail closed.
enum WatchLaterMediaPolicy {
    /// Offline local media playback / save is not allowed for any host.
    /// Call sites still check `OfflineMediaCopyrightPolicy` first for a clearer copyright toast.
    static func allowsOfflineMedia(on url: URL?) -> Bool {
        _ = url
        return false
    }

    /// Media for this page must use the network (Open Live).
    static func requiresOnlineMedia(for _: URL?) -> Bool {
        true
    }

    static let onlineMediaRequiredNotice =
        "Media on this site requires a network connection. Use Open Live to play."
}
