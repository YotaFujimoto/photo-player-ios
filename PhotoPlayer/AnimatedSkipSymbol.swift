import SwiftUI

/// The ring/head alone rotate; the numeral is a separate, stationary sibling.
/// Time is measured from the current feedback, so replacement never queues turns.
struct AnimatedSkipSymbol: View {
    let feedback: SkipFeedback
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    static let turnDuration = 0.42

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 60, paused: reduceMotion)) { timeline in
            let elapsed = max(0, timeline.date.timeIntervalSince(feedback.presentedAt))
            SkipSymbolGlyph(forward: feedback.forward,
                            turns: reduceMotion ? 0 : min(1, elapsed / Self.turnDuration))
        }
    }
}

struct SkipSymbolGlyph: View {
    let forward: Bool
    let turns: Double
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                SkipArrowShape(forward: forward, turns: turns).fill(.foreground)
                Text("10")
                    .font(.system(size: min(geometry.size.width, geometry.size.height) * 0.43,
                                  weight: .medium, design: .rounded).monospacedDigit())
            }.frame(width: geometry.size.width, height: geometry.size.height)
        }
    }
}

struct SkipArrowShape: Shape {
    let forward: Bool
    var turns: Double
    func path(in rect: CGRect) -> Path {
        // Unit circle: the arrowhead stays inside its envelope during rotation.
        // Transform into the SF-glyph-sized frame last, preserving that frame's
        // width, height and center throughout the turn.
        var arc = Path()
        arc.addArc(center: .zero, radius: 0.925, startAngle: .degrees(-30),
                   endAngle: .degrees(270), clockwise: false)
        var arrow = arc.strokedPath(StrokeStyle(lineWidth: 0.15, lineCap: .round))
        func point(_ degrees: Double, _ radius: Double) -> CGPoint {
            let radians = degrees * .pi / 180
            return CGPoint(x: cos(radians) * radius, y: sin(radians) * radius)
        }
        var head = Path()
        head.move(to: point(-65, 0.96))
        head.addLine(to: point(-102, 0.99))
        head.addLine(to: point(-96, 0.57)); head.closeSubpath()
        arrow.addPath(head)
        if !forward { arrow = arrow.applying(CGAffineTransform(scaleX: -1, y: 1)) }
        let angle = (forward ? 1.0 : -1.0) * turns * 2 * .pi
        return arrow.applying(CGAffineTransform(rotationAngle: angle)
            .concatenating(CGAffineTransform(scaleX: rect.width / 2, y: rect.height / 2))
            .concatenating(CGAffineTransform(translationX: rect.midX, y: rect.midY)))
    }
}
