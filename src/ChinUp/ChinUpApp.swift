//
// ChinUpApp.swift
// ChinUp
//
//  Created by NG on 20/01/26.
//

import SwiftUI

@main
struct ChinUpApp: App {
    // MARK: - Initialization

    init() {
        // Set default values for settings if not already set
        registerDefaultSettings()
    }
    
    // MARK: - Body
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .task {
                    // Request notification authorization on app launch. The granted
                    // flag is published on the manager; nothing here needs it.
                    _ = await NotificationManager.shared.requestAuthorization()
                }
        }
    }
    
    // MARK: - Private Methods
    
    private func registerDefaultSettings() {
        let defaults: [String: Any] = [
            "notificationsEnabled": true,
            "soundEnabled": true,
            "lowerPostureThreshold": -10.0,  // Lower limit (chin down)
            "upperPostureThreshold": 15.0,    // Upper limit (chin up)
            "reminderInterval": 30.0,
            "hapticFeedback": true
        ]
        UserDefaults.standard.register(defaults: defaults)

        // Migrate from old single threshold to dual thresholds
        migratePostureThresholds()
    }

    private func migratePostureThresholds() {
        let userDefaults = UserDefaults.standard

        // Check if migration is needed (new thresholds don't exist yet)
        if userDefaults.object(forKey: "lowerPostureThreshold") == nil {
            // Check if old threshold exists
            if let oldValue = userDefaults.object(forKey: "poorPostureThreshold") as? Double {
                // Migrate: old positive value becomes negative lower threshold
                userDefaults.set(-oldValue, forKey: "lowerPostureThreshold")
                // Set default upper threshold
                userDefaults.set(15.0, forKey: "upperPostureThreshold")
                // Clean up old key
                userDefaults.removeObject(forKey: "poorPostureThreshold")
            }
        }
    }
}
