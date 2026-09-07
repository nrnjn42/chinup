//
//  WindowVisibilityMonitor.swift
// ChinUp
//
//  Created by NG on 20/01/26.
//

import SwiftUI

/// Decides when the UI is actually on screen so motion updates can be throttled.
///
/// Scene-activation notifications do not fire when the user switches windows in
/// "Designed for iPad" mode, so visibility is polled instead of observed.
final class WindowVisibilityMonitor: ObservableObject {
    @Published private(set) var isVisible = true

    /// Fired with `isVisible && scenePhase == .active` whenever either input changes.
    var onShouldUpdateUIChange: ((Bool) -> Void)?

    private var timer: Timer?
    private var scenePhase: ScenePhase = .active

    func start() {
        stop()
        Logging.log("🔄 [POLLING] Starting window visibility polling (every 1 second)")

        checkVisibility()

        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.checkVisibility()
        }
    }

    func stop() {
        Logging.log("⏹️  [POLLING] Stopping window visibility polling")
        timer?.invalidate()
        timer = nil
    }

    func handleScenePhaseChange(from oldPhase: ScenePhase, to newPhase: ScenePhase) {
        Logging.log("🔄 [SCENE] Phase changed: \(oldPhase) → \(newPhase)")
        scenePhase = newPhase

        switch newPhase {
        case .active:
            Logging.log("   → App became ACTIVE, window visible: \(isVisible)")
            start()
            if isVisible {
                onShouldUpdateUIChange?(true)
            }
        case .inactive:
            Logging.log("   → App became INACTIVE")
            stop()
            onShouldUpdateUIChange?(false)
        case .background:
            Logging.log("   → App went to BACKGROUND")
            stop()
            onShouldUpdateUIChange?(false)
        @unknown default:
            break
        }
    }

    private func checkVisibility() {
        let hasActiveWindow = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .contains { $0.activationState == .foregroundActive }

        let shouldBeVisible = hasActiveWindow && UIApplication.shared.applicationState == .active

        guard shouldBeVisible != isVisible else { return }

        Logging.log("👁️  [POLL CHECK] Visibility changed: \(isVisible) → \(shouldBeVisible)")
        Logging.log("   Active window scenes: \(hasActiveWindow), App state: \(UIApplication.shared.applicationState == .active)")
        isVisible = shouldBeVisible

        let shouldEnableUI = shouldBeVisible && scenePhase == .active
        Logging.log("👁️  [VISIBILITY] Window visibility changed to: \(shouldBeVisible ? "VISIBLE" : "HIDDEN")")
        Logging.log("   Current scene phase: \(scenePhase), setting UI updates to: \(shouldEnableUI ? "ENABLED" : "DISABLED")")
        onShouldUpdateUIChange?(shouldEnableUI)
    }
}
