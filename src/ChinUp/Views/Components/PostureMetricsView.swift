//
//  PostureMetricsView.swift
// ChinUp
//
//  Created by NG on 20/01/26.
//

import SwiftUI

struct PostureMetricsView: View {
    let poorPosturePercentage: Int

    // MARK: - Body

    var body: some View {
        VStack(spacing: 20) {
            // Progress ring
            progressRing
        }
    }
    
    // MARK: - Progress Ring
    
    private var progressRing: some View {
        ZStack {
            // Background circle
            Circle()
                .stroke(Color(.tertiarySystemBackground), lineWidth: 14)
                .frame(width: 140, height: 140)

            // Progress circle
            Circle()
                .trim(from: 0, to: CGFloat(poorPosturePercentage) / 100)
                .stroke(
                    LinearGradient(
                        colors: gradientColors,
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    style: StrokeStyle(lineWidth: 14, lineCap: .round)
                )
                .frame(width: 140, height: 140)
                .rotationEffect(.degrees(-90))
            
            // Center content
            VStack(spacing: 6) {
                Text("\(poorPosturePercentage)%")
                    .font(.system(size: 32, weight: .bold, design: .rounded))
                    .foregroundColor(.primary)

                Text("Poor Posture")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
        }
    }
    
    private var gradientColors: [Color] {
        switch poorPosturePercentage {
        case 0...15:
            return [.green, .green.opacity(0.7)]
        case 16...30:
            return [.orange, .yellow]
        default:
            return [.red, .red.opacity(0.7)]
        }
    }
}

#Preview {
    PostureMetricsView(poorPosturePercentage: 15)
        .padding()
}