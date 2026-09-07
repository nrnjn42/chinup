//
//  NotificationManager.swift
// ChinUp
//
//  Created by NG on 20/01/26.
//

import Foundation
import UserNotifications
import AudioToolbox
import AVFoundation

/// Types of posture alerts
enum PostureAlertType {
    case chinTooLow
    case chinTooHigh
    
    var title: String {
        switch self {
        case .chinTooLow:
            return "Posture Check! 🧘"
        case .chinTooHigh:
            return "Posture Check! 🧘"
        }
    }
    
    var message: String {
        switch self {
        case .chinTooLow:
            return "Time to straighten up! Lift your chin and align your spine."
        case .chinTooHigh:
            return "Lower your chin a little."
        }
    }
}

/// Manages local notifications and sound alerts for posture reminders
@MainActor
final class NotificationManager: ObservableObject {
    // MARK: - Singleton
    
    static let shared = NotificationManager()
    
    // MARK: - Published Properties
    
    @Published private(set) var isAuthorized = false
    @Published private(set) var authorizationStatus: UNAuthorizationStatus = .notDetermined

    // MARK: - Private Properties

    private let notificationCenter = UNUserNotificationCenter.current()
    private var lastNotificationTime: Date?
    private let voiceAlertManager = VoiceAlertManager()
    
    // MARK: - UserDefaults Keys
    
    private let notificationsEnabledKey = "notificationsEnabled"
    private let soundEnabledKey = "soundEnabled"
    private let reminderIntervalKey = "reminderInterval"
    
    // MARK: - Initialization
    
    private init() {
        Task {
            await checkAuthorizationStatus()
        }
        setupAudioSession()
    }
    
