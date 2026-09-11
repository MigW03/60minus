import ApplicationServices
import Foundation

struct NumberSuggestion: Equatable {
    enum Kind: Equatable {
        case digitSequence
        case compound
    }

    let originalText: String
    let replacement: String
    let alternatives: [String]
    let range: NSRange
    let kind: Kind
}

struct TextSnapshot {
    enum CoordinateSpace {
        case characterRange
        case textMarkers(owner: AXUIElement)
    }

    let element: AXUIElement
    let processIdentifier: pid_t
    let selectedRange: NSRange
    let textBeforeCaret: String
    let textBeforeCaretStart: Int
    let characterAfterCaret: String?
    let coordinateSpace: CoordinateSpace

    init(
        element: AXUIElement,
        processIdentifier: pid_t,
        selectedRange: NSRange,
        textBeforeCaret: String,
        textBeforeCaretStart: Int,
        characterAfterCaret: String?,
        coordinateSpace: CoordinateSpace = .characterRange
    ) {
        self.element = element
        self.processIdentifier = processIdentifier
        self.selectedRange = selectedRange
        self.textBeforeCaret = textBeforeCaret
        self.textBeforeCaretStart = textBeforeCaretStart
        self.characterAfterCaret = characterAfterCaret
        self.coordinateSpace = coordinateSpace
    }
}

enum ScanReason {
    case boundary
    case editedTextSettled
}
