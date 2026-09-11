import AppKit
import ApplicationServices
import Foundation

final class AccessibilityClient {
    private let contextLimit = 256
    private let selectedMarkerRangeAttribute = "AXSelectedTextMarkerRange" as CFString
    private let markerForIndexAttribute = "AXTextMarkerForIndex" as CFString
    private let indexForMarkerAttribute = "AXIndexForTextMarker" as CFString
    private let markerRangeForElementAttribute = "AXTextMarkerRangeForUIElement" as CFString
    private let stringForMarkerRangeAttribute = "AXStringForTextMarkerRange" as CFString
    private let boundsForMarkerRangeAttribute = "AXBoundsForTextMarkerRange" as CFString

    static var isTrusted: Bool {
        AXIsProcessTrusted()
    }

    static func requestPermission() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }

    func focusedSnapshot() -> TextSnapshot? {
        guard let element = focusedElement(), !isProtected(element) else { return nil }

        var pid: pid_t = 0
        guard AXUIElementGetPid(element, &pid) == .success else { return nil }

        if let selectedRange = selectedTextRange(of: element),
           selectedRange.length == 0,
           let snapshot = characterRangeSnapshot(element: element, pid: pid, selectedRange: selectedRange) {
            return snapshot
        }

        // WebKit and Chromium editors commonly expose text through document-scoped
        // AX text markers instead of the character-range attributes used by native
        // NSTextField/NSTextView controls. The marker attributes may live on the
        // focused element or on one of its ancestors.
        var candidate: AXUIElement? = element
        for _ in 0..<12 {
            guard let owner = candidate else { break }
            if let snapshot = textMarkerSnapshot(element: element, owner: owner, pid: pid) {
                return snapshot
            }
            candidate = copyElementAttribute(owner, kAXParentAttribute as CFString)
        }

        return nil
    }

    func caretBounds(for snapshot: TextSnapshot) -> CGRect? {
        let exact: CGRect?
        switch snapshot.coordinateSpace {
        case .characterRange:
            exact = bounds(for: snapshot.selectedRange, of: snapshot.element)
        case .textMarkers(let owner):
            exact = markerCaretBounds(at: snapshot.selectedRange.location, owner: owner)
        }

        if let exact, isUsable(exact) {
            return exact
        }
        if let frame = frame(of: snapshot.element), isUsable(frame) {
            return CGRect(x: frame.minX + 8, y: frame.maxY - 22, width: 1, height: 20)
        }
        if let location = CGEvent(source: nil)?.location {
            return CGRect(x: location.x, y: location.y, width: 1, height: 20)
        }
        return nil
    }

    func textBounds(for suggestion: NumberSuggestion, in snapshot: TextSnapshot) -> CGRect? {
        let exact: CGRect?
        switch snapshot.coordinateSpace {
        case .characterRange:
            exact = bounds(for: suggestion.range, of: snapshot.element)
        case .textMarkers(let owner):
            exact = markerRange(in: suggestion.range, owner: owner).flatMap {
                markerBounds(for: $0, owner: owner)
            }
        }

        if let exact, isUsable(exact) {
            return exact
        }
        return caretBounds(for: snapshot)
    }

    func replace(_ suggestion: NumberSuggestion, in snapshot: TextSnapshot, with replacement: String) -> Bool {
        guard let current = focusedSnapshot(),
              current.processIdentifier == snapshot.processIdentifier,
              CFEqual(current.element, snapshot.element),
              string(in: suggestion.range, snapshot: current) == suggestion.originalText else {
            return false
        }

        switch current.coordinateSpace {
        case .characterRange:
            return replaceCharacterRange(suggestion.range, in: current.element, with: replacement)
        case .textMarkers(let owner):
            return replaceMarkerRange(
                suggestion.range,
                focusedElement: current.element,
                owner: owner,
                with: replacement
            )
        }
    }

    private func focusedElement() -> AXUIElement? {
        let system = AXUIElementCreateSystemWide()
        if let element = copyElementAttribute(system, kAXFocusedUIElementAttribute as CFString) {
            return element
        }

        // A few applications do not populate the system-wide focused element but
        // do answer the same query on their application accessibility object.
        guard let pid = NSWorkspace.shared.frontmostApplication?.processIdentifier else { return nil }
        return copyElementAttribute(
            AXUIElementCreateApplication(pid),
            kAXFocusedUIElementAttribute as CFString
        )
    }

    private func characterRangeSnapshot(
        element: AXUIElement,
        pid: pid_t,
        selectedRange: NSRange
    ) -> TextSnapshot? {
        let start = max(0, selectedRange.location - contextLimit)
        let beforeRange = NSRange(location: start, length: selectedRange.location - start)
        guard let before = string(in: beforeRange, of: element) else { return nil }

        let after = string(in: NSRange(location: selectedRange.location, length: 1), of: element)
        return TextSnapshot(
            element: element,
            processIdentifier: pid,
            selectedRange: selectedRange,
            textBeforeCaret: before,
            textBeforeCaretStart: start,
            characterAfterCaret: after?.isEmpty == false ? after : nil,
            coordinateSpace: .characterRange
        )
    }

    private func replaceCharacterRange(_ range: NSRange, in element: AXUIElement, with replacement: String) -> Bool {
        guard let rangeValue = axValue(for: range) else { return false }
        var settable = DarwinBoolean(false)
        let settableResult = AXUIElementIsAttributeSettable(
            element,
            kAXSelectedTextRangeAttribute as CFString,
            &settable
        )
        guard settableResult != .success || settable.boolValue else {
            return false
        }

        guard AXUIElementSetAttributeValue(
            element,
            kAXSelectedTextRangeAttribute as CFString,
            rangeValue
        ) == .success else {
            return false
        }

        return AXUIElementSetAttributeValue(
            element,
            kAXSelectedTextAttribute as CFString,
            replacement as CFString
        ) == .success
    }

    private func textMarkerSnapshot(
        element: AXUIElement,
        owner: AXUIElement,
        pid: pid_t
    ) -> TextSnapshot? {
        guard let selection = markerRangeAttribute(selectedMarkerRangeAttribute, of: owner) else {
            return nil
        }
        let selectionStart = AXTextMarkerRangeCopyStartMarker(selection)
        let selectionEnd = AXTextMarkerRangeCopyEndMarker(selection)
        guard let caretIndex = markerIndex(selectionStart, owner: owner),
              markerIndex(selectionEnd, owner: owner) == caretIndex else {
            return nil
        }

        var elementStart = 0
        var elementEnd = Int.max
        if let elementRange = markerRange(for: element, owner: owner) {
            let startMarker = AXTextMarkerRangeCopyStartMarker(elementRange)
            let endMarker = AXTextMarkerRangeCopyEndMarker(elementRange)
            elementStart = markerIndex(startMarker, owner: owner) ?? elementStart
            elementEnd = markerIndex(endMarker, owner: owner) ?? elementEnd
        }

        let contextStart = max(elementStart, caretIndex - contextLimit)
        guard let before = markerString(
            in: NSRange(location: contextStart, length: caretIndex - contextStart),
            owner: owner
        ) else {
            return nil
        }

        let after: String?
        if caretIndex < elementEnd {
            let value = markerString(in: NSRange(location: caretIndex, length: 1), owner: owner)
            after = value?.isEmpty == false ? value : nil
        } else {
            after = nil
        }

        return TextSnapshot(
            element: element,
            processIdentifier: pid,
            selectedRange: NSRange(location: caretIndex, length: 0),
            textBeforeCaret: before,
            textBeforeCaretStart: contextStart,
            characterAfterCaret: after,
            coordinateSpace: .textMarkers(owner: owner)
        )
    }

    private func replaceMarkerRange(
        _ range: NSRange,
        focusedElement: AXUIElement,
        owner: AXUIElement,
        with replacement: String
    ) -> Bool {
        guard let markerRange = markerRange(in: range, owner: owner) else { return false }

        let selectionTargets = sameElement(focusedElement, owner)
            ? [owner]
            : [focusedElement, owner]
        guard set(markerRange, attribute: selectedMarkerRangeAttribute, onAny: selectionTargets) else {
            return false
        }

        let replacementTargets = sameElement(focusedElement, owner)
            ? [focusedElement]
            : [focusedElement, owner]
        if set(replacement as CFString, attribute: kAXSelectedTextAttribute as CFString, onAny: replacementTargets) {
            return true
        }

        // Some web editors allow assistive technologies to set their marker
        // selection but not AXSelectedText. Typing Unicode events replaces that
        // selected range without touching the user's clipboard.
        return postUnicode(replacement)
    }

    private func string(in range: NSRange, snapshot: TextSnapshot) -> String? {
        switch snapshot.coordinateSpace {
        case .characterRange:
            return string(in: range, of: snapshot.element)
        case .textMarkers(let owner):
            return markerString(in: range, owner: owner)
        }
    }

    private func selectedTextRange(of element: AXUIElement) -> NSRange? {
        var raw: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            element,
            kAXSelectedTextRangeAttribute as CFString,
            &raw
        ) == .success, let raw else {
            return nil
        }

        guard CFGetTypeID(raw) == AXValueGetTypeID() else { return nil }
        let value = unsafeBitCast(raw, to: AXValue.self)
        var range = CFRange()
        guard AXValueGetValue(value, .cfRange, &range), range.location >= 0, range.length >= 0 else {
            return nil
        }
        return NSRange(location: range.location, length: range.length)
    }

    private func string(in range: NSRange, of element: AXUIElement) -> String? {
        guard let rangeValue = axValue(for: range) else { return nil }
        var raw: CFTypeRef?
        let result = AXUIElementCopyParameterizedAttributeValue(
            element,
            kAXStringForRangeParameterizedAttribute as CFString,
            rangeValue,
            &raw
        )
        if result == .success, let string = raw as? String {
            return string
        }

        // Some controls expose the parameterized ranges poorly but do expose
        // their complete value. Keep this fallback bounded when slicing.
        var valueRaw: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            element,
            kAXValueAttribute as CFString,
            &valueRaw
        ) == .success, let full = valueRaw as? String else {
            return nil
        }
        let nsFull = full as NSString
        guard range.location >= 0, NSMaxRange(range) <= nsFull.length else { return nil }
        return nsFull.substring(with: range)
    }

    private func bounds(for range: NSRange, of element: AXUIElement) -> CGRect? {
        guard let rangeValue = axValue(for: range) else { return nil }
        var raw: CFTypeRef?
        guard AXUIElementCopyParameterizedAttributeValue(
            element,
            kAXBoundsForRangeParameterizedAttribute as CFString,
            rangeValue,
            &raw
        ) == .success, let raw else {
            return nil
        }
        guard CFGetTypeID(raw) == AXValueGetTypeID() else { return nil }
        let value = unsafeBitCast(raw, to: AXValue.self)
        var rect = CGRect.zero
        guard AXValueGetValue(value, .cgRect, &rect) else { return nil }
        return rect
    }

    private func markerRangeAttribute(_ attribute: CFString, of element: AXUIElement) -> AXTextMarkerRange? {
        var raw: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute, &raw) == .success,
              let raw,
              CFGetTypeID(raw) == AXTextMarkerRangeGetTypeID() else {
            return nil
        }
        return unsafeBitCast(raw, to: AXTextMarkerRange.self)
    }

    private func markerRange(for element: AXUIElement, owner: AXUIElement) -> AXTextMarkerRange? {
        var raw: CFTypeRef?
        guard AXUIElementCopyParameterizedAttributeValue(
            owner,
            markerRangeForElementAttribute,
            element,
            &raw
        ) == .success,
        let raw,
        CFGetTypeID(raw) == AXTextMarkerRangeGetTypeID() else {
            return nil
        }
        return unsafeBitCast(raw, to: AXTextMarkerRange.self)
    }

    private func marker(at index: Int, owner: AXUIElement) -> AXTextMarker? {
        var raw: CFTypeRef?
        guard AXUIElementCopyParameterizedAttributeValue(
            owner,
            markerForIndexAttribute,
            index as CFNumber,
            &raw
        ) == .success,
        let raw,
        CFGetTypeID(raw) == AXTextMarkerGetTypeID() else {
            return nil
        }
        return unsafeBitCast(raw, to: AXTextMarker.self)
    }

    private func markerIndex(_ marker: AXTextMarker, owner: AXUIElement) -> Int? {
        var raw: CFTypeRef?
        guard AXUIElementCopyParameterizedAttributeValue(
            owner,
            indexForMarkerAttribute,
            marker,
            &raw
        ) == .success,
        let number = raw as? NSNumber else {
            return nil
        }
        return number.intValue
    }

    private func markerRange(in range: NSRange, owner: AXUIElement) -> AXTextMarkerRange? {
        guard range.location >= 0,
              range.length >= 0,
              let start = marker(at: range.location, owner: owner),
              let end = marker(at: NSMaxRange(range), owner: owner) else {
            return nil
        }
        return AXTextMarkerRangeCreate(nil, start, end)
    }

    private func markerString(in range: NSRange, owner: AXUIElement) -> String? {
        guard let markerRange = markerRange(in: range, owner: owner) else { return nil }
        var raw: CFTypeRef?
        guard AXUIElementCopyParameterizedAttributeValue(
            owner,
            stringForMarkerRangeAttribute,
            markerRange,
            &raw
        ) == .success else {
            return nil
        }
        return raw as? String
    }

    private func markerCaretBounds(at index: Int, owner: AXUIElement) -> CGRect? {
        if let caretRange = markerRange(in: NSRange(location: index, length: 0), owner: owner),
           let rect = markerBounds(for: caretRange, owner: owner),
           isUsable(rect) {
            return rect
        }

        // Several Chromium versions return no rectangle for an empty marker
        // range. Use the adjacent glyph edge as the caret in that case.
        if let nextRange = markerRange(in: NSRange(location: index, length: 1), owner: owner),
           let next = markerBounds(for: nextRange, owner: owner),
           isUsable(next) {
            return CGRect(x: next.minX, y: next.minY, width: 1, height: max(1, next.height))
        }
        if index > 0,
           let previousRange = markerRange(in: NSRange(location: index - 1, length: 1), owner: owner),
           let previous = markerBounds(for: previousRange, owner: owner),
           isUsable(previous) {
            return CGRect(x: previous.maxX, y: previous.minY, width: 1, height: max(1, previous.height))
        }
        return nil
    }

    private func markerBounds(for range: AXTextMarkerRange, owner: AXUIElement) -> CGRect? {
        var raw: CFTypeRef?
        guard AXUIElementCopyParameterizedAttributeValue(
            owner,
            boundsForMarkerRangeAttribute,
            range,
            &raw
        ) == .success,
        let raw else {
            return nil
        }
        if CFGetTypeID(raw) == AXValueGetTypeID() {
            let value = unsafeBitCast(raw, to: AXValue.self)
            var rect = CGRect.zero
            return AXValueGetValue(value, .cgRect, &rect) ? rect : nil
        }
        return (raw as? NSValue)?.rectValue
    }

    private func frame(of element: AXUIElement) -> CGRect? {
        var raw: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            element,
            "AXFrame" as CFString,
            &raw
        ) == .success,
        let raw,
        CFGetTypeID(raw) == AXValueGetTypeID() else {
            return nil
        }
        let value = unsafeBitCast(raw, to: AXValue.self)
        var rect = CGRect.zero
        return AXValueGetValue(value, .cgRect, &rect) ? rect : nil
    }

    private func isUsable(_ rect: CGRect) -> Bool {
        !rect.isNull
            && !rect.isInfinite
            && rect.origin.x.isFinite
            && rect.origin.y.isFinite
            && rect.size.width.isFinite
            && rect.size.height.isFinite
    }

    private func set(_ value: CFTypeRef, attribute: CFString, onAny elements: [AXUIElement]) -> Bool {
        for element in elements where AXUIElementSetAttributeValue(element, attribute, value) == .success {
            return true
        }
        return false
    }

    private func sameElement(_ lhs: AXUIElement, _ rhs: AXUIElement) -> Bool {
        CFEqual(lhs, rhs)
    }

    private func postUnicode(_ string: String) -> Bool {
        let utf16 = Array(string.utf16)
        guard !utf16.isEmpty,
              let source = CGEventSource(stateID: .combinedSessionState),
              let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: true),
              let keyUp = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: false) else {
            return false
        }
        utf16.withUnsafeBufferPointer { buffer in
            keyDown.keyboardSetUnicodeString(stringLength: buffer.count, unicodeString: buffer.baseAddress!)
            keyUp.keyboardSetUnicodeString(stringLength: buffer.count, unicodeString: buffer.baseAddress!)
        }
        keyDown.post(tap: .cghidEventTap)
        keyUp.post(tap: .cghidEventTap)
        return true
    }

    private func axValue(for range: NSRange) -> AXValue? {
        var cfRange = CFRange(location: range.location, length: range.length)
        return AXValueCreate(.cfRange, &cfRange)
    }

    private func copyElementAttribute(_ element: AXUIElement, _ attribute: CFString) -> AXUIElement? {
        var raw: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute, &raw) == .success,
              let raw else { return nil }
        return (raw as! AXUIElement)
    }

    private func isProtected(_ element: AXUIElement) -> Bool {
        var raw: CFTypeRef?
        if AXUIElementCopyAttributeValue(
            element,
            kAXSubroleAttribute as CFString,
            &raw
        ) == .success, let subrole = raw as? String,
           subrole == (kAXSecureTextFieldSubrole as String) {
            return true
        }

        // Chromium-based password controls commonly expose this boolean.
        raw = nil
        if AXUIElementCopyAttributeValue(
            element,
            "AXProtectedContent" as CFString,
            &raw
        ) == .success, let protected = raw as? Bool {
            return protected
        }
        return false
    }
}
