import Foundation

/// Centralized manager that decides when the app should perform a device state poll.
/// It encapsulates rate-limit cool-offs and exponential back-off strategies so callers
/// only need to ask `shouldPoll` and record the outcome of each attempt.
struct PollManager {
    /// Internal state for the polling finite-state machine.
    enum State: Equatable {
        /// Everything is healthy – poll on the normal cadence.
        case healthy
        /// We hit the Smart Device Management API rate-limit.  Suspend polling until `until`.
        case rateLimited(until: Date)
        /// Pub/Sub long-polling is not working; fall back to progressive back-off polling.
        case pubSubDown
    }

    /// Maximum poll frequency: 10 devices.get calls per minute.
    private static let minimumPollInterval: TimeInterval = 6.0
    /// How often to recheck health when Pub/Sub is working and the popover is hidden.
    private static let hiddenWindowCheckInterval: TimeInterval = 30.0
    /// Longest backoff interval when Pub/Sub is down and the window is hidden.
    private static let fallbackMaxInterval: TimeInterval = 60.0

    /// Current FSM state. Default is `.healthy`.
    private(set) var state: State = .healthy

    /// Interval used for exponential backoff while Pub/Sub is down.
    private var nextFallbackInterval: TimeInterval = PollManager.minimumPollInterval

    /// Determines whether we should issue a poll right now and what interval the caller should
    /// schedule the next evaluation for.
    /// - Parameters:
    ///   - pubSubActive: `true` if Pub/Sub is working (we can rely on push events).
    ///   - windowVisible: Whether the pop-over window is currently visible to the user.  When the
    ///                    window is hidden we can poll less aggressively.
    /// - Returns: A tuple of `(shouldPoll, nextInterval)`.  If `shouldPoll == false`, callers should
    ///            wait `nextInterval` seconds before asking again.  If `shouldPoll == true`, callers
    ///            should perform a poll now and schedule the next one after `nextInterval` seconds.
    mutating func shouldPoll(pubSubActive: Bool, windowVisible: Bool) -> (should: Bool, interval: TimeInterval) {
        switch state {
        case .healthy:
            guard pubSubActive else {
                state = .pubSubDown
                nextFallbackInterval = PollManager.minimumPollInterval
                return shouldPoll(pubSubActive: pubSubActive, windowVisible: windowVisible)
            }
            if windowVisible {
                return (true, PollManager.minimumPollInterval)
            } else {
                return (false, PollManager.hiddenWindowCheckInterval)
            }

        case .rateLimited(let until):
            // Only resume polling once we are past the cool-off window.
            let now = Date()
            if now < until {
                let wait = max(until.timeIntervalSince(now), PollManager.minimumPollInterval)
                return (false, wait)
            }
            // Cool-off expired – return to healthy state and recompute decision.
            state = pubSubActive ? .healthy : .pubSubDown
            return shouldPoll(pubSubActive: pubSubActive, windowVisible: windowVisible)

        case .pubSubDown:
            if pubSubActive {
                state = .healthy
                nextFallbackInterval = PollManager.minimumPollInterval
                return shouldPoll(pubSubActive: pubSubActive, windowVisible: windowVisible)
            }

            let interval: TimeInterval
            if windowVisible {
                interval = PollManager.minimumPollInterval
            } else {
                interval = nextFallbackInterval
                nextFallbackInterval = min(nextFallbackInterval * 2, PollManager.fallbackMaxInterval)
            }
            return (true, interval)
        }
    }

    /// Call this whenever a poll completes successfully.
    mutating func recordSuccess() {
        nextFallbackInterval = PollManager.minimumPollInterval
        state = .healthy
    }

    /// Call this when a poll fails due to an explicit rate-limit error from the API.
    mutating func recordRateLimit() {
        state = .rateLimited(until: Date().addingTimeInterval(300)) // 5-minute cool-off
        nextFallbackInterval = PollManager.minimumPollInterval
    }

    /// Call this when Pub/Sub has been deemed non-functional so that we switch to back-off mode.
    mutating func recordPubSubFailure() {
        state = .pubSubDown
        nextFallbackInterval = PollManager.minimumPollInterval
    }

    mutating func reset() {
        state = .healthy
        nextFallbackInterval = PollManager.minimumPollInterval
    }
}
