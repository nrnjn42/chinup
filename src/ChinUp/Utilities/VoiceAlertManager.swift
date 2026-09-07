//
//  VoiceAlertManager.swift
// ChinUp
//
//  Created by NG on 20/01/26.
//

import Foundation
import AVFoundation

/// Manages voice alerts using AVSpeechSynthesizer
/// Speaks "chin up" and "chin down" with optimized settings for quick, clear alerts
@MainActor
final class VoiceAlertManager: NSObject, ObservableObject {
    // MARK: - Properties

    private let synthesizer = AVSpeechSynthesizer()

    // Pre-configured utterances for instant playback
    private let chinUpUtterance: AVSpeechUtterance
    private let chinDownUtterance: AVSpeechUtterance

    @Published var lastSpokenMessage: String = ""

    // MARK: - Initialization

    override init() {
        // Pre-create utterances for minimal latency
        chinUpUtterance = AVSpeechUtterance(string: "chin up")
        chinDownUtterance = AVSpeechUtterance(string: "chin down")

        super.init()

        // Configure utterances
        configureUtterance(chinUpUtterance)
        configureUtterance(chinDownUtterance)

        synthesizer.delegate = self
        setupAudioSession()
    }

    // MARK: - Setup

    private func setupAudioSession() {
        #if !targetEnvironment(macCatalyst)
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default, options: [.mixWithOthers])
            // Do not activate here; we will activate only when needed
        } catch {
            Logging.log("Audio session setup failed: \(error)")
        }
        #endif
    }

    private func configureUtterance(_ utterance: AVSpeechUtterance) {
        // Use default US English voice
        utterance.voice = AVSpeechSynthesisVoice(language: "en-US")

        // Moderate speech rate for clarity (default is 0.5)
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate

        // Full volume
        utterance.volume = 1.0

        // No delay before speaking
        utterance.preUtteranceDelay = 0
        utterance.postUtteranceDelay = 0

        // Normal pitch
        utterance.pitchMultiplier = 1.0
    }

    // MARK: - Public Methods

    /// Speaks "chin up" voice alert
    func speakChinUp() {
        speak(chinUpUtterance, message: "chin up")
    }

    /// Speaks "chin down" voice alert
    func speakChinDown() {
        speak(chinDownUtterance, message: "chin down")
    }

    /// Stops any currently speaking utterance
    func stopSpeaking() {
        if synthesizer.isSpeaking {
            synthesizer.stopSpeaking(at: .immediate)
        }
    }

    // MARK: - Private Methods

    /// Checks if audio is currently routed to AirPods (Bluetooth)
    private func isAirPodsConnected() -> Bool {
        #if targetEnvironment(macCatalyst)
        // On Mac, always allow (no easy way to check audio route)
        return true
        #else
        let outputs = AVAudioSession.sharedInstance().currentRoute.outputs
        for output in outputs {
            let portType = output.portType.rawValue.lowercased()
            // Check for any Bluetooth audio (includes AirPods)
            if portType.contains("bluetooth") || output.portType == .bluetoothA2DP || output.portType == .bluetoothHFP || output.portType == .bluetoothLE {
                Logging.log("🎧 [AUDIO ROUTE] Bluetooth audio detected: \(output.portName) (\(output.portType.rawValue))")
                return true
            }
        }
        Logging.log("🔇 [AUDIO ROUTE] No Bluetooth - current outputs: \(outputs.map { "\($0.portName): \($0.portType.rawValue)" })")
        return false
        #endif
    }

    private func speak(_ utterance: AVSpeechUtterance, message: String) {
        // Only play through AirPods, not system speakers
        guard isAirPodsConnected() else {
            Logging.log("🔇 [ALERT BLOCKED] No AirPods connected - not playing through speakers")
            return
        }

        // Activate audio session
        #if !targetEnvironment(macCatalyst)
        do {
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {
            Logging.log("Failed to activate audio session: \(error)")
        }
        #endif

        // Stop any current speech for immediate response
        if synthesizer.isSpeaking {
            synthesizer.stopSpeaking(at: .immediate)
        }

        // Speak the utterance
        synthesizer.speak(utterance)
        lastSpokenMessage = message

        Logging.log("🔊 Speaking: \(message)")
    }
}

// MARK: - AVSpeechSynthesizerDelegate

extension VoiceAlertManager: AVSpeechSynthesizerDelegate {
    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didStart utterance: AVSpeechUtterance) {
        Logging.log("🎙️ Speech started: \(utterance.speechString)")
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        Logging.log("✅ Speech finished: \(utterance.speechString)")
        // Wait a bit before deactivating to let the synthesizer clean up its audio graph
        Task {
            try? await Task.sleep(nanoseconds: 1_000_000_000) // 1 second
            deactivateAudioSession()
        }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        Logging.log("⏹️ Speech cancelled: \(utterance.speechString)")
        Task {
            try? await Task.sleep(nanoseconds: 1_000_000_000) // 1 second
            deactivateAudioSession()
        }
    }
    
    private nonisolated func deactivateAudioSession() {
        #if !targetEnvironment(macCatalyst)
        do {
            try AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
            Logging.log("🔇 [AUDIO] Session deactivated successfully")
        } catch {
            Logging.log("❌ [AUDIO] Failed to deactivate audio session: \(error)")
        }
        #endif
    }
}
