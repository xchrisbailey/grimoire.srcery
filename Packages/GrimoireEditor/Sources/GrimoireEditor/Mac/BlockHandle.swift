#if os(macOS)
import AppKit
import GrimoireCore

/// The ⋮⋮ handle that appears in the left margin beside the block under the mouse. Drag
/// it to move the block; click it for the block menu.
@MainActor
final class BlockHandle: NSObject {
    private weak var controller: EditorController?
    private let handle = HandleView()
    private let dropLine = NSView()
    /// The block the handle sits beside.
    private var block: Int?

    init(controller: EditorController) {
        self.controller = controller
        super.init()
        handle.isHidden = true
        handle.onMouseDown = { [weak self] event in self?.mouseDown(event) }
        dropLine.wantsLayer = true
        dropLine.layer?.cornerRadius = 1
        applyTheme(controller.styler.theme)
        dropLine.isHidden = true
        controller.textView.addSubview(handle)
        controller.textView.addSubview(dropLine)
    }

    var textView: MarkdownTextView? { controller?.textView }

    func applyTheme(_ theme: EditorTheme) {
        handle.tint = theme.marker
        handle.hoverFill = theme.codeBackground
        handle.needsDisplay = true
        dropLine.layer?.backgroundColor = theme.magic.cgColor
    }

    // MARK: - Hover

    func mouseMoved(to point: CGPoint) {
        guard let target = blockFrame(at: point) else {
            if !handle.isTracking { hide() }
            return
        }
        block = target.block
        let size = HandleView.size
        handle.frame = CGRect(
            x: target.firstLine.minX - size.width - 6, y: target.firstLine.midY - size.height / 2, width: size.width,
            height: size.height)
        handle.isHidden = false
    }

    func hide() {
        handle.isHidden = true
        block = nil
    }

    /// The block whose text is beside `point`, if any.
    func block(at point: CGPoint) -> Int? {
        blockFrame(at: point)?.block
    }

    /// The block whose text is beside `point`, with its first line's frame in view
    /// coordinates. Blank lines between blocks have none.
    private func blockFrame(at point: CGPoint) -> (block: Int, firstLine: CGRect)? {
        guard let controller, let textView, let layoutManager = textView.textLayoutManager,
            let storage = textView.textContentStorage
        else { return nil }
        let origin = textView.textContainerOrigin
        let containerPoint = CGPoint(x: textView.textContainerOrigin.x + 10, y: point.y - origin.y)
        guard let fragment = layoutManager.textLayoutFragment(for: CGPoint(x: 10, y: containerPoint.y)),
            let range = fragment.textElement?.elementRange
        else { return nil }
        let offset = storage.offset(from: storage.documentRange.location, to: range.location)
        let index = controller.index
        guard let position = index.blockIndex(at: offset), offset <= index.sourceRange(of: position).upperBound
        else { return nil }
        return (position, firstLineFrame(of: position) ?? .zero)
    }

    /// The first line of block `position`, in the text view's coordinates.
    func firstLineFrame(of position: Int) -> CGRect? {
        guard let controller, let textView, let layoutManager = textView.textLayoutManager,
            let storage = textView.textContentStorage,
            let location = storage.location(
                storage.documentRange.location, offsetBy: controller.index.sourceRange(of: position).lowerBound),
            let fragment = layoutManager.textLayoutFragment(for: location)
        else { return nil }
        let origin = textView.textContainerOrigin
        let padding = textView.textContainer?.lineFragmentPadding ?? 5
        let line = fragment.textLineFragments.first?.typographicBounds ?? .zero
        let frame = fragment.layoutFragmentFrame
        return CGRect(
            x: origin.x + padding, y: origin.y + frame.minY + line.minY, width: frame.width,
            height: max(line.height, 18))
    }

    // MARK: - Click and drag

    private func mouseDown(_ event: NSEvent) {
        guard let source = block, let textView, let window = textView.window else { return }
        let start = event.locationInWindow
        var destination: Int?
        handle.isTracking = true
        defer {
            handle.isTracking = false
            dropLine.isHidden = true
        }
        while let next = window.nextEvent(matching: [.leftMouseDragged, .leftMouseUp]) {
            if next.type == .leftMouseUp { break }
            let location = next.locationInWindow
            guard destination != nil || hypot(location.x - start.x, location.y - start.y) > 4 else { continue }
            let point = textView.convert(location, from: nil)
            textView.autoscroll(with: next)
            destination = dropTarget(at: point, source: source)
        }
        if let destination {
            if destination != source { controller?.moveBlock(source, to: destination) }
        } else {
            showMenu(for: source, with: event)
        }
    }

