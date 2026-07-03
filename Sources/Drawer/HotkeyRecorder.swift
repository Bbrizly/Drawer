import AppKit

@MainActor
final class HotkeyRecorder {
    private var monitor: Any?

    func start(capture: @escaping (UInt32) -> Void) {
        stop()
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            capture(UInt32(event.keyCode))
            return nil
        }
    }

    func stop() {
        if let monitor {
            NSEvent.removeMonitor(monitor)
            self.monitor = nil
        }
    }

    deinit {
        if let monitor { NSEvent.removeMonitor(monitor) }
    }
}
