import Foundation

/// The one task title or note being typed into right now.
///
/// A title or note only reaches the file on submit or on blur, so quitting mid
/// edit used to lose whatever was typed. The other stores each get a `saveNow()`
/// at termination; the task file had no equivalent because the draft lives in
/// per-row view state that nothing outside the row can reach.
///
/// One slot, because the app only ever has one focused field. The row claims it
/// when a field opens and drops it when the field saves, so at quit there is
/// either nothing to do or exactly one edit to commit.
///
/// ponytail: a shared instance, not an injected dependency. There is one
/// drawer window and one focused field in the process; threading an object from
/// AppDelegate through DrawerView to every row buys nothing.
@MainActor
final class OpenTaskEdit {
    static let shared = OpenTaskEdit()

    private var save: (() -> Void)?

    /// The field just opened. `commit` is whatever the row's own save does.
    func claim(_ commit: @escaping () -> Void) { save = commit }

    /// The field saved itself the normal way.
    func release() { save = nil }

    /// Write the open edit through, once. Called on the way out.
    func commit() {
        let pending = save
        save = nil
        pending?()
    }
}
