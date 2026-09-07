import Foundation
import CoreMotion
import Combine
import SwiftUI
import UIKit // Needed for UIApplication state check

@MainActor
class HeadphoneMotionViewModel: ObservableObject {
    // MARK: - Published Properties
    @Published var pitch: Double = 0
    @Published var roll: Double = 0
    @Published var yaw: Double = 0
    @Published var isConnected = false
    @Published var connectionStatus = "Not Connected"
    @Published var postureQuality: PostureQuality = .good
    @Published var pitchHistory: [Double] = []
    @Published var poorPostureDuration: TimeInterval = 0
    @Published var sessionDuration: TimeInterval = 0
    @Published var poorPosturePercentage: Int = 0
    @Published var isTracking = false
    @Published var sessionState: SessionState = .active
    @Published var pauseRemainingSeconds: TimeInterval = 0

    // MARK: - Private Properties
    private let motionManager = CMHeadphoneMotionManager()
    private var updateTimer: Timer?
    private var poorPostureStartTime: Date?
    private var sessionStartTime = Date()
    /// Counts processed motion samples; used only to throttle diagnostic logging.
    private var pitchCount: Int = 0
    private var lastPoorPostureCheck: Date?
    private var shouldUpdateUI = true // Only update UI when app is active
    private var internalPoorPostureDuration: TimeInterval = 0 // Internal state for poor posture duration
    private var internalPostureQuality: PostureQuality = .good // Internal state for alerts, doesn't trigger UI
    
    // Logging helpers
    private var lastBackgroundLog: Date?

    // Pause state
    private var pauseTimer: Timer?
    private var pauseEndTime: Date?
    private var pauseDurationSeconds: TimeInterval = 0
    private var accumulatedSessionDuration: TimeInterval = 0 // Session time before pause
    private var lastActiveTime: Date? // Last time session was active

    // Auto-pause detection
    private var recentPitchValues: [Double] = []
    private var flatDetectionStart: Date?
    private var wearDetectionStart: Date?
    private let flatDetectionThreshold: TimeInterval = 5.0 // 5 seconds of flat detection
    private let horizontalAngleThreshold: Double = 75.0 // Pitch > 75° or < -75° is considered horizontal
    private let motionVarianceThreshold: Double = 2.0 // Low variance indicates no motion

    // Disconnect detection - detects frozen motion data
    private var lastMotionValues: (pitch: Double, roll: Double, yaw: Double)?
    private var frozenMotionCount: Int = 0
    private let frozenMotionThreshold: Int = 3 // 3 consecutive identical readings = disconnected

    // MARK: - Settings (from UserDefaults)
    private var lowerPostureThreshold: Double {
        UserDefaults.standard.double(forKey: "lowerPostureThreshold")
    }
    private var upperPostureThreshold: Double {
        UserDefaults.standard.double(forKey: "upperPostureThreshold")
    }
    private var warningThreshold: Double {
        lowerPostureThreshold + 1.0 // Warning is 1 degree less severe than poor
    }

    // MARK: - Constants
    private let maxHistoryPoints = 100
    private let pollingInterval: TimeInterval = 1.0 // Poll every 1 second for battery efficiency
    private let lyingDownThreshold: Double = 40.0 // No alerts when lying down (pitch >= 40°)
    
    // MARK: - Posture Quality
    enum PostureQuality {
        case good
        case warning
        case poorChinLow   // Chin tilted too far down
        case poorChinHigh  // Chin tilted too far up
        
        var color: Color {
            switch self {
            case .good: return .green
            case .warning: return .orange
            case .poorChinLow, .poorChinHigh: return .red
            }
        }
        
        var icon: String {
            switch self {
            case .good: return "checkmark.circle.fill"
            case .warning: return "exclamationmark.triangle.fill"
            case .poorChinLow, .poorChinHigh: return "xmark.circle.fill"
            }
        }
        
        var message: String {
            switch self {
            case .good: return "Looking great!"
            case .warning: return "Getting there!"
            case .poorChinLow: return "Chin up!"
            case .poorChinHigh: return "Lower your chin!"
            }
        }
        
