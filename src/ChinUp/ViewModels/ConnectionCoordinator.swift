//
//  ConnectionCoordinator.swift
// ChinUp
//
//  Created by NG on 20/01/26.
//

import Foundation
import SwiftUI

enum ConnectionState: Equatable {
    case disconnected
    case connecting
    case connected
    case error(String)

    var isConnected: Bool {
        if case .connected = self { return true }
        return false
    }

    var canStartTracking: Bool {
        if case .disconnected = self { return true }
        if case .error = self { return true }
        return false
    }

    var title: String {
        switch self {
        case .disconnected: return "Connect AirPods"
        case .connecting: return "Connecting..."
        case .connected: return "Connected"
        case .error: return "Connection Failed"
        }
    }

    var detail: String {
        switch self {
        case .disconnected:
            return "Put on your AirPods and hold your head high"
        case .connecting:
            return "Hang tight—we're connecting to your AirPods. This may take a few moments."
        case .connected:
            return "You're all set! Straighten up your workday"
        case .error:
            return "Hmm, we couldn't connect. Let's give it another go."
        }
    }
}

/// Owns the connect → timeout → back-off → retry ladder that sits between the
/// view and `HeadphoneMotionViewModel`.
@MainActor
final class ConnectionCoordinator: ObservableObject {
    @Published private(set) var state: ConnectionState = .disconnected
    @Published private(set) var isRetrying = false
    @Published private(set) var attempts = 0

    private let motion: HeadphoneMotionViewModel
    private var retryTask: Task<Void, Never>?
    private var timeoutTask: Task<Void, Never>?

    private let connectionTimeout: TimeInterval = 10
    private let baseRetryDelay: TimeInterval = 30
    private let maxRetryDelay: TimeInterval = 600

    init(motion: HeadphoneMotionViewModel) {
        self.motion = motion
    }

    // MARK: - Session Control

    /// A deliberate tap restarts the backoff ladder; only unattended failures escalate.
    func startSession() {
        guard state.canStartTracking else { return }

        cancelScheduledWork()
        attempts = 1
        attemptConnection()
    }

    func stopSession() {
        cancelScheduledWork()
        withAnimation(.easeInOut(duration: 0.3)) {
            motion.stopTracking()
            state = .disconnected
            isRetrying = false
            attempts = 0
        }
    }

    func cancelConnection() {
        cancelScheduledWork()
        motion.stopTracking()
        state = .disconnected
        isRetrying = false
        attempts = 0
    }

    func pauseSession(duration: TimeInterval?) {
        withAnimation(.easeInOut(duration: 0.3)) {
            motion.pauseSession(duration: duration, reason: .pausedManual)
        }
    }

    func resumeSession() {
        withAnimation(.easeInOut(duration: 0.3)) {
            motion.resumeSession()
        }
    }

    // MARK: - Motion State Sync

    /// Deferred by a hop: callers are SwiftUI `onChange` handlers running inside a
    /// view update, and publishing from there would mutate state mid-render.
    func syncWithMotionState() {
        Task { [weak self] in
            self?.applyMotionState()
        }
    }

    private func applyMotionState() {
        if motion.isConnected {
            cancelScheduledWork()
            state = .connected
            isRetrying = false
            attempts = 0
        } else if retryTask != nil {
            // A backoff retry is already pending — keep the countdown on screen
            // instead of letting stopTracking()'s "Disconnected" reset us to idle.
            return
        } else if motion.connectionStatus.contains("Error") || motion.connectionStatus.contains("not available") {
            isRetrying = false
            if attempts > 0 {
                // startTracking() bails out before the timeout is armed when no
                // motion-capable AirPods are paired. Retry anyway — they may be
                // put on later, which is the whole point of the backoff.
                timeoutTask?.cancel()
                timeoutTask = nil
                handleConnectionFailure(reason: motion.connectionStatus + ".")
            } else {
                state = .error(motion.connectionStatus)
            }
        } else if motion.connectionStatus == "Connecting..." {
            state = .connecting
        } else {
            state = .disconnected
            isRetrying = false
        }
    }

    // MARK: - Retry Ladder

    /// 30s, 60, 120, 240, 480, then held at 600 for as long as the app stays open.
    private func retryDelay(forAttempt attempt: Int) -> TimeInterval {
        let exponent = min(max(0, attempt - 1), 16)
        return min(baseRetryDelay * pow(2, Double(exponent)), maxRetryDelay)
    }

    private func attemptConnection() {
        state = .connecting
        isRetrying = true

        withAnimation(.easeInOut(duration: 0.3)) {
            motion.startTracking()
        }

        timeoutTask?.cancel()
        let timeout = connectionTimeout
        timeoutTask = Task { [weak self] in
            guard await Task.sleepUninterrupted(timeout) else { return }
            guard let self, case .connecting = state else { return }
            timeoutTask = nil
            handleConnectionFailure()
        }
    }

    private func handleConnectionFailure(reason: String = "Couldn't connect.") {
        let delay = retryDelay(forAttempt: attempts)

        // Register the pending retry *before* stopping tracking. stopTracking()
        // flips connectionStatus to "Disconnected", and applyMotionState()
        // would otherwise reset us to .disconnected and strip the countdown.
        retryTask = Task { [weak self] in
            guard await Task.sleepUninterrupted(delay) else { return }
            guard let self else { return }
            retryTask = nil
            guard case .error = state else { return }
            attempts += 1
            attemptConnection()
        }

        motion.stopTracking()

        state = .error(retryMessage(reason: reason, delay: delay))
        isRetrying = false

        Logging.log("🔌 [RETRY] Attempt \(attempts) failed, retrying in \(Int(delay))s")
    }

    private func retryMessage(reason: String, delay: TimeInterval) -> String {
        let interval: String
        if delay >= 60 {
            let minutes = Int(delay / 60)
            interval = minutes == 1 ? "1 minute" : "\(minutes) minutes"
        } else {
            interval = "\(Int(delay)) seconds"
        }
        return "\(reason) Retrying in \(interval)."
    }

    private func cancelScheduledWork() {
        retryTask?.cancel()
        retryTask = nil
        timeoutTask?.cancel()
        timeoutTask = nil
    }
}

private extension Task where Success == Never, Failure == Never {
    /// Sleeps for `seconds`, returning `false` if the surrounding task was cancelled.
    static func sleepUninterrupted(_ seconds: TimeInterval) async -> Bool {
        do {
            try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            return !Task.isCancelled
        } catch {
            return false
        }
    }
}
