//
//  SessionState.swift
// ChinUp
//
//  Created on 20/01/25.
//

import Foundation

enum SessionState: Int {
    case active = 10

    case pausedManual = 20
    case pausedRemoved = 21
    case pausedDisconnected = 22

    var isPaused: Bool {
        return rawValue >= 20
    }

    var isActive: Bool {
        return rawValue == 10
    }

    var displayName: String {
        switch self {
        case .active:
            return "Active"
        case .pausedManual:
            return "Paused"
        case .pausedRemoved:
            return "Paused - AirPods removed"
        case .pausedDisconnected:
            return "AirPods disconnected. Will resume once back online"
        }
    }
}
