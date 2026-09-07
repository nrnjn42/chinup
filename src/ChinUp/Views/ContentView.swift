//
//  ContentView.swift
// ChinUp
//
//  Created by NG on 20/01/26.
//

import SwiftUI

struct ContentView: View {
    // MARK: - Properties

    @StateObject private var motionVM: HeadphoneMotionViewModel
    @StateObject private var connection: ConnectionCoordinator
    @StateObject private var visibility = WindowVisibilityMonitor()
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @State private var showingSettings = false

    init() {
        let motion = HeadphoneMotionViewModel()
        _motionVM = StateObject(wrappedValue: motion)
        _connection = StateObject(wrappedValue: ConnectionCoordinator(motion: motion))
    }

    // MARK: - Body

    var body: some View {
        NavigationStack {
            ZStack {
                backgroundGradient

                ScrollView {
                    VStack(spacing: 0) {
                        headerSection

                        if connection.state.isConnected {
                            connectedContent
                                .transition(.asymmetric(
                                    insertion: .opacity.combined(with: .scale(scale: 0.95)),
                                    removal: .opacity
                                ))
                        } else {
                            disconnectedContent
                                .transition(.asymmetric(
                                    insertion: .opacity.combined(with: .scale(scale: 0.95)),
                                    removal: .opacity
                                ))
                        }

                        Spacer(minLength: bottomSpacerHeight)
                    }
                    .padding(.horizontal)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    if connection.state.isConnected {
                        sessionStatusChip
                    }
                }

                settingsToolbarItem
            }
            .sheet(isPresented: $showingSettings) {
                settingsSheet
            }
        }
        .onAppear {
            connection.syncWithMotionState()
            visibility.onShouldUpdateUIChange = { [motionVM] enabled in
                motionVM.setUIUpdateEnabled(enabled)
            }
            visibility.start()
        }
        .onDisappear {
            visibility.stop()
        }
        .onChange(of: motionVM.isConnected) { _, _ in
            connection.syncWithMotionState()
        }
        .onChange(of: motionVM.connectionStatus) { _, _ in
            connection.syncWithMotionState()
        }
        .onChange(of: scenePhase) { oldPhase, newPhase in
            visibility.handleScenePhaseChange(from: oldPhase, to: newPhase)
        }
    }

    // MARK: - Background

    private var backgroundGradient: some View {
        LinearGradient(
            colors: connection.state.isConnected ?
                [Color(.systemBackground), motionVM.postureQuality.color.opacity(0.1)] :
                [Color(.systemBackground), Color(.secondarySystemBackground)],
            startPoint: .top,
            endPoint: .bottom
        )
        .ignoresSafeArea()
    }

    // MARK: - Header Section

    private var headerSection: some View {
        VStack(spacing: 16) {
            HStack {
                Spacer()
            }
        }
        .padding(.top, headerTopPadding)
        .padding(.bottom, headerBottomPadding)
    }

    // MARK: - Session Status Chip

    private var sessionStatusChip: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(motionVM.postureQuality.color)
                .frame(width: 8, height: 8)
                .scaleEffect(motionVM.postureQuality.isPoor ? 1.2 : 1.0)

            Text("Live")
                .font(.caption.weight(.medium))
                .foregroundColor(.primary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(Color(.tertiarySystemBackground))
        .cornerRadius(20)
    }

    // MARK: - Settings Sheet

    private var settingsSheet: some View {
        #if targetEnvironment(macCatalyst)
        // Catalyst's default form sheet is 540×620, which cuts off the Privacy
        // notice and forces a scroll for two short sections.
        SettingsView().frame(minWidth: 540, minHeight: 744)
        #else
        SettingsView()
        #endif
    }

    // MARK: - Settings Button

