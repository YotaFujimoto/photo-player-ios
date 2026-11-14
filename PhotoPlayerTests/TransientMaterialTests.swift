import XCTest
import SwiftUI
@testable import PhotoPlayer

final class TransientMaterialTests: XCTestCase {
    @MainActor func testInformationSurfacesPreserveCanvasAndPassThroughOnBrightAndDarkFrames() async throws {
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let previous = scene.windows.first(where: \.isKeyWindow)
        let window = UIWindow(windowScene: scene)
        defer { window.isHidden = true; previous?.makeKey() }
        for size in [CGSize(width: 390, height: 844), CGSize(width: 844, height: 390)] {
            for bright in [false, true] {
                let surface = MaterialUnderlay(frame: .zero)
                surface.backgroundColor = bright ? .white : .black
                let host = UIHostingController(rootView: ZStack {
                    MaterialCanvas(surface: surface)
                    VStack(spacing: 12) {
                        Text("+11.4s").font(.system(size: 16).monospacedDigit())
                            .frame(width: 96, height: 32).transientMaterial()
                        Text("2×").font(.headline.monospacedDigit()).padding(10).transientMaterial(circular: true)
                        Text("Saved 10 photos.").font(.system(size: 16))
                            .padding(.horizontal, 12).padding(.vertical, 7).transientMaterial()
                        VStack(spacing: 8) {
                            ProgressView(); Text("Saving to Photos…").font(.caption)
                        }.padding().transientMaterial()
                        Image(systemName: "goforward.10").font(.system(size: 24))
                            .shadow(color: .black.opacity(0.4), radius: 1, y: 1)
                            .frame(width: 44, height: 44).allowsHitTesting(false)
                    }.allowsHitTesting(false)
                }.foregroundStyle(.white).tint(.white).ignoresSafeArea())
                window.frame = CGRect(origin: .zero, size: size)
                window.rootViewController = host; window.makeKeyAndVisible()
                host.view.frame = window.bounds
                let deadline = ContinuousClock.now.advanced(by: .seconds(5))
                while surface.window == nil && ContinuousClock.now < deadline { try await Task.sleep(for: .milliseconds(20)) }
                host.view.layoutIfNeeded()
                XCTAssertEqual(surface.bounds.size, size)
                // A HUD placed on the canvas must not become a touch destination.
                XCTAssertTrue(host.view.hitTest(CGPoint(x: size.width / 2, y: size.height / 2), with: nil) === surface)
                let image = UIGraphicsImageRenderer(size: size).image { _ in
                    XCTAssertTrue(host.view.drawHierarchy(in: host.view.bounds, afterScreenUpdates: true))
                }
                let attachment = XCTAttachment(image: image)
                attachment.name = "information-material-\(Int(size.width))-\(bright ? "bright" : "dark")"
                attachment.lifetime = .keepAlways; add(attachment)
            }
        }
    }
}

private final class MaterialUnderlay: UIView {}
private struct MaterialCanvas: UIViewRepresentable {
    let surface: MaterialUnderlay
    func makeUIView(context: Context) -> MaterialUnderlay { surface }
    func updateUIView(_ view: MaterialUnderlay, context: Context) {}
}
