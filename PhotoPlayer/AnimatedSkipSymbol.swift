import SwiftUI

/// The ring/head alone rotate; the numeral is a separate, stationary sibling.
/// Time is measured from the current feedback, so replacement never queues turns.
struct AnimatedSkipSymbol: View {
    let feedback: SkipFeedback
    let reduceMotion: Bool
    static let turnDuration = 0.28

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
                let artwork = forward ? SkipArrowArtwork.forward : SkipArrowArtwork.backward
                let side = min(geometry.size.width, geometry.size.height)
                let scale = side / (2 * artwork.radius)
                Image(uiImage: artwork.image).resizable()
                    .frame(width: artwork.size.width * scale, height: artwork.size.height * scale)
                    .offset(x: (artwork.size.width / 2 - artwork.center.x) * scale,
                            y: (artwork.size.height / 2 - artwork.center.y) * scale)
                    .frame(width: side, height: side)
                    .rotationEffect(.degrees((forward ? 1 : -1) * turns * 360))
                Text("10")
                    .font(.system(size: min(geometry.size.width, geometry.size.height) * 0.43,
                                  weight: .medium, design: .rounded).monospacedDigit())
            }.frame(width: geometry.size.width, height: geometry.size.height)
        }
    }
}

/// Measure only the two official SF glyphs once, never video pixels. The lower
/// semicircle defines the rotation center independently of the arrowhead. This
/// preserves Apple's artwork while avoiding a pivot at its asymmetric bounds.
private struct SkipArrowArtwork {
    let image: UIImage
    let size: CGSize
    let center: CGPoint
    let radius: CGFloat
    static let forward = Self(name: "goforward")
    static let backward = Self(name: "gobackward")
    init(name: String) {
        let symbol = UIImage(systemName: name, withConfiguration: UIImage.SymbolConfiguration(pointSize: 128, weight: .regular))!
        self.image = symbol.withRenderingMode(.alwaysTemplate)
        let format = UIGraphicsImageRendererFormat(); format.scale = 1; format.opaque = false
        let image = UIGraphicsImageRenderer(size: symbol.size, format: format).image { _ in
            symbol.withTintColor(.white, renderingMode: .alwaysOriginal).draw(at: .zero)
        }.cgImage!
        let w = image.width, h = image.height
        var bytes = [UInt8](repeating: 0, count: w * h * 4)
        bytes.withUnsafeMutableBytes { raw in
            let context = CGContext(data: raw.baseAddress, width: w, height: h, bitsPerComponent: 8,
                bytesPerRow: w * 4, space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
            context.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        }
        var ink: [CGPoint] = []
        for y in 0..<h { for x in 0..<w where bytes[(y*w+x)*4+3] > 127 {
            ink.append(CGPoint(x: CGFloat(x)+0.5, y: CGFloat(y)+0.5))
        } }
        let lower = ink.filter { $0.y >= CGFloat(h) * 0.45 }
        let left = lower.map(\.x).min()!, right = lower.map(\.x).max()!
        let bottom = lower.map(\.y).max()!
        let pivot = CGPoint(x: (left + right) / 2, y: bottom - (right - left) / 2)
        center = pivot
        radius = ink.map { hypot($0.x - pivot.x, $0.y - pivot.y) }.max()! + 0.5
        size = symbol.size
    }
}
