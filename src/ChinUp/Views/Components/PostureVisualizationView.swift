import SwiftUI

struct WavyCircle: Shape {
    var frequency: Double = 8
    var amplitude: Double = 5
    
    func path(in rect: CGRect) -> Path {
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let radius = min(rect.width, rect.height) / 2
        
        var path = Path()
        let points = 360
        
        for i in 0...points {
            let angle = Double(i) * .pi / 180
            let wave = sin(angle * frequency) * amplitude
            let r = radius + wave
            let x = center.x + r * cos(angle)
            let y = center.y + r * sin(angle)
            
            if i == 0 {
                path.move(to: CGPoint(x: x, y: y))
            } else {
                path.addLine(to: CGPoint(x: x, y: y))
            }
        }
        
        path.closeSubpath()
        return path
    }
}

struct PostureVisualizationView: View {
    let pitch: Double
    let postureQuality: HeadphoneMotionViewModel.PostureQuality

    var body: some View {
        ZStack {
            // Background wavy circle (Static)
            WavyCircle(frequency: 8, amplitude: 5)
                .stroke(
                    LinearGradient(
                        colors: [postureQuality.color.opacity(0.3), postureQuality.color.opacity(0.1)],
                        startPoint: .top,
                        endPoint: .bottom
                    ),
                    lineWidth: 3
                )
                .background(
                    WavyCircle(frequency: 8, amplitude: 5)
                        .fill(Color(.systemBackground))
                )
            
            // Posture indicator
            VStack(spacing: 20) {
                // Icon
                Image(systemName: postureQuality.icon)
                    .font(.system(size: 60))
                    .foregroundColor(postureQuality.color)
                    .scaleEffect(postureQuality.isPoor ? 1.1 : 1.0)
                
                // Pitch value
                VStack(spacing: 4) {
                    Text(String(format: "%.1f°", pitch))
                        .font(.system(size: 36, weight: .bold, design: .rounded))
                        .foregroundColor(.primary)
                    
                    Text(postureQuality.message)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
            }
        }
        .frame(width: 220, height: 220)
    }
}

#Preview {
    VStack(spacing: 40) {
        PostureVisualizationView(
            pitch: 0,
            postureQuality: .good
        )
        
        PostureVisualizationView(
            pitch: 15,
            postureQuality: .warning
        )
        
        PostureVisualizationView(
            pitch: -25,
            postureQuality: .poorChinLow
        )
        
        PostureVisualizationView(
            pitch: 25,
            postureQuality: .poorChinHigh
        )
    }
    .padding()
}
