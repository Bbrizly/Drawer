import SwiftUI

@main
struct DrawerMobileApp: App {
    @StateObject private var model = DrawerMobileModel()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            DrawerRootView(model: model)
                .task { model.bootstrap() }
                .onOpenURL { url in
                    guard url.scheme == "drawer" else { return }
                    if url.host == "capture" || url.path == "/capture" {
                        model.requestCapture()
                    }
                }
                .onChange(of: scenePhase) { _, phase in
                    model.setSceneActive(phase == .active)
                }
        }
    }
}
