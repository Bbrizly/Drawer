import Foundation

/// A value we want to remember without redrawing anything.
///
/// Some views measure themselves during layout (a frame, a height) and only
/// need that number later, when a click or a tick comes in. Keeping it in
/// `@State` looks harmless but is not: the write asks SwiftUI for another
/// layout pass, that pass measures again, and the two feed each other. With
/// enough views on screen it never settles and the main thread spins until you
/// force quit. That was the freeze fixed in d08fc61.
///
/// A plain reference is invisible to SwiftUI, so writing to it costs a pointer
/// store and nothing else. Reach for this whenever a measurement is read by an
/// event handler rather than drawn.
final class Box<Value> {
    var value: Value

    init(_ value: Value) {
        self.value = value
    }
}
