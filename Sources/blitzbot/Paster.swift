import AppKit

enum Paster {
    static func pasteText(_ text: String) {
        let pb = NSPasteboard.general
        pb.clearContents()
        let ok = pb.setString(text, forType: .string)
        Log.write("clipboard set ok=\(ok) len=\(text.count)")

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
            simulateCommandV()
        }
    }

    private static func simulateCommandV() {
        let source = CGEventSource(stateID: .combinedSessionState)
        let vKey: CGKeyCode = 9

        let down = CGEvent(keyboardEventSource: source, virtualKey: vKey, keyDown: true)
        down?.flags = .maskCommand
        let up = CGEvent(keyboardEventSource: source, virtualKey: vKey, keyDown: false)
        up?.flags = .maskCommand

        let tap: CGEventTapLocation = .cgAnnotatedSessionEventTap
        down?.post(tap: tap)
        usleep(20_000)
        up?.post(tap: tap)
        Log.write("Cmd+V posted via \(tap)")
    }
}
