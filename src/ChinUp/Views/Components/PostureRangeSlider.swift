//
//  PostureRangeSlider.swift
// ChinUp
//
//  Created by NG on 20/01/26.
//

import SwiftUI

/// Dual-thumb slider for the good-posture range. Neither SwiftUI nor UIKit ships one.
///
/// The thumbs are confined to disjoint bounds (chin-down is always negative, chin-up
/// always positive), so they cannot cross and no swap handling is needed.
struct PostureRangeSlider: View {
    @Binding var lowerValue: Double
    @Binding var upperValue: Double

    let lowerBounds: ClosedRange<Double>
    let upperBounds: ClosedRange<Double>
    var step: Double = 1

    private static let space = "PostureRangeSlider"
    private let thumbSize: CGFloat = 26
    private let trackHeight: CGFloat = 6

    private var trackRange: ClosedRange<Double> {
        lowerBounds.lowerBound...upperBounds.upperBound
    }

    var body: some View {
        GeometryReader { geo in
            let usable = max(0, geo.size.width - thumbSize)
            let lowerX = offset(for: lowerValue, usable: usable)
            let upperX = offset(for: upperValue, usable: usable)

            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color(.tertiarySystemBackground))
                    .frame(height: trackHeight)

                // Level-head reference. The good zone straddles 0°, so the marker
                // tells you at a glance how lopsided your range is.
                Rectangle()
                    .fill(Color.secondary.opacity(0.4))
                    .frame(width: 1, height: trackHeight + 6)
                    .offset(x: offset(for: 0, usable: usable) + thumbSize / 2)

                Capsule()
                    .fill(Color.green.opacity(0.55))
                    .frame(width: max(0, upperX - lowerX), height: trackHeight)
                    .offset(x: lowerX + thumbSize / 2)

                thumb(at: lowerX, usable: usable, bounds: lowerBounds, value: $lowerValue)
                    .accessibilityLabel("Chin down limit")
                    .accessibilityValue("\(Int(lowerValue)) degrees")
                    .accessibilityAdjustableAction { direction in
                        adjust($lowerValue, bounds: lowerBounds, direction: direction)
                    }

                thumb(at: upperX, usable: usable, bounds: upperBounds, value: $upperValue)
                    .accessibilityLabel("Chin up limit")
                    .accessibilityValue("\(Int(upperValue)) degrees")
                    .accessibilityAdjustableAction { direction in
                        adjust($upperValue, bounds: upperBounds, direction: direction)
                    }
            }
            .frame(height: geo.size.height)
            .coordinateSpace(name: Self.space)
        }
        .frame(height: thumbSize + 8)
    }

    // MARK: - Thumb

    private func thumb(
        at x: CGFloat,
        usable: CGFloat,
        bounds: ClosedRange<Double>,
        value: Binding<Double>
    ) -> some View {
        Circle()
            .fill(Color.white)
            .overlay(Circle().strokeBorder(Color.green, lineWidth: 2.5))
            .shadow(color: .black.opacity(0.2), radius: 2, y: 1)
            .frame(width: thumbSize, height: thumbSize)
            .offset(x: x)
            .gesture(
                DragGesture(minimumDistance: 0, coordinateSpace: .named(Self.space))
                    .onChanged { drag in
                        let new = self.value(
                            atCenter: drag.location.x,
                            usable: usable,
                            bounds: bounds
                        )
                        if new != value.wrappedValue {
                            value.wrappedValue = new
                        }
                    }
            )
            .accessibilityElement()
    }

    // MARK: - Geometry

    /// Leading-edge offset of the thumb for a given value, in 0...usable.
    private func offset(for value: Double, usable: CGFloat) -> CGFloat {
        let span = trackRange.upperBound - trackRange.lowerBound
        guard span > 0, usable > 0 else { return 0 }
        let fraction = (value - trackRange.lowerBound) / span
        return CGFloat(min(max(fraction, 0), 1)) * usable
    }

    private func value(
        atCenter centerX: CGFloat,
        usable: CGFloat,
        bounds: ClosedRange<Double>
    ) -> Double {
        guard usable > 0 else { return bounds.lowerBound }
        let leading = min(max(centerX - thumbSize / 2, 0), usable)
        let span = trackRange.upperBound - trackRange.lowerBound
        let raw = trackRange.lowerBound + Double(leading / usable) * span
        return clamp((raw / step).rounded() * step, to: bounds)
    }

    private func adjust(
        _ value: Binding<Double>,
        bounds: ClosedRange<Double>,
        direction: AccessibilityAdjustmentDirection
    ) {
        switch direction {
        case .increment:
            value.wrappedValue = clamp(value.wrappedValue + step, to: bounds)
        case .decrement:
            value.wrappedValue = clamp(value.wrappedValue - step, to: bounds)
        @unknown default:
            break
        }
    }

    private func clamp(_ value: Double, to bounds: ClosedRange<Double>) -> Double {
        min(max(value, bounds.lowerBound), bounds.upperBound)
    }
}

#Preview {
    struct Harness: View {
        @State private var lower = -10.0
        @State private var upper = 15.0

        var body: some View {
            VStack(spacing: 12) {
                Text("\(Int(lower))° to +\(Int(upper))°")
                PostureRangeSlider(
                    lowerValue: $lower,
                    upperValue: $upper,
                    lowerBounds: -25...(-5),
                    upperBounds: 5...25
                )
            }
            .padding()
        }
    }
    return Harness()
}