    /// On macOS 26 (Liquid Glass) the toolbar paints its own capsule behind every
    /// item, which reads as a dark disc over the gradient. `.buttonStyle(.plain)`
    /// does not suppress it — the background belongs to the toolbar, not the button.
    @ToolbarContentBuilder
    private var settingsToolbarItem: some ToolbarContent {
        if #available(iOS 26.0, macOS 26.0, *) {
            ToolbarItem(placement: .navigationBarTrailing) {
                settingsButton
            }
            .sharedBackgroundVisibility(.hidden)
        } else {
            ToolbarItem(placement: .navigationBarTrailing) {
                settingsButton
            }
        }
    }

    private var settingsButton: some View {
        Button {
            showingSettings = true
        } label: {
            Image(systemName: "gearshape.fill")
                .font(.title3)
                .foregroundColor(.primary)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Settings")
    }

    // MARK: - Connected Content

    private var connectedContent: some View {
        VStack(spacing: contentSpacing) {
            PostureVisualizationView(
                pitch: motionVM.pitch,
                postureQuality: motionVM.postureQuality
            )
            .frame(height: visualizationHeight)

            combinedMetricsCard

            if motionVM.sessionState.isPaused {
                pausedControls
            } else {
                pauseMenu
            }
        }
        .frame(maxWidth: contentMaxWidth)
    }

    private var pausedControls: some View {
        VStack(spacing: 16) {
            VStack(spacing: 8) {
                HStack(spacing: 8) {
                    Image(systemName: "pause.circle.fill")
                        .font(.title3)
                        .foregroundColor(.orange)
                    Text(motionVM.sessionState.displayName)
                        .font(.headline)
                        .foregroundColor(.primary)
                }

                if motionVM.pauseRemainingSeconds > 0 {
                    Text(pauseRemainingText)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
            }
            .padding()
            .frame(maxWidth: .infinity)
            .background(Color.orange.opacity(0.1))
            .cornerRadius(12)

            Button {
                connection.resumeSession()
            } label: {
                HStack(spacing: 14) {
                    Image(systemName: "play.circle.fill")
                        .font(.title2)
                    Text("Resume Session")
                        .font(.title3.bold())
                }
                .foregroundColor(.white)
                .frame(maxWidth: buttonMaxWidth ?? .infinity)
                .padding(.vertical, 18)
                .background(
                    LinearGradient(
                        colors: [.green, .green.opacity(0.8)],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .cornerRadius(16)
            }

            // While paused the Pause menu is swapped out for Resume, so this is the
            // only remaining way to end a session without quitting the app.
            Button(role: .destructive) {
                connection.stopSession()
            } label: {
                Text("End Session")
                    .font(.subheadline.weight(.medium))
                    .foregroundColor(.red)
            }
            .buttonStyle(.plain)
        }
    }

    private var pauseMenu: some View {
        Menu {
            Button {
                connection.pauseSession(duration: 5 * 60)
            } label: {
                Label("Pause for 5 minutes", systemImage: "5.circle")
            }

            Button {
                connection.pauseSession(duration: 10 * 60)
            } label: {
                Label("Pause for 10 minutes", systemImage: "10.circle")
            }

            Button {
                connection.pauseSession(duration: 15 * 60)
            } label: {
                Label("Pause for 15 minutes", systemImage: "15.circle")
            }

            Button {
                connection.pauseSession(duration: 20 * 60)
            } label: {
                Label("Pause for 20 minutes", systemImage: "20.circle")
            }

            Button {
                connection.pauseSession(duration: nil)
            } label: {
                Label("Pause indefinitely", systemImage: "infinity")
            }

            Divider()

            Button(role: .destructive) {
                connection.stopSession()
            } label: {
                Label("End Session", systemImage: "stop.circle")
            }
        } label: {
            HStack(spacing: 14) {
                Image(systemName: "pause.circle.fill")
                    .font(.title2)
                Text("Pause Session")
                    .font(.title3.bold())
                Image(systemName: "chevron.down")
                    .font(.caption.bold())
            }
            .foregroundColor(.white)
            .frame(maxWidth: buttonMaxWidth ?? .infinity)
            .padding(.vertical, 18)
            .background(
                LinearGradient(
                    colors: [.orange, .orange.opacity(0.8)],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
            .cornerRadius(16)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Combined Metrics Card

    private var combinedMetricsCard: some View {
        VStack(spacing: 24) {
            VStack(spacing: 12) {
                Image(systemName: motionVM.postureQuality.icon)
                    .font(.system(size: 32))
                    .foregroundColor(motionVM.postureQuality.color)

                Text(motionVM.postureQuality.message)
                    .font(.title2.bold())
                    .foregroundColor(.primary)

                Text("Posture Quality")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity)

            VStack(spacing: 6) {
                Text(sessionDurationText)
                    .font(.system(size: 24, weight: .semibold, design: .rounded))
                    .foregroundColor(.primary)

                Text("Session Time")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }

            PostureMetricsView(poorPosturePercentage: motionVM.poorPosturePercentage)

            Divider()
                .padding(.horizontal, -20)

            VStack(alignment: .leading, spacing: 16) {
                Text("Posture Timeline")
                    .font(.title3.bold())

                PostureGraphView(
                    dataPoints: motionVM.pitchHistory,
                    currentPitch: motionVM.pitch
                )
                .frame(height: 120)
            }
        }
        .padding(20)
        .background(Color(.secondarySystemBackground))
        .cornerRadius(20)
    }

    // MARK: - Disconnected Content

    private var disconnectedContent: some View {
        VStack(spacing: 40) {
            Spacer()

            connectionIllustration

            VStack(spacing: 20) {
                Text(connection.state.title)
                    .font(.title2.bold())
                    .foregroundColor(.primary)
                    .multilineTextAlignment(.center)

                Text(connection.state.detail)
                    .font(.body)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 320)

                connectionButton
                connectionStatusInfo
            }

            Spacer()
        }
    }

    private var connectionIllustration: some View {
        ZStack {
            Circle()
                .stroke(Color.blue.opacity(0.2), lineWidth: 3)
                .frame(width: 160, height: 160)
                .scaleEffect(connection.isRetrying ? 1.1 : 1.0)
                .animation(.easeInOut(duration: 1.0).repeatForever(autoreverses: true), value: connection.isRetrying)

            Circle()
                .stroke(Color.blue.opacity(0.4), lineWidth: 2)
                .frame(width: 120, height: 120)
                .scaleEffect(connection.isRetrying ? 0.9 : 1.0)
                .animation(.easeInOut(duration: 1.0).repeatForever(autoreverses: true), value: connection.isRetrying)

            Image(systemName: "airpodspro")
                .font(.system(size: 50))
                .foregroundColor(.blue)
                .symbolEffect(.pulse, isActive: connection.state == .connecting)
        }
    }

    private var connectionButton: some View {
        Group {
            switch connection.state {
            case .disconnected, .error:
                Button {
                    connection.startSession()
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "play.circle.fill")
                            .font(.title3)
                        Text("Start Tracking")
                            .font(.headline)
                    }
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(
                        LinearGradient(
                            colors: [.blue, .blue.opacity(0.8)],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .cornerRadius(16)
                }
                .disabled(connection.isRetrying)

            case .connecting:
                Button {
                    connection.cancelConnection()
                } label: {
                    HStack(spacing: 12) {
                        ProgressView()
                            .scaleEffect(0.8)
                            .tint(.secondary)
                        Text("Connecting...")
                            .font(.headline)
                    }
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(Color(.tertiarySystemBackground))
                    .cornerRadius(16)
                }

            case .connected:
                EmptyView()
            }
        }
        .frame(maxWidth: 280)
    }

    private var connectionStatusInfo: some View {
        Group {
            if case .error(let message) = connection.state {
                VStack(spacing: 12) {
                    HStack(spacing: 8) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(.orange)
                        Text(message)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(Color.orange.opacity(0.1))
                    .cornerRadius(20)

                    if connection.attempts > 0 {
                        Button("Retry Connection") {
                            connection.startSession()
                        }
                        .font(.caption)
                        .foregroundColor(.blue)
                    }
                }
            } else if case .connecting = connection.state {
                HStack(spacing: 8) {
                    Image(systemName: "info.circle")
                    Text("Put on your AirPods Pro and wait for connection")
                        .font(.caption)
                }
                .foregroundColor(.secondary)
            }
        }
    }

    // MARK: - Computed Properties

    private var sessionDurationText: String {
        let minutes = Int(motionVM.sessionDuration / 60)
        let seconds = Int(motionVM.sessionDuration.truncatingRemainder(dividingBy: 60))
        return String(format: "%02d:%02d", minutes, seconds)
    }

    private var pauseRemainingText: String {
        let minutes = Int(motionVM.pauseRemainingSeconds / 60)
        let seconds = Int(motionVM.pauseRemainingSeconds.truncatingRemainder(dividingBy: 60))
        return String(format: "%d:%02d remaining", minutes, seconds)
    }

    // MARK: - Adaptive Layout Properties

    private var isCompactWidth: Bool {
        horizontalSizeClass == .compact
    }

    private var contentMaxWidth: CGFloat? {
        isCompactWidth ? nil : 800
    }

    private var contentSpacing: CGFloat {
        isCompactWidth ? 32 : 20
    }

    private var visualizationHeight: CGFloat {
        isCompactWidth ? 280 : 200
    }

    private var headerTopPadding: CGFloat {
        isCompactWidth ? 20 : 12
    }

    private var headerBottomPadding: CGFloat {
        isCompactWidth ? 30 : 20
    }

    private var buttonMaxWidth: CGFloat? {
        isCompactWidth ? nil : 400
    }

    private var bottomSpacerHeight: CGFloat {
        isCompactWidth ? 100 : 20
    }
}

// MARK: - Previews

#Preview("Connected State") {
    ContentView()
}

#Preview("Disconnected State") {
    ContentView()
}
