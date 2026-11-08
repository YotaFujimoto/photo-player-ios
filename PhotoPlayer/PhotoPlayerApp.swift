import SwiftUI
import UIKit

@main
@MainActor
enum PhotoPlayerApp {
    static func main() {
        UIApplicationMain(CommandLine.argc, CommandLine.unsafeArgv,
                          NSStringFromClass(PhotoPlayerApplication.self), NSStringFromClass(AppDelegate.self))
    }
}

// A single process-owned entry, before UIKit dispatches to any window/recognizer.
// No gesture recognizer, swizzling, event suppression, or synthetic re-taps.
final class PhotoPlayerApplication: UIApplication {
    let selectionTrace = SelectionTrace()
    lazy var input = ApplicationInput(trace: selectionTrace,
        enabled: !ProcessInfo.processInfo.arguments.contains("--disable-input-monitor"))

    override func sendEvent(_ event: UIEvent) {
        let samples = event.type == .touches ? (event.allTouches ?? []).map { InputSample(touch: $0) } : []
        input.dispatch(samples) { super.sendEvent(event) }
    }
}

final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication, configurationForConnecting session: UISceneSession,
                     options: UIScene.ConnectionOptions) -> UISceneConfiguration {
        let config = UISceneConfiguration(name: "PhotoPlayer", sessionRole: session.role)
        config.delegateClass = AppSceneDelegate.self
        return config
    }
}

@MainActor
final class AppSceneState: ObservableObject {
    @Published var phase: ScenePhase = .inactive
    let trace: SelectionTrace
    init(trace: SelectionTrace) { self.trace = trace }
    func transition(_ phase: ScenePhase, reason: String) {
        trace.lifecycle(reason)
        self.phase = phase
    }
}

final class AppSceneDelegate: NSObject, UIWindowSceneDelegate {
    var window: UIWindow?
    private var state: AppSceneState?
    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options: UIScene.ConnectionOptions) {
        guard let scene = scene as? UIWindowScene, let app = UIApplication.shared as? PhotoPlayerApplication else { return }
        let state = AppSceneState(trace: app.selectionTrace)
        self.state = state
        let window = UIWindow(windowScene: scene)
        window.rootViewController = UIHostingController(rootView: AppRoot(state: state))
        self.window = window
        window.makeKeyAndVisible()
        state.trace.lifecycle("scene.connect")
    }
    func sceneDidBecomeActive(_ scene: UIScene) { state?.transition(.active, reason: "scene.active") }
    func sceneWillResignActive(_ scene: UIScene) { state?.transition(.inactive, reason: "scene.inactive") }
    func sceneDidEnterBackground(_ scene: UIScene) { state?.transition(.background, reason: "scene.background") }
    func sceneWillEnterForeground(_ scene: UIScene) { state?.transition(.inactive, reason: "scene.foreground") }
    func sceneDidDisconnect(_ scene: UIScene) { state?.transition(.background, reason: "scene.disconnect") }
}

private struct AppRoot: View {
    @ObservedObject var state: AppSceneState
    @State private var tab = 0
    var body: some View {
        TabView(selection: $tab) {
            LibraryScreen(trace: state.trace).tabItem { Label("動画", systemImage: "play.rectangle") }.tag(0)
            CounterView().tabItem { Label("導入確認", systemImage: "checkmark.circle") }.tag(1)
        }
        .environment(\.scenePhase, state.phase)
        .onChange(of: tab) { _, value in state.trace.lifecycle("tab.\(value == 0 ? "library" : "counter")") }
    }
}
