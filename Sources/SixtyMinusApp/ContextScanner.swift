import Foundation

struct ContextScanner {
    private let parser = NumberParser()

    func suggestion(from snapshot: TextSnapshot, reason: ScanReason) -> NumberSuggestion? {
        if case .editedTextSettled = reason,
           let next = snapshot.characterAfterCaret,
           !isBoundary(next) {
            // During an in-place edit, only consider the word complete when
            // the caret is at an existing separator or at the end of text.
            return nil
        }

        return parser.suggestion(
            in: snapshot.textBeforeCaret,
            globalOffset: snapshot.textBeforeCaretStart
        )
    }

    private func isBoundary(_ text: String) -> Bool {
        guard let scalar = text.unicodeScalars.first else { return true }
        return CharacterSet.whitespacesAndNewlines
            .union(.punctuationCharacters)
            .contains(scalar)
    }
}