    /// Where a block dragged to `point` lands, and shows the line marking it.
    private func dropTarget(at point: CGPoint, source: Int) -> Int? {
        guard let target = blockFrame(at: point)?.block ?? nearestBlock(to: point) else { return nil }
        guard let frame = firstLineFrame(of: target) else { return nil }
        let y: CGFloat
        if target > source,
            let next = target + 1 < (controller?.index.blocks.count ?? 0) ? firstLineFrame(of: target + 1) : nil
        {
            y = next.minY - 4
        } else if target > source {
            y = (textView?.bounds.height ?? frame.maxY) - (textView?.textContainerInset.height ?? 0)
        } else {
            y = frame.minY - 4
        }
        dropLine.frame = CGRect(x: frame.minX, y: y, width: min(frame.width, 680), height: 2)
        dropLine.isHidden = target == source
        return target
    }

    private func nearestBlock(to point: CGPoint) -> Int? {
        guard let count = controller?.index.blocks.count, count > 0 else { return nil }
        if let first = firstLineFrame(of: 0), point.y < first.minY { return 0 }
        return count - 1
    }

    // MARK: - Menu

    private func showMenu(for position: Int, with event: NSEvent) {
        let menu = NSMenu()
        let turnInto = NSMenuItem(title: String(localized: "Turn Into"), action: nil, keyEquivalent: "")
        let submenu = NSMenu()
        for (title, kind) in Self.kinds {
            submenu.addItem(item(title) { [weak self] in self?.controller?.convertBlock(position, to: kind) })
        }
        turnInto.submenu = submenu
        menu.addItem(turnInto)
        menu.addItem(item(String(localized: "Duplicate")) { [weak self] in self?.controller?.duplicateBlock(position) })
        menu.addItem(item(String(localized: "Copy Link")) { [weak self] in self?.copyLink(to: position) })
        menu.addItem(.separator())
        menu.addItem(item(String(localized: "Delete")) { [weak self] in self?.controller?.deleteBlock(position) })
        NSMenu.popUpContextMenu(menu, with: event, for: handle)
    }

    static let kinds: [(String, BlockKind)] = [
        (String(localized: "Text"), .paragraph),
        (String(localized: "Heading 1"), .heading(level: 1)),
        (String(localized: "Heading 2"), .heading(level: 2)),
        (String(localized: "Heading 3"), .heading(level: 3)),
        (String(localized: "Bulleted List"), .listItem(.bullet)),
        (String(localized: "Numbered List"), .listItem(.ordered())),
        (String(localized: "To-do"), .listItem(.task)),
        (String(localized: "Quote"), .blockquote),
        (String(localized: "Code Block"), .codeBlock(language: nil)),
    ]

    private func item(_ title: String, action: @escaping () -> Void) -> NSMenuItem {
        MenuClosure.item(title, action)
    }

    /// Puts a markdown link to the block on the pasteboard: `[Heading](file.md#heading)` for
    /// headings, a link to the file otherwise.
    private func copyLink(to position: Int) {
        guard let controller, let fileURL = controller.fileURL else { return }
        let block = controller.index.blocks[position]
        let file =
            fileURL.lastPathComponent.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed)
            ?? fileURL.lastPathComponent
        let link: String
        if case .heading = block.kind {
            link = "[\(block.text)](\(file)#\(Self.slug(block.text)))"
        } else {
            link = "[\(fileURL.deletingPathExtension().lastPathComponent)](\(file))"
        }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(link, forType: .string)
    }

    /// GitHub's heading anchors: lowercased, punctuation dropped, spaces as hyphens.
    static func slug(_ heading: String) -> String {
        heading.lowercased()
            .filter { $0.isLetter || $0.isNumber || $0 == " " || $0 == "-" || $0 == "_" }
            .replacingOccurrences(of: " ", with: "-")
    }
}

/// The ⋮⋮ grip itself.
private final class HandleView: NSView {
    static let size = CGSize(width: 18, height: 22)
    var tint: NSColor = .tertiaryLabelColor
    var hoverFill: NSColor = .quaternaryLabelColor
    var onMouseDown: ((NSEvent) -> Void)?
    var isTracking = false
    private var isHovered = false {
        didSet { needsDisplay = true }
    }

    override var isFlipped: Bool { true }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(
            NSTrackingArea(
                rect: bounds, options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect], owner: self))
    }

    override func mouseEntered(with event: NSEvent) { isHovered = true }
    override func mouseExited(with event: NSEvent) { isHovered = false }
    override func mouseDown(with event: NSEvent) { onMouseDown?(event) }
    override func resetCursorRects() { addCursorRect(bounds, cursor: .openHand) }

    override func draw(_ dirtyRect: NSRect) {
        if isHovered || isTracking {
            hoverFill.setFill()
            NSBezierPath(roundedRect: bounds, xRadius: 5, yRadius: 5).fill()
        }
        tint.setFill()
        // Two columns of three dots.
        for column in 0..<2 {
            for row in 0..<3 {
                let dot = CGRect(
                    x: bounds.midX - 3.5 + CGFloat(column) * 5, y: bounds.midY - 6.5 + CGFloat(row) * 5, width: 2.4,
                    height: 2.4)
                NSBezierPath(ovalIn: dot).fill()
            }
        }
    }
}
#endif
