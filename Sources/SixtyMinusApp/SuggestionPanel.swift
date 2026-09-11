import AppKit

private final class SuggestionWindow: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

private final class FirstMouseButton: NSButton {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

private final class VerticallyCenteredTextFieldCell: NSTextFieldCell {
    override func drawingRect(forBounds rect: NSRect) -> NSRect {
        let naturalHeight = ceil(cellSize(forBounds: rect).height)
        guard naturalHeight < rect.height else { return super.drawingRect(forBounds: rect) }

        let centeredRect = NSRect(
            x: rect.minX,
            y: rect.minY + floor((rect.height - naturalHeight) / 2),
            width: rect.width,
            height: naturalHeight
        )
        return super.drawingRect(forBounds: centeredRect)
    }
}

private final class SuggestionRow: NSView {
    var onClick: (() -> Void)?

    private let valueLabel = NSTextField(labelWithString: "")
    private let tabLabel = NSTextField(labelWithString: "⇥")

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.cornerRadius = 5

        valueLabel.cell = VerticallyCenteredTextFieldCell(textCell: "")
        valueLabel.font = .systemFont(ofSize: 13)
        valueLabel.lineBreakMode = .byTruncatingTail
        valueLabel.maximumNumberOfLines = 1
        addSubview(valueLabel)

        tabLabel.cell = VerticallyCenteredTextFieldCell(textCell: "⇥")
        tabLabel.font = .systemFont(ofSize: 13, weight: .medium)
        tabLabel.alignment = .center
        addSubview(tabLabel)

        setAccessibilityRole(.button)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layout() {
        super.layout()
        valueLabel.frame = NSRect(x: 10, y: 0, width: bounds.width - 46, height: bounds.height)
        tabLabel.frame = NSRect(x: bounds.width - 34, y: 0, width: 24, height: bounds.height)
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseDown(with event: NSEvent) {
        onClick?()
    }

    func configure(value: String, selected: Bool) {
        valueLabel.stringValue = value
        tabLabel.isHidden = !selected
        layer?.backgroundColor = selected
            ? NSColor.controlAccentColor.cgColor
            : NSColor.clear.cgColor
        valueLabel.textColor = selected ? .white : .labelColor
        tabLabel.textColor = selected ? .white : .secondaryLabelColor
        setAccessibilityLabel("Replace with \(value)")
        setAccessibilityValue(selected ? "Selected" : nil)
    }
}

/// The original, conventional suggestion menu: a non-activating list with a
/// clearly selected row and a visible Tab hint. It deliberately avoids the
/// native spelling-correction indicator and all modal tracking APIs.
final class SuggestionPanel: NSObject {
    var onAccept: ((String) -> Void)?
    var onDismiss: (() -> Void)?

    private let panel: SuggestionWindow
    private let backgroundView = NSVisualEffectView(frame: .zero)
    private let closeButton = FirstMouseButton(frame: .zero)
    private var rows: [SuggestionRow] = []
    private var choices: [String] = []
    private(set) var selectedIndex = 0
    private var anchorRect = NSRect.zero

    private let rowHeight: CGFloat = 32
    private let outerPadding: CGFloat = 6
    private let closeWidth: CGFloat = 28

    override init() {
        panel = SuggestionWindow(
            contentRect: NSRect(x: 0, y: 0, width: 160, height: 44),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: true
        )
        super.init()

        panel.level = .popUpMenu
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.ignoresMouseEvents = false
        panel.becomesKeyOnlyIfNeeded = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]

        backgroundView.material = .popover
        backgroundView.blendingMode = .behindWindow
        backgroundView.state = .active
        backgroundView.wantsLayer = true
        backgroundView.layer?.cornerRadius = 8
        backgroundView.layer?.masksToBounds = true
        panel.contentView = backgroundView

        closeButton.target = self
        closeButton.action = #selector(closeClicked)
        closeButton.title = "×"
        closeButton.font = .systemFont(ofSize: 15)
        closeButton.isBordered = false
        closeButton.focusRingType = .none
        closeButton.setAccessibilityLabel("Dismiss number correction")
        backgroundView.addSubview(closeButton)
    }

