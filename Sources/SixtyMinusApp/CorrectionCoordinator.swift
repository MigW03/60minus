import AppKit
import CoreGraphics
import Foundation

final class CorrectionCoordinator: EventTapDelegate {
    private struct VisibleSuggestion {
        let suggestion: NumberSuggestion
        let snapshot: TextSnapshot
    }

    private let accessibility = AccessibilityClient()
    private let scanner = ContextScanner()
    private let panel = SuggestionPanel()
    private let worker = DispatchQueue(label: "com.sixtyminus.accessibility", qos: .userInteractive)

    private var visible: VisibleSuggestion?
    private var editingExistingText = false
    private var scanGeneration = 0
    private var pendingScan: DispatchWorkItem?
    private var suppressedSuggestion: VisibleSuggestion?

    var isPaused = false {
        didSet {
            if isPaused { dismiss() }
        }
    }

    init() {
        panel.onAccept = { [weak self] replacement in
            self?.accept(replacement: replacement)
        }
        panel.onDismiss = { [weak self] in
            self?.dismiss(suppressCurrent: true)
        }
    }

    func eventTap(_ tap: EventTap, received input: KeyboardInput) -> Bool {
        guard !isPaused else { return false }
        if visible != nil {
            if !input.hasCommandModifier, !input.hasControlModifier, !input.hasOptionModifier {
                switch input.keyCode {
                case 48: // Tab
                    let replacement = panel.selectedReplacement
                    DispatchQueue.main.async { [weak self] in
                        if let replacement { self?.accept(replacement: replacement) }
                    }
                    return true
                case 53: // Escape
                    DispatchQueue.main.async { [weak self] in
                        self?.dismiss(suppressCurrent: true)
                    }
                    return true
                case 126: // Up
                    DispatchQueue.main.async { [weak self] in self?.panel.moveSelection(by: -1) }
                    return true
                case 125: // Down
                    DispatchQueue.main.async { [weak self] in self?.panel.moveSelection(by: 1) }
                    return true
                default:
                    break
                }
            }

            // Every non-navigation input goes directly to the real app. Hiding
            // the panel here can never invoke acceptance.
            dismiss(suppressCurrent: true)
        }

        if input.hasCommandModifier || input.hasControlModifier || input.hasOptionModifier {
            suppressedSuggestion = nil
            editingExistingText = true
            cancelPendingScan()
            return false
        }

        if isEditingKey(input.keyCode) {
            if input.keyCode == 51 || input.keyCode == 117 {
                suppressedSuggestion = nil
            }
            editingExistingText = true
            cancelPendingScan()
            return false
        }

        guard !input.isRepeat, !input.text.isEmpty else { return false }
        if isBoundary(input.text) {
            editingExistingText = false
            scheduleScan(reason: .boundary, after: 0.010)
        } else if editingExistingText {
            suppressedSuggestion = nil
            // An in-place edit may already have a separator to its right, so
            // it might never produce another boundary key. This edit-only
            // settle catches `tee` -> `three` without delaying normal typing.
            scheduleScan(reason: .editedTextSettled, after: 0.085)
        } else if pendingScan != nil {
            // Do not let a retry from a previous boundary inspect text the user
            // has already continued typing.
            cancelPendingScan()
        }
        return false
    }

    func eventTapReceivedMouseDown(_ tap: EventTap, at quartzLocation: CGPoint) {
        if panel.contains(quartzScreenPoint: quartzLocation) { return }
        dismiss(suppressCurrent: true)
        editingExistingText = true
        cancelPendingScan()
    }

    func applicationChanged() {
        dismiss()
        suppressedSuggestion = nil
        editingExistingText = false
        cancelPendingScan()
    }

    private func scheduleScan(reason: ScanReason, after delay: TimeInterval) {
        cancelPendingScan()
        scanGeneration += 1
        let generation = scanGeneration
        scheduleScanAttempt(reason: reason, after: delay, generation: generation, attempt: 0)
    }

    private func scheduleScanAttempt(
        reason: ScanReason,
        after delay: TimeInterval,
        generation: Int,
        attempt: Int
    ) {
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.worker.async { [weak self] in
                guard let self else { return }
                let snapshot = self.accessibility.focusedSnapshot()
                let suggestion = snapshot.flatMap { self.scanner.suggestion(from: $0, reason: reason) }
                let bounds = snapshot.flatMap { snapshot in
                    suggestion.flatMap { self.accessibility.textBounds(for: $0, in: snapshot) }
                }
                DispatchQueue.main.async { [weak self] in
                    guard let self, generation == self.scanGeneration else { return }
                    self.pendingScan = nil
                    guard let snapshot, let suggestion, let bounds else {
                        if attempt < 2 {
                            // Web-based editors can publish their updated
                            // accessibility tree a frame or two after the key event.
                            self.scheduleScanAttempt(
                                reason: reason,
                                after: attempt == 0 ? 0.045 : 0.090,
                                generation: generation,
                                attempt: attempt + 1
                            )
                            return
                        }
                        self.dismiss()
                        return
                    }
                    if self.isSuppressed(suggestion, in: snapshot) {
                        self.visible = nil
                        self.panel.dismiss()
                        return
                    }
                    self.suppressedSuggestion = nil
                    self.visible = VisibleSuggestion(suggestion: suggestion, snapshot: snapshot)
                    self.panel.show(suggestion: suggestion, caretBounds: bounds)
                }
            }
        }
        pendingScan = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    private func accept(replacement: String) {
        guard let visible else { return }
        suppressedSuggestion = nil
        dismiss()

        worker.async { [accessibility] in
            _ = accessibility.replace(
                visible.suggestion,
                in: visible.snapshot,
                with: replacement
            )
        }
    }

    private func dismiss(suppressCurrent: Bool = false) {
        if suppressCurrent, let visible {
            suppressedSuggestion = visible
        }
        visible = nil
        panel.dismiss()
    }

    private func isSuppressed(_ suggestion: NumberSuggestion, in snapshot: TextSnapshot) -> Bool {
        guard let suppressedSuggestion else { return false }
        return snapshot.processIdentifier == suppressedSuggestion.snapshot.processIdentifier
            && CFEqual(snapshot.element, suppressedSuggestion.snapshot.element)
            && suggestion.range == suppressedSuggestion.suggestion.range
            && suggestion.originalText == suppressedSuggestion.suggestion.originalText
    }

    private func cancelPendingScan() {
        pendingScan?.cancel()
        pendingScan = nil
        scanGeneration += 1
    }

    private func isBoundary(_ text: String) -> Bool {
        text.unicodeScalars.contains {
            CharacterSet.whitespacesAndNewlines
                .union(.punctuationCharacters)
                .contains($0)
        }
    }

    private func isEditingKey(_ keyCode: Int64) -> Bool {
        switch keyCode {
        case 51, 117, 115, 116, 119, 121, 123, 124, 125, 126:
            return true
        default:
            return false
        }
    }
}
