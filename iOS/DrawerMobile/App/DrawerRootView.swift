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
                    .accessibilityLabel("Opening Drawer")
            case .connected:
                DrawerHomeView(
                    model: model,
                    changeFile: { showingImporter = true }
                )
            case .waitingForProvider:
                DrawerConnectionView(
                    needsPermission: false,
                    waitingForProvider: true,
                    message: model.statusMessage,
                    chooseFile: { showingImporter = true }
                )
            case .disconnected, .needsPermission:
                DrawerConnectionView(
                    needsPermission: model.connectionState == .needsPermission,
                    waitingForProvider: false,
                    message: model.statusMessage,
                    chooseFile: { showingImporter = true }
                )
            }
        }
        .tint(DrawerPalette.accent)
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
                model.reportError(error)
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
        DrawerPalette.canvas
        .ignoresSafeArea()
    }
}

enum DrawerPalette {
    static let canvas = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0.075, green: 0.072, blue: 0.065, alpha: 1)
            : UIColor(red: 0.965, green: 0.952, blue: 0.925, alpha: 1)
    })

    static let surface = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0.12, green: 0.115, blue: 0.105, alpha: 1)
            : UIColor(red: 0.985, green: 0.978, blue: 0.955, alpha: 1)
    })

    static let ink = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark ? .white : UIColor(red: 0.12, green: 0.105, blue: 0.09, alpha: 1)
    })

    static let accent = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 1.0, green: 0.60, blue: 0.30, alpha: 1)
            : UIColor(red: 0.82, green: 0.30, blue: 0.14, alpha: 1)
    })
}
