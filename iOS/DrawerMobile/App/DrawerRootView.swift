import SwiftUI
import UIKit
import UniformTypeIdentifiers

struct DrawerRootView: View {
    @ObservedObject var model: DrawerMobileModel
    @State private var showingImporter = false

    private var markdownTypes: [UTType] {
        var types: [UTType] = [.plainText]
        if let markdown = UTType(filenameExtension: "md") {
            types.insert(markdown, at: 0)
        }
        return types
    }

    var body: some View {
        ZStack {
            DrawerBackdrop()
            switch model.connectionState {
            case .loading:
                ProgressView()
                    .controlSize(.large)
            case .connected:
                DrawerHomeView(
                    model: model,
                    changeFile: { showingImporter = true }
                )
            case .disconnected, .needsPermission:
                DrawerConnectionView(
                    needsPermission: model.connectionState == .needsPermission,
                    message: model.statusMessage,
                    chooseFile: { showingImporter = true }
                )
            }
        }
        .fileImporter(
            isPresented: $showingImporter,
            allowedContentTypes: markdownTypes,
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                if let url = urls.first { model.connect(to: url) }
            case .failure(let error):
                let nsError = error as NSError
                if nsError.domain == NSCocoaErrorDomain,
                   nsError.code == CocoaError.userCancelled.rawValue {
                    return
                }
                model.statusMessage = error.localizedDescription
                DrawerHaptics.shared.error()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .NSCalendarDayChanged)) { _ in
            model.handleSignificantTimeChange()
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.significantTimeChangeNotification)) { _ in
            model.handleSignificantTimeChange()
        }
        .onReceive(NotificationCenter.default.publisher(for: .NSSystemTimeZoneDidChange)) { _ in
            model.handleSignificantTimeChange()
        }
    }
}

private struct DrawerBackdrop: View {
    var body: some View {
        ZStack {
            Color(uiColor: .systemGroupedBackground)
            RadialGradient(
                colors: [
                    Color.accentColor.opacity(0.10),
                    Color.clear,
                ],
                center: .topTrailing,
                startRadius: 10,
                endRadius: 440
            )
            .ignoresSafeArea()
        }
        .ignoresSafeArea()
    }
}
