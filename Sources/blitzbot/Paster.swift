import AppKit

enum Paster {
    /// Pastes `text` via clipboard + ⌘V. If `autoReturn` is true and the paste was successful
    /// (non-empty text, clipboard write succeeded), sends a Return key shortly after.
    static func pasteText(_ text: String, autoReturn: Bool = false) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            Log.write("paste skipped: empty text (autoReturn=\(autoReturn))")
            return
        }

        let pb = NSPasteboard.general
        pb.clearContents()
        let ok = pb.setString(text, forType: .string)
        Log.write("clipboard set ok=\(ok) len=\(text.count)")

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
            simulateCommandV()
            if autoReturn && ok {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) {
                    simulateReturn()
                }
            } else if autoReturn {
                Log.write("autoReturn skipped: clipboard write failed")
            }
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

    private static func simulateReturn() {
        let source = CGEventSource(stateID: .combinedSessionState)
        let returnKey: CGKeyCode = 36

        let down = CGEvent(keyboardEventSource: source, virtualKey: returnKey, keyDown: true)
        let up = CGEvent(keyboardEventSource: source, virtualKey: returnKey, keyDown: false)

        let tap: CGEventTapLocation = .cgAnnotatedSessionEventTap
        down?.post(tap: tap)
        usleep(20_000)
        up?.post(tap: tap)
        Log.write("Return posted via \(tap)")
    }
}
