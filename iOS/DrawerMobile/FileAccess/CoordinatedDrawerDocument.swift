import Foundation

/// Foreground presenter for the externally owned Drawer.md. Apple explicitly
/// warns against leaving file presenters registered while an iOS app is
/// backgrounded, so DrawerMobileModel starts/stops this with scene activity.
final class DrawerFilePresenter: NSObject, NSFilePresenter {
    let presentedItemURL: URL?
    let presentedItemOperationQueue: OperationQueue
    var onChange: (() -> Void)?
    var onMove: ((URL) -> Void)?

    init(url: URL) {
        presentedItemURL = url
        let queue = OperationQueue()
        queue.name = "com.bbrizly.drawer.ios.file-presenter"
        queue.maxConcurrentOperationCount = 1
        presentedItemOperationQueue = queue
        super.init()
    }

    func presentedItemDidChange() {
        DispatchQueue.main.async { [weak self] in self?.onChange?() }
    }

    func presentedItemDidMove(to newURL: URL) {
        DispatchQueue.main.async { [weak self] in self?.onMove?(newURL) }
    }
}

final class CoordinatedDrawerDocument {
    let session: DrawerFileSession
    private let presenter: DrawerFilePresenter
    private var observing = false

    init(session: DrawerFileSession) {
        self.session = session
        presenter = DrawerFilePresenter(url: session.url)
    }

    var url: URL { session.url }

    func read() throws -> Data { try session.read() }
    func write(_ data: Data) throws { try session.write(data) }

    func startObserving(onChange: @escaping () -> Void, onMove: @escaping (URL) -> Void) {
        presenter.onChange = onChange
        presenter.onMove = onMove
        guard !observing else { return }
        NSFileCoordinator.addFilePresenter(presenter)
        observing = true
    }

    func stopObserving() {
        guard observing else { return }
        NSFileCoordinator.removeFilePresenter(presenter)
        observing = false
    }

    deinit {
        if observing {
            NSFileCoordinator.removeFilePresenter(presenter)
        }
    }
}