    func show(suggestion: NumberSuggestion, caretBounds: CGRect) {
        choices = [suggestion.replacement] + suggestion.alternatives
        selectedIndex = 0
        anchorRect = normalizedAnchorRect(appKitRect(fromAccessibilityRect: caretBounds))
        rebuildRowsAndPosition()
        panel.orderFrontRegardless()
    }

    func contains(quartzScreenPoint point: CGPoint) -> Bool {
        guard panel.isVisible else { return false }
        return panel.frame.contains(appKitPoint(fromQuartzPoint: point))
    }

    func dismiss() {
        choices = []
        selectedIndex = 0
        rows.forEach { $0.removeFromSuperview() }
        rows = []
        panel.orderOut(nil)
    }

    func moveSelection(by delta: Int) {
        guard choices.count > 1 else { return }
        selectedIndex = (selectedIndex + delta + choices.count) % choices.count
        updateSelection()
    }

    var selectedReplacement: String? {
        choices.indices.contains(selectedIndex) ? choices[selectedIndex] : nil
    }

    private func rebuildRowsAndPosition() {
        rows.forEach { $0.removeFromSuperview() }
        rows = []

        let font = NSFont.systemFont(ofSize: 13)
        let widest = choices.map {
            ($0 as NSString).size(withAttributes: [.font: font]).width
        }.max() ?? 0
        let width = min(360, max(160, ceil(widest) + 82))
        let height = outerPadding * 2 + rowHeight * CGFloat(choices.count)

        backgroundView.frame = NSRect(x: 0, y: 0, width: width, height: height)
        closeButton.frame = NSRect(
            x: width - outerPadding - closeWidth,
            y: height - outerPadding - rowHeight,
            width: closeWidth,
            height: rowHeight
        )

        for index in choices.indices {
            let row = SuggestionRow(frame: NSRect(
                x: outerPadding,
                y: height - outerPadding - rowHeight * CGFloat(index + 1),
                width: width - outerPadding * 2 - (index == 0 ? closeWidth : 0),
                height: rowHeight
            ))
            row.onClick = { [weak self] in self?.acceptChoice(at: index) }
            backgroundView.addSubview(row, positioned: .below, relativeTo: closeButton)
            rows.append(row)
        }

        updateSelection()
        panel.setFrame(positionedFrame(width: width, height: height), display: true)
    }

    private func updateSelection() {
        for index in rows.indices {
            rows[index].configure(value: choices[index], selected: index == selectedIndex)
        }
    }

    private func acceptChoice(at index: Int) {
        guard choices.indices.contains(index) else { return }
        onAccept?(choices[index])
    }

    private func positionedFrame(width: CGFloat, height: CGFloat) -> NSRect {
        var frame = NSRect(
            x: anchorRect.midX - width / 2,
            y: anchorRect.minY - height - 5,
            width: width,
            height: height
        )

        let screen = NSScreen.screens.first(where: { $0.frame.intersects(anchorRect) })
            ?? NSScreen.main
            ?? NSScreen.screens.first
        if let visibleFrame = screen?.visibleFrame {
            if frame.minY < visibleFrame.minY + 6 {
                frame.origin.y = anchorRect.maxY + 5
            }
            frame.origin.x = min(
                max(frame.origin.x, visibleFrame.minX + 6),
                visibleFrame.maxX - frame.width - 6
            )
        }
        return frame
    }

    private func normalizedAnchorRect(_ textRect: NSRect) -> NSRect {
        NSRect(
            x: textRect.minX,
            y: textRect.minY,
            width: max(1, textRect.width),
            height: max(1, textRect.height)
        )
    }

    private func appKitRect(fromAccessibilityRect rect: CGRect) -> NSRect {
        let primaryTop = NSScreen.screens.first?.frame.maxY ?? 0
        return NSRect(
            x: rect.minX,
            y: primaryTop - rect.maxY,
            width: rect.width,
            height: rect.height
        )
    }

    private func appKitPoint(fromQuartzPoint point: CGPoint) -> NSPoint {
        let primaryTop = NSScreen.screens.first?.frame.maxY ?? 0
        return NSPoint(x: point.x, y: primaryTop - point.y)
    }

    @objc private func closeClicked() {
        onDismiss?()
    }
}