        var isPoor: Bool {
            switch self {
            case .poorChinLow, .poorChinHigh: return true
            default: return false
            }
        }
    }
    
    // MARK: - Initialization
    init() {
        setupMotionUpdates()
    }
    
    deinit {
        // Clean up resources directly without capturing self
        motionManager.stopDeviceMotionUpdates()
        updateTimer?.invalidate()
    }
    
    // MARK: - Public Methods
    func startTracking() {
        guard motionManager.isDeviceMotionAvailable else {
            connectionStatus = "AirPods Pro not available"
            return
        }

        resetSession()
        connectionStatus = "Connecting..."
        isTracking = true

        // Start device motion updates (needed for polling to work)
        motionManager.startDeviceMotionUpdates()

        // A retry can call this without a stopTracking() in between; without this
        // the previous timer stays scheduled on the run loop and keeps polling.
        updateTimer?.invalidate()

        // Use polling instead of continuous callback for battery efficiency
        updateTimer = Timer.scheduledTimer(withTimeInterval: pollingInterval, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.pollMotionData()
            }
        }

        // Initial poll to get immediate data
        Task {
            try? await Task.sleep(nanoseconds: 500_000_000) // Wait 0.5s for first reading
            pollMotionData()
        }
    }

    /// Call this when app goes to background - tracking continues but UI updates stop
    func setUIUpdateEnabled(_ enabled: Bool) {
        if shouldUpdateUI != enabled {
            Logging.log("🎨 [UI UPDATES] Changed from \(shouldUpdateUI) → \(enabled)")
        }
        shouldUpdateUI = enabled
        
        if enabled {
            // Force update UI with current internal state
            sessionDuration = Date().timeIntervalSince(sessionStartTime)
            poorPostureDuration = internalPoorPostureDuration
            poorPosturePercentage = sessionDuration > 0 ? Int((internalPoorPostureDuration / sessionDuration) * 100) : 0
            
            // Sync posture quality
            if postureQuality != internalPostureQuality {
                postureQuality = internalPostureQuality
            }
        }
    }
    
    /// Polls the current motion data from the headphones
    private func pollMotionData() {
        // --- DIAGNOSTIC LOGGING ---
        let now = Date()
        if lastBackgroundLog == nil || now.timeIntervalSince(lastBackgroundLog!) > 10.0 {
            lastBackgroundLog = now
            let appState = UIApplication.shared.applicationState
            let stateString: String
            switch appState {
            case .active: stateString = "ACTIVE"
            case .inactive: stateString = "INACTIVE"
            case .background: stateString = "BACKGROUND"
            @unknown default: stateString = "UNKNOWN"
            }
            Logging.log("💓 [HEARTBEAT] AppState: \(stateString), Tracking: \(isTracking), UIUpdates: \(shouldUpdateUI)")
        }
        // ---------------------------

        guard let motion = motionManager.deviceMotion else {
            Logging.log("🔌 [POLL] ❌ No motion data available (deviceMotion is nil)")

            // No motion data at all - consider disconnected
            if isConnected {
                Logging.log("🔌 [DISCONNECT] ⚠️⚠️⚠️ AirPods DISCONNECTED - deviceMotion returned nil")
                isConnected = false
                connectionStatus = "Disconnected"

                if sessionState.isActive {
                    Logging.log("🔌 [DISCONNECT] Auto-pausing session indefinitely")
                    pauseSession(duration: nil, reason: .pausedDisconnected)
                    sendAirPodsDisconnectedNotification()
                }
            }

            return
        }

        // Process motion data (will check if frozen)
        processMotionData(motion)
    }
    
    func stopTracking() {
        motionManager.stopDeviceMotionUpdates()
        updateTimer?.invalidate()
        updateTimer = nil
        pauseTimer?.invalidate()
        pauseTimer = nil
        isTracking = false
        isConnected = false
        connectionStatus = "Disconnected"
        sessionState = .active
    }

    func pauseSession(duration: TimeInterval?, reason: SessionState) {
        guard sessionState.isActive else { return }

        // Store accumulated duration up to this point
        accumulatedSessionDuration = Date().timeIntervalSince(sessionStartTime)
        lastActiveTime = Date()

        sessionState = reason
        pauseDurationSeconds = duration ?? 0

        // Finalize any accumulated poor posture time before pausing
        // This prevents the pause duration from being incorrectly added to poor posture time
        if poorPostureStartTime != nil, let lastCheck = lastPoorPostureCheck {
            let now = Date()
            internalPoorPostureDuration += now.timeIntervalSince(lastCheck)
            
            if shouldUpdateUI {
                poorPostureDuration = internalPoorPostureDuration
            }
        }
        poorPostureStartTime = nil
        lastPoorPostureCheck = nil

        // Clear removal detection state
        flatDetectionStart = nil
        wearDetectionStart = nil
        recentPitchValues.removeAll()

        // Only clear disconnect detection state for non-disconnect pauses
        // For disconnect pauses, we need to keep tracking frozen state
        if reason != .pausedDisconnected {
            frozenMotionCount = 0
            lastMotionValues = nil
        }

        if let duration = duration {
            // Set up timed pause
            pauseEndTime = Date().addingTimeInterval(duration)
            pauseRemainingSeconds = duration

            // Start countdown timer
            pauseTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.updatePauseTimer()
                }
            }
        } else {
            // Indefinite pause
            pauseEndTime = nil
            pauseRemainingSeconds = 0
        }

        Logging.log("⏸️ [PAUSE] Session paused: \(sessionState.displayName), duration: \(duration.map { "\($0)s" } ?? "indefinite")")
    }

    func resumeSession() {
        guard sessionState.isPaused else {
            Logging.log("▶️ [RESUME] ⚠️ Cannot resume - session not paused (state: \(sessionState.displayName))")
            return
        }

        Logging.log("▶️ [RESUME] Resuming from state: \(sessionState.displayName)")

        // Stop pause timer
        pauseTimer?.invalidate()
        pauseTimer = nil
        pauseEndTime = nil
        pauseRemainingSeconds = 0

        // Update session start time to account for pause
        let pausedDuration = Date().timeIntervalSince(lastActiveTime ?? Date())
        sessionStartTime = sessionStartTime.addingTimeInterval(pausedDuration)

        sessionState = .active
        lastActiveTime = nil

        Logging.log("▶️ [RESUME] ✅ Session RESUMED - now Active")
    }

    private func updatePauseTimer() {
        guard let endTime = pauseEndTime else { return }

        let remaining = endTime.timeIntervalSince(Date())

        if remaining <= 0 {
            // Pause expired - extend by same duration
            Logging.log("⏰ [PAUSE] Timer expired, extending by \(pauseDurationSeconds)s")
            pauseEndTime = Date().addingTimeInterval(pauseDurationSeconds)
            pauseRemainingSeconds = pauseDurationSeconds

            // Send notification to user asking if they want to continue
            sendPauseExpiredNotification()
        } else {
            pauseRemainingSeconds = remaining
        }
    }

    private func detectAirPodsRemoval(pitch: Double) {
        guard sessionState.isActive else {
            flatDetectionStart = nil
            return
        }

        // Track recent pitch values for variance calculation
        recentPitchValues.append(pitch)
        if recentPitchValues.count > 10 {
            recentPitchValues.removeFirst()
        }

        // Calculate variance (need at least 5 readings)
        guard recentPitchValues.count >= 5 else { return }

        let variance = calculateVariance(values: recentPitchValues)
        let isNearlyHorizontal = abs(pitch) > horizontalAngleThreshold
        let hasLowMotion = variance < motionVarianceThreshold

        // Log every 5 polls to see detection status
        if pitchCount % 5 == 0 {
            Logging.log("📱 [REMOVAL CHECK] Raw pitch: \(String(format: "%.1f", pitch))°, variance: \(String(format: "%.2f", variance)), horizontal: \(isNearlyHorizontal), lowMotion: \(hasLowMotion)")
        }

        if isNearlyHorizontal && hasLowMotion {
            // Start or continue detection timer
            if flatDetectionStart == nil {
                flatDetectionStart = Date()
                Logging.log("📱 [REMOVAL] ⚠️ Detection STARTED - pitch: \(String(format: "%.1f", pitch))°, variance: \(String(format: "%.2f", variance))")
            } else if let start = flatDetectionStart {
                let detectionDuration = Date().timeIntervalSince(start)
                Logging.log("📱 [REMOVAL] ⏱️ Detection ongoing (\(String(format: "%.1f", detectionDuration))s / \(flatDetectionThreshold)s)")

                if detectionDuration >= flatDetectionThreshold {
                    // AirPods likely removed - auto-pause
                    Logging.log("🎧 [REMOVAL] ✅ AirPods removed detected! Auto-pausing session")
                    pauseSession(duration: nil, reason: .pausedRemoved)
                    sendAirPodsRemovedNotification()
                    flatDetectionStart = nil
                    recentPitchValues.removeAll()
                }
            }
        } else {
            // Reset detection if conditions no longer met
            if flatDetectionStart != nil {
                Logging.log("📱 [REMOVAL] ❌ Detection RESET - pitch: \(String(format: "%.1f", pitch))°, variance: \(String(format: "%.2f", variance))")
            }
            flatDetectionStart = nil
        }
    }

    /// Mirror of `detectAirPodsRemoval` for the way back: once removal has paused the
    /// session, sustained non-horizontal pitch means they are back in an ear. Deliberately
    /// gated on angle alone — someone wearing AirPods while sitting still produces the same
    /// low variance as a pair lying on a desk, so variance cannot distinguish the two here.
    private func detectAirPodsWorn(pitch: Double) {
        guard sessionState == .pausedRemoved else {
            wearDetectionStart = nil
            return
        }

        guard abs(pitch) <= horizontalAngleThreshold else {
            wearDetectionStart = nil
            return
        }

        guard let start = wearDetectionStart else {
            wearDetectionStart = Date()
            Logging.log("🎧 [WEAR] ⚠️ Detection STARTED - pitch: \(String(format: "%.1f", pitch))°")
            return
        }

        if Date().timeIntervalSince(start) >= flatDetectionThreshold {
            Logging.log("🎧 [WEAR] ✅ AirPods worn again - AUTO-RESUMING session")
            wearDetectionStart = nil
            resumeSession()
            sendAirPodsReconnectedNotification()
        }
    }

    private func calculateVariance(values: [Double]) -> Double {
        guard !values.isEmpty else { return 0 }

        let mean = values.reduce(0, +) / Double(values.count)
        let squaredDifferences = values.map { pow($0 - mean, 2) }
        let variance = squaredDifferences.reduce(0, +) / Double(values.count)
        return variance
    }


    private func checkForReconnection() {
        Logging.log("🔌 [RECONNECT CHECK] sessionState: \(sessionState.displayName), isConnected: \(isConnected)")

        if sessionState == .pausedDisconnected && isConnected {
            Logging.log("🔌 [RECONNECT] ✅✅✅ AirPods reconnected - AUTO-RESUMING session")
            resumeSession()
            sendAirPodsReconnectedNotification()
        }
    }

    // MARK: - Notification Methods

    private func sendPauseExpiredNotification() {
        NotificationManager.shared.sendPauseExpiredNotification()
    }

    private func sendAirPodsRemovedNotification() {
        NotificationManager.shared.sendAirPodsRemovedNotification()
    }

    private func sendAirPodsDisconnectedNotification() {
        NotificationManager.shared.sendAirPodsDisconnectedNotification()
    }

    private func sendAirPodsReconnectedNotification() {
        NotificationManager.shared.sendAirPodsReconnectedNotification()
    }
    
    func resetSession() {
        pitchHistory.removeAll()
        poorPostureDuration = 0
        internalPoorPostureDuration = 0
        sessionDuration = 0
        poorPosturePercentage = 0
        poorPostureStartTime = nil
        lastPoorPostureCheck = nil
        sessionStartTime = Date()
        pitchCount = 0
        NotificationManager.shared.resetLastNotificationTime()
    }
    
    // MARK: - Private Methods
    private func setupMotionUpdates() {
        // No-op: motion updates are now started in startTracking with polling
    }
    
    private func processMotionData(_ motion: CMDeviceMotion) {
        let newPitch = motion.attitude.pitch * 180 / .pi
        let newRoll = motion.attitude.roll * 180 / .pi
        let newYaw = motion.attitude.yaw * 180 / .pi

        // Check if motion data is frozen (same values = disconnected)
        if let lastValues = lastMotionValues {
            // Compare with very small tolerance (0.001 degrees)
            let pitchDiff = abs(newPitch - lastValues.pitch)
            let rollDiff = abs(newRoll - lastValues.roll)
            let yawDiff = abs(newYaw - lastValues.yaw)

            if pitchDiff < 0.001 && rollDiff < 0.001 && yawDiff < 0.001 {
                frozenMotionCount += 1
                Logging.log("🔌 [MOTION FROZEN] Count: \(frozenMotionCount)/\(frozenMotionThreshold) - pitch: \(String(format: "%.3f", newPitch))°")

                if frozenMotionCount >= frozenMotionThreshold {
                    // Motion data is frozen - AirPods disconnected
                    if isConnected {
                        Logging.log("🔌 [DISCONNECT] ⚠️⚠️⚠️ AirPods DISCONNECTED - Motion data FROZEN for \(frozenMotionCount) polls")
                        isConnected = false
                        connectionStatus = "Disconnected"

                        if sessionState.isActive {
                            Logging.log("🔌 [DISCONNECT] Auto-pausing session indefinitely")
                            pauseSession(duration: nil, reason: .pausedDisconnected)
                            sendAirPodsDisconnectedNotification()
                        }
                    } else {
                        Logging.log("🔌 [STILL FROZEN] Ignoring frozen data - already disconnected (count: \(frozenMotionCount))")
                    }

                    // ALWAYS return when data is frozen - don't process it
                    return
                }
            } else {
                // Motion is changing - reset frozen counter
                if frozenMotionCount > 0 {
                    Logging.log("🔌 [MOTION ACTIVE] ✅ Motion changed - reset frozen count (was \(frozenMotionCount))")
                    Logging.log("🔌 [MOTION ACTIVE] isConnected: \(isConnected), will check for reconnection")
                }
                frozenMotionCount = 0
            }
        }

        // Store current values for next comparison
        lastMotionValues = (newPitch, newRoll, newYaw)

        // Apply low-pass filter for smoother values (for UI display)
        let filteredPitch = pitch * 0.8 + newPitch * 0.2
        let filteredRoll = roll * 0.8 + newRoll * 0.2
        let filteredYaw = yaw * 0.8 + newYaw * 0.2

        // Always update connection status (needed for logic)
        if !isConnected {
            isConnected = true
            connectionStatus = "Connected"
            frozenMotionCount = 0 // Reset on reconnect
            Logging.log("🔌 [CONNECTION] ✅✅✅ AirPods CONNECTED - Motion data flowing")
            // Check if we should auto-resume after reconnection
            checkForReconnection()
        }

        // Detect AirPods removal using RAW pitch (not filtered) for immediate detection
        detectAirPodsRemoval(pitch: newPitch)
        detectAirPodsWorn(pitch: newPitch)

        // Only process tracking data when session is active
        if sessionState.isActive {
            pitchCount += 1

            // Update internal posture quality and send alerts (always needed)
            updatePostureQualityInternal(pitch: filteredPitch)

            // Update session metrics (always needed)
            updateSessionMetrics()

            // Only update UI-heavy @Published properties when app is visible
            if shouldUpdateUI {
                pitch = filteredPitch
                roll = filteredRoll
                yaw = filteredYaw
                updatePitchHistory(filteredPitch)

                // Update UI postureQuality only when visible to avoid triggering animations
                if postureQuality != internalPostureQuality {
                    postureQuality = internalPostureQuality
                }
            } else {
                // Log once every 10 polls when UI updates are disabled
                if pitchCount % 10 == 0 {
                    Logging.log("⏸️  [TRACKING] Still tracking (pitch: \(String(format: "%.1f", filteredPitch))°) but UI updates DISABLED")
                }
            }
        }
    }
    
    private func updatePitchHistory(_ newPitch: Double) {
        pitchHistory.append(newPitch)
        if pitchHistory.count > maxHistoryPoints {
            pitchHistory.removeFirst()
        }
    }
    
    private func updatePostureQualityInternal(pitch: Double) {
        // Only process posture quality when actively tracking
        guard sessionState.isActive && isConnected else {
            return
        }

        // Don't process or send alerts if detecting frozen motion (potential disconnect)
        if frozenMotionCount > 0 {
            if pitchCount % 5 == 0 {
                Logging.log("🔕 [ALERT BLOCKED] Frozen motion detected (\(frozenMotionCount)/\(frozenMotionThreshold)) - suppressing alerts")
            }
            return
        }

        let now = Date()
        let threshold = lowerPostureThreshold
        let warning = warningThreshold

        // Check for chin too low (negative pitch beyond threshold)
        if pitch < threshold {
            internalPostureQuality = .poorChinLow
            if poorPostureStartTime == nil {
                poorPostureStartTime = now
                lastPoorPostureCheck = now
            }

            // Trigger notification for poor posture (chin too low)
            triggerPostureNotification(pitch: pitch)
        }
        // Check for chin too high (positive pitch above upper threshold but below lying down)
        else if pitch > upperPostureThreshold && pitch < lyingDownThreshold {
            internalPostureQuality = .poorChinHigh
            if poorPostureStartTime == nil {
                poorPostureStartTime = now
                lastPoorPostureCheck = now
            }

            // Trigger notification for poor posture (chin too high)
            triggerPostureNotification(pitch: pitch)
        }
        // Lying down - treat as good posture (no alerts)
        else if pitch >= lyingDownThreshold {
            internalPostureQuality = .good
            // If we were in poor posture, calculate the duration
            if poorPostureStartTime != nil, let lastCheck = lastPoorPostureCheck {
                internalPoorPostureDuration += now.timeIntervalSince(lastCheck)
            }
            poorPostureStartTime = nil
            lastPoorPostureCheck = nil
        }
        else if pitch < warning {
            internalPostureQuality = .warning
            // If we were in poor posture, calculate the duration
            if poorPostureStartTime != nil, let lastCheck = lastPoorPostureCheck {
                internalPoorPostureDuration += now.timeIntervalSince(lastCheck)
            }
            poorPostureStartTime = nil
            lastPoorPostureCheck = nil
        } else {
            internalPostureQuality = .good
            // If we were in poor posture, calculate the duration
            if poorPostureStartTime != nil, let lastCheck = lastPoorPostureCheck {
                internalPoorPostureDuration += now.timeIntervalSince(lastCheck)
            }
            poorPostureStartTime = nil
            lastPoorPostureCheck = nil
        }
    }

    private func triggerPostureNotification(pitch: Double) {
        // Don't send posture notifications when session is paused or not connected
        guard sessionState.isActive && isConnected else {
            if pitchCount % 10 == 0 {
                Logging.log("🔕 [ALERT BLOCKED] Not sending posture alert - sessionState: \(sessionState.displayName), isConnected: \(isConnected)")
            }
            return
        }

        NotificationManager.shared.sendPostureNotificationIfNeeded(
            pitch: pitch,
            lowerThreshold: lowerPostureThreshold,
            upperThreshold: upperPostureThreshold
        )
    }
    
    private func updateSessionMetrics() {
        // Don't update metrics when paused
        guard sessionState.isActive else {
            return
        }

        let now = Date()
        let newDuration = now.timeIntervalSince(sessionStartTime)

        // Update poor posture duration if currently in poor posture
        if poorPostureStartTime != nil {
            if let lastCheck = lastPoorPostureCheck {
                internalPoorPostureDuration += now.timeIntervalSince(lastCheck)
                lastPoorPostureCheck = now
            }
        }

        // Batch update session metrics to reduce @Published overhead
        let newPercentage = newDuration > 0 ? Int((internalPoorPostureDuration / newDuration) * 100) : 0
        
        // Update UI only if enabled
        if shouldUpdateUI {
            if abs(sessionDuration - newDuration) >= 1.0 || poorPosturePercentage != newPercentage {
                sessionDuration = newDuration
                poorPostureDuration = internalPoorPostureDuration
                poorPosturePercentage = newPercentage
            }
        }
    }
}
