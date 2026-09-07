//
//  SettingsView.swift
// ChinUp
//
//  Created by NG on 20/01/26.
//

import SwiftUI

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss

    // User preferences persisted with @AppStorage
    @AppStorage("notificationsEnabled") private var notificationsEnabled = true
    @AppStorage("soundEnabled") private var soundEnabled = true
    @AppStorage("lowerPostureThreshold") private var lowerPostureThreshold = -10.0 // Lower limit (chin down)
    @AppStorage("upperPostureThreshold") private var upperPostureThreshold = 15.0 // Upper limit (chin up)
    @AppStorage("reminderInterval") private var reminderInterval = 30.0 // in seconds
    @AppStorage("hapticFeedback") private var hapticFeedback = true

    var body: some View {
        NavigationStack {
            List {
                preferencesSection
                privacySection
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                    .fontWeight(.medium)
                }
            }
        }
    }

    // MARK: - Preferences Section
    
    private var preferencesSection: some View {
        Section {
            // Notifications Toggle
            HStack {
                Label("Enable Notifications", systemImage: "bell")
                Spacer()
                Toggle("", isOn: $notificationsEnabled)
            }
            
            // Sounds Toggle
            HStack {
                Label("Enable Sounds", systemImage: "speaker.wave.2")
                Spacer()
                Toggle("", isOn: $soundEnabled)
            }
            
            // Good Posture Zone
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Label("Good Posture Zone", systemImage: "checkmark.circle.fill")
                    Spacer()
                    Text("\(Int(lowerPostureThreshold))° to +\(Int(upperPostureThreshold))°")
                        .foregroundColor(.secondary)
                        .fontWeight(.medium)
                        .monospacedDigit()
                }

                PostureRangeSlider(
                    lowerValue: $lowerPostureThreshold,
                    upperValue: $upperPostureThreshold,
                    lowerBounds: -25...(-5),
                    upperBounds: 5...25
                )

                HStack {
                    Text("-25° chin down")
                    Spacer()
                    Text("chin up +25°")
                }
                .font(.caption)
                .foregroundColor(.secondary)

                Text("The green region is the good zone. Beyond that, you get alerts.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding(.vertical, 4)


            // Reminder Interval
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Label("Reminder Interval", systemImage: "timer")
                    Spacer()
                    Text("\(Int(reminderInterval))s")
                        .foregroundColor(.secondary)
                        .fontWeight(.medium)
                }
                
                Slider(
                    value: $reminderInterval,
                    in: 5...120,
                    step: 5
                ) {
                    Text("Interval")
                } minimumValueLabel: {
                    Text("5s")
                        .font(.caption)
                        .foregroundColor(.secondary)
                } maximumValueLabel: {
                    Text("120s")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .tint(.blue)
            }
            
            // Haptic Feedback
            HStack {
                Label("Haptic Feedback", systemImage: "iphone.radiowaves.left.and.right")
                Spacer()
                Toggle("", isOn: $hapticFeedback)
            }
        } header: {
            Label("Preferences", systemImage: "slider.horizontal.3")
        }
    }

    // MARK: - Privacy Section

    private var privacySection: some View {
        Section {
            VStack(alignment: .leading, spacing: 6) {
                Text("No tracking. No collection. No account.")
                    .font(.subheadline)
                    .fontWeight(.medium)

                Text("Head motion is read from your AirPods and processed entirely on this Mac. Nothing is uploaded — ChinUp has no network code at all. Sessions aren't even saved: your posture readings live in memory while a session runs and are gone when it stops. The only things written to disk are the settings on this page and a local diagnostic log.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding(.vertical, 4)
        } header: {
            Label("Privacy", systemImage: "hand.raised")
        }
    }
}

#Preview {
    SettingsView()
}