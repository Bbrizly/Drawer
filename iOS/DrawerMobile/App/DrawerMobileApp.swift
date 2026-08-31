import SwiftUI

@main
struct DrawerMobileApp: App {
    @StateObject private var model = DrawerMobileModel()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            DrawerRootView(model: model)
                .task {
                    // ActivityKit and pending local notifications can outlive a
                    // process. If there is no persisted Focus session after the
                    // model's restore pass, clear any orphan system surface.
                    // A legitimate restored session remains untouched because
                    // it has already repopulated DrawerFocusStore.
                    if DrawerFocusStore.load() == nil {
                        FocusNotificationScheduler.cancel()
                    }
                    model.bootstrap()
                }
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