    private func setupAudioSession() {
        #if !targetEnvironment(macCatalyst)
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default, options: [.mixWithOthers])
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {
            Logging.log("Failed to setup audio session: \(error)")
        }
        #endif
    }
    
    // MARK: - Authorization
    
    /// Requests notification authorization from the user
    func requestAuthorization() async -> Bool {
        do {
            let granted = try await notificationCenter.requestAuthorization(
                options: [.alert, .sound, .badge]
            )
            await MainActor.run {
                self.isAuthorized = granted
            }
            await checkAuthorizationStatus()
            return granted
        } catch {
            Logging.log("Failed to request notification authorization: \(error)")
            return false
        }
    }
    
    /// Checks the current authorization status
    func checkAuthorizationStatus() async {
        let settings = await notificationCenter.notificationSettings()
        await MainActor.run {
            self.authorizationStatus = settings.authorizationStatus
            self.isAuthorized = settings.authorizationStatus == .authorized
        }
    }
    
    // MARK: - Notification Sending
    
    // High angle threshold - no alerts when AirPods likely on desk
    private let highAngleThreshold: Double = 40.0

    /// Sends a posture correction notification if conditions are met
    /// - Parameters:
    ///   - pitch: The current pitch angle
    ///   - lowerThreshold: The poor posture threshold from settings (for chin too low)
    ///   - upperThreshold: The upper posture threshold from settings (for chin too high)
    func sendPostureNotificationIfNeeded(pitch: Double, lowerThreshold: Double, upperThreshold: Double) {
        // Check if either notifications or sounds are enabled
        let notificationsEnabled = UserDefaults.standard.bool(forKey: notificationsEnabledKey)
        let soundEnabled = UserDefaults.standard.bool(forKey: soundEnabledKey)

        // If both are disabled, do nothing
        guard notificationsEnabled || soundEnabled else { return }

        // Don't send alerts if absolute angle > 40° - likely on desk or lying down
        if abs(pitch) >= highAngleThreshold {
            Logging.log("🔕 [ALERT BLOCKED] Pitch \(String(format: "%.1f", pitch))° outside ±\(highAngleThreshold)° - suppressing alert")
            return
        }

        // Determine alert type based on pitch
        let alertType: PostureAlertType?
        if pitch < lowerThreshold {
            alertType = .chinTooLow
        } else if pitch > upperThreshold {
            alertType = .chinTooHigh
        } else {
            alertType = nil
        }
        
        // Only proceed if there's a posture issue
        guard let alert = alertType else { return }
        
        // Get reminder interval from settings (in seconds)
        let reminderInterval = UserDefaults.standard.double(forKey: reminderIntervalKey)
        let intervalSeconds = max(reminderInterval, 5.0) // Minimum 5 seconds
        
        // Check if enough time has passed since last notification
        if let lastTime = lastNotificationTime {
            let timeSinceLast = Date().timeIntervalSince(lastTime)
            guard timeSinceLast >= intervalSeconds else { return }
        }
        
        // Send the notification if enabled
        if notificationsEnabled {
            sendPostureNotification(alertType: alert)
        }
        
        // Play sound if enabled
        if soundEnabled {
            playAlertSound(for: alert)
        }
        
        lastNotificationTime = Date()
    }
    
    /// Sends an immediate posture correction notification
    /// - Parameter alertType: The type of posture alert to send
    private func sendPostureNotification(alertType: PostureAlertType) {
        // Only send notification if authorized
        guard isAuthorized else { return }
        
        let content = UNMutableNotificationContent()
        content.title = alertType.title
        content.body = alertType.message
        content.sound = .default
        content.categoryIdentifier = "POSTURE_REMINDER"
        
        // Create a trigger that fires immediately
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
        
        // Create request with unique identifier
        let request = UNNotificationRequest(
            identifier: "posture-reminder-\(UUID().uuidString)",
            content: content,
            trigger: trigger
        )
        
        // Schedule the notification
        notificationCenter.add(request) { error in
            if let error = error {
                Logging.log("Failed to schedule notification: \(error)")
            }
        }
    }
    
    /// Plays an alert sound directly from the app
    private func playAlertSound(for alertType: PostureAlertType) {
        playSound(for: alertType)
    }
    
    /// Plays voice alert using AVSpeechSynthesizer
    private func playSound(for alertType: PostureAlertType) {
        switch alertType {
        case .chinTooLow:
            voiceAlertManager.speakChinUp()
        case .chinTooHigh:
            voiceAlertManager.speakChinDown()
        }
    }
    
    /// Resets the last notification time (useful when starting a new session)
    func resetLastNotificationTime() {
        lastNotificationTime = nil
    }

    // MARK: - Pause Notifications

    /// Sends notification when pause timer expires
    func sendPauseExpiredNotification() {
        guard isAuthorized else { return }

        let content = UNMutableNotificationContent()
        content.title = "Session Paused"
        content.body = "Your pause timer has expired. Would you like to continue?"
        content.sound = .default
        content.categoryIdentifier = "PAUSE_EXPIRED"

        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
        let request = UNNotificationRequest(
            identifier: "pause-expired-\(UUID().uuidString)",
            content: content,
            trigger: trigger
        )

        notificationCenter.add(request) { error in
            if let error = error {
                Logging.log("Failed to send pause expired notification: \(error)")
            }
        }
    }

    /// Sends notification when AirPods are removed
    func sendAirPodsRemovedNotification() {
        guard isAuthorized else { return }

        let content = UNMutableNotificationContent()
        content.title = "Session Paused"
        content.body = "AirPods removed - your session has been paused."
        content.sound = .default
        content.categoryIdentifier = "AIRPODS_REMOVED"

        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
        let request = UNNotificationRequest(
            identifier: "airpods-removed-\(UUID().uuidString)",
            content: content,
            trigger: trigger
        )

        notificationCenter.add(request) { error in
            if let error = error {
                Logging.log("Failed to send AirPods removed notification: \(error)")
            }
        }
    }

    /// Sends notification when AirPods are disconnected
    func sendAirPodsDisconnectedNotification() {
        guard isAuthorized else { return }

        let content = UNMutableNotificationContent()
        content.title = "Session Paused"
        content.body = "AirPods disconnected - your session has been paused."
        content.sound = .default
        content.categoryIdentifier = "AIRPODS_DISCONNECTED"

        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
        let request = UNNotificationRequest(
            identifier: "airpods-disconnected-\(UUID().uuidString)",
            content: content,
            trigger: trigger
        )

        notificationCenter.add(request) { error in
            if let error = error {
                Logging.log("Failed to send AirPods disconnected notification: \(error)")
            }
        }
    }

    /// Sends notification when AirPods are reconnected
    func sendAirPodsReconnectedNotification() {
        guard isAuthorized else { return }

        let content = UNMutableNotificationContent()
        content.title = "Session Resumed"
        content.body = "AirPods reconnected - your session has been automatically resumed."
        content.sound = .default
        content.categoryIdentifier = "AIRPODS_RECONNECTED"

        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
        let request = UNNotificationRequest(
            identifier: "airpods-reconnected-\(UUID().uuidString)",
            content: content,
            trigger: trigger
        )

        notificationCenter.add(request) { error in
            if let error = error {
                Logging.log("Failed to send AirPods reconnected notification: \(error)")
            }
        }
    }
}

