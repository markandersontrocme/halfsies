import HalfsiesCore
import SwiftUI

/// The Halfsies mark: a circle split into a left and a right half.
/// Each half fills from the bottom up with that half's battery.
/// A low half turns red, an asleep half is dotted, and a half that is not reported shows only a faint track.
public struct SplitRing: View {
    let battery: SplitBattery
    let lineWidth: CGFloat
    let color: Color

    public init(_ battery: SplitBattery, lineWidth: CGFloat, color: Color = .primary) {
        self.battery = battery
        self.lineWidth = lineWidth
        self.color = color
    }

    public var body: some View {
        ZStack {
            HalfRing(side: .left, level: battery.left, lineWidth: lineWidth, color: color)
            HalfRing(side: .right, level: battery.right, lineWidth: lineWidth, color: color)
        }
        // Keeps the stroke inside the frame.
        .padding(lineWidth / 2)
        .animation(.smooth, value: battery)
    }
}

private struct HalfRing: View {
    let side: HalfArc.Side
    let level: BatteryLevel?
    let lineWidth: CGFloat
    let color: Color

    var body: some View {
        let solid = StrokeStyle(lineWidth: lineWidth, lineCap: .round)
        ZStack {
            switch level {
            case .percent(let value):
                HalfArc(side: side, lineWidth: lineWidth, fill: 1)
                    .stroke(color.opacity(0.3), style: solid)
                HalfArc(side: side, lineWidth: lineWidth, fill: Double(value) / 100)
                    .stroke(level?.isLow == true ? Color.red : color, style: solid)
            case .disconnected:
                HalfArc(side: side, lineWidth: lineWidth, fill: 1)
                    .stroke(color.opacity(0.4), style: StrokeStyle(lineWidth: lineWidth, lineCap: .round, dash: [0, lineWidth * 1.6]))
            case nil:
                HalfArc(side: side, lineWidth: lineWidth, fill: 1)
                    .stroke(color.opacity(0.15), style: solid)
            }
        }
    }
}

/// One half of the ring, drawn from the bottom gap up towards the top gap.
private struct HalfArc: Shape {
    enum Side { case left, right }

    var side: Side
    var lineWidth: CGFloat
    /// How much of the half to draw, from 0 to 1.
    var fill: Double

    var animatableData: Double {
        get { fill }
        set { fill = newValue }
    }

    func path(in rect: CGRect) -> Path {
        let radius = min(rect.width, rect.height) / 2
        let center = CGPoint(x: rect.midX, y: rect.midY)
        // Leave about one line width of space between the rounded ends at the top and bottom, at any size.
        let gap = Angle.radians(asin(min(lineWidth / radius, 1)))
        let sweep = (Angle.degrees(180) - gap * 2) * min(max(fill, 0), 1)
        let bottom = Angle.degrees(90)

        var path = Path()
        // SwiftUI's y axis points down, so `clockwise: false` moves clockwise on screen.
        switch side {
        case .left:
            path.addArc(center: center, radius: radius, startAngle: bottom + gap, endAngle: bottom + gap + sweep, clockwise: false)
        case .right:
            path.addArc(center: center, radius: radius, startAngle: bottom - gap, endAngle: bottom - gap - sweep, clockwise: true)
        }
        return path
    }
}
