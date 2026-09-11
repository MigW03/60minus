import Foundation
import ApplicationServices
import Testing
@testable import SixtyMinusApp

struct NumberParserTests {
    private let parser = NumberParser()

    @Test func digitSequence() {
        let suggestion = parser.suggestion(in: "five five three ")
        #expect(suggestion?.replacement == "553")
        #expect(suggestion?.originalText == "five five three")
        #expect(suggestion?.alternatives == ["5 5 3"])
    }

    @Test func correctedTrailingWordIsReadFromCurrentDocumentText() {
        // This is the state after the user changed `tee` to `three`.
        let suggestion = parser.suggestion(in: "five five three")
        #expect(suggestion?.replacement == "553")
        #expect(suggestion?.range == NSRange(location: 0, length: 15))
    }

    @Test func invalidTrailingWordDoesNotReachBackToEarlierNumbers() {
        #expect(parser.suggestion(in: "five five tee ") == nil)
    }

    @Test func findsNumberAfterOrdinaryPrefix() {
        let suggestion = parser.suggestion(in: "call me at five five three ")
        #expect(suggestion?.replacement == "553")
        #expect(suggestion?.originalText == "five five three")
    }

    @Test func compoundNumber() {
        #expect(parser.suggestion(in: "one hundred forty two ")?.replacement == "142")
    }

    @Test func mixedSpokenChunksAreConcatenatedRatherThanAdded() {
        let suggestion = parser.suggestion(in: "one two ten ")
        #expect(suggestion?.replacement == "1210")
        #expect(suggestion?.alternatives == ["1 2 10"])
    }

    @Test func tensAndUnitRemainAConventionalCompoundChunk() {
        let suggestion = parser.suggestion(in: "twenty one ")
        #expect(suggestion?.replacement == "21")
        #expect(suggestion?.alternatives == [])
    }

    @Test func teenFollowedByDigitsIsAChunkSequence() {
        #expect(parser.suggestion(in: "ten nine three ")?.replacement == "1093")
    }

    @Test func punctuationDoesNotJoinSeparateNumberPhrases() {
        #expect(parser.suggestion(in: "five, three ")?.replacement == "3")
    }

    @Test func newlineDoesNotJoinSeparateNumberPhrases() {
        let suggestion = parser.suggestion(in: "five five three\nfive two ")
        #expect(suggestion?.originalText == "five two")
        #expect(suggestion?.replacement == "52")
        #expect(suggestion?.range == NSRange(location: 16, length: 8))
    }

    @Test func trailingNewlineStillCompletesThePrecedingPhrase() {
        let suggestion = parser.suggestion(in: "five five three\n")
        #expect(suggestion?.originalText == "five five three")
        #expect(suggestion?.replacement == "553")
    }

    @Test func rangeUsesUTF16Offsets() {
        let suggestion = parser.suggestion(in: "🙂 five three ", globalOffset: 10)
        #expect(suggestion?.range == NSRange(location: 13, length: 10))
    }
}

struct ContextScannerTests {
    private let scanner = ContextScanner()

    @Test func editedWordBeforeExistingSeparatorProducesSuggestion() {
        let snapshot = makeSnapshot(before: "five five three", after: " ")
        #expect(scanner.suggestion(from: snapshot, reason: .editedTextSettled)?.replacement == "553")
    }

    @Test func editedWordAtEndOfFieldProducesSuggestion() {
        let snapshot = makeSnapshot(before: "five five three", after: nil)
        #expect(scanner.suggestion(from: snapshot, reason: .editedTextSettled)?.replacement == "553")
    }

    @Test func editDoesNotFireWhileCaretIsStillInsideAWord() {
        let snapshot = makeSnapshot(before: "five five thr", after: "e")
        #expect(scanner.suggestion(from: snapshot, reason: .editedTextSettled) == nil)
    }

    @Test func scannerStopsAtLineBoundary() {
        let snapshot = makeSnapshot(before: "five five three\nfive two ", after: nil)
        let suggestion = scanner.suggestion(from: snapshot, reason: .boundary)
        #expect(suggestion?.originalText == "five two")
        #expect(suggestion?.replacement == "52")
    }

    private func makeSnapshot(before: String, after: String?) -> TextSnapshot {
        TextSnapshot(
            element: AXUIElementCreateSystemWide(),
            processIdentifier: 1,
            selectedRange: NSRange(location: (before as NSString).length, length: 0),
            textBeforeCaret: before,
            textBeforeCaretStart: 0,
            characterAfterCaret: after
        )
    }
}
