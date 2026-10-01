import CoreGraphics
import Foundation

#if os(macOS)
import AppKit
#else
import UIKit
#endif

/// A layout fragment (one line of source) that draws its `LineDecoration` around the
/// text: code backgrounds, quote bars, rules, bullets, checkboxes and image previews.
public final class MarkdownLayoutFragment: NSTextLayoutFragment {
    let decoration: LineDecoration
    let theme: EditorTheme

    init(textElement: NSTextElement, range: NSTextRange?, decoration: LineDecoration, theme: EditorTheme) {
        self.decoration = decoration
        self.theme = theme
        super.init(textElement: textElement, range: range)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    /// The decoration for a paragraph, if its first character carries one.
    static func decoration(of element: NSTextElement) -> LineDecoration? {
        guard let paragraph = element as? NSTextParagraph, paragraph.attributedString.length > 0 else { return nil }
        return paragraph.attributedString.attribute(.grimoireDecoration, at: 0, effectiveRange: nil) as? LineDecoration
    }

    /// Room to draw past the text: full-width code backgrounds, and the image preview
    /// below an image line.
    public override var renderingSurfaceBounds: CGRect {
        var bounds = super.renderingSurfaceBounds
        let frame = layoutFragmentFrame
        switch decoration.kind {
        case .code, .rule, .quote:
            bounds = bounds.union(CGRect(x: -frame.minX, y: 0, width: containerWidth, height: frame.height))
        case .image(_, let size):
            bounds = bounds.union(
                CGRect(
                    x: -frame.minX, y: 0, width: max(size.width + 10, frame.width),
                    height: frame.height + size.height + 16))
        case .tableRow(let edges, _, _):
            bounds = bounds.union(
                CGRect(x: -frame.minX, y: 0, width: frame.minX + (edges.last ?? 0) + 12, height: frame.height))
        case .tableDelimiter:
            break
        case .bullet, .task:
            // Drawn in the indent, left of where the fragment's text starts.
            bounds = bounds.union(CGRect(x: -frame.minX, y: 0, width: frame.width + frame.minX, height: frame.height))
        }
        return bounds
    }

    private var containerWidth: CGFloat {
        textLayoutManager?.textContainer?.size.width ?? layoutFragmentFrame.width
    }

    /// Where the middle of the first line's capital letters sits, for centering bullets
    /// and checkboxes on the text.
    var firstLineCenterY: CGFloat {
        guard let line = textLineFragments.first else { return layoutFragmentFrame.height / 2 }
        let baseline = line.typographicBounds.minY + line.glyphOrigin.y
        return baseline - theme.body.capHeight / 2
    }

    public override func draw(at point: CGPoint, in context: CGContext) {
        context.saveGState()
        drawDecoration(at: point, in: context)
        context.restoreGState()
        super.draw(at: point, in: context)
        if case .image(let url, let size) = decoration.kind {
            drawImage(url: url, size: size, at: point, in: context)
        }
    }

    private func drawDecoration(at point: CGPoint, in context: CGContext) {
        let frame = layoutFragmentFrame
        let padding = textLayoutManager?.textContainer?.lineFragmentPadding ?? 5
        // Where the text container's column starts, in the context's coordinates.
        let columnX = point.x - frame.minX + padding
        switch decoration.kind {
        case .code(let position):
            let rect = CGRect(x: columnX, y: point.y, width: containerWidth - padding * 2, height: frame.height)
            drawCodeBackground(rect, position: position, in: context)
        case .quote:
            context.setFillColor(theme.magic.withAlphaComponent(0.7).cgColor)
            context.fill(CGRect(x: columnX + 2, y: point.y, width: 3, height: frame.height))
        case .rule:
            let y = point.y + frame.height / 2
            context.setStrokeColor(theme.surface.cgColor)
            context.setLineWidth(1)
            context.move(to: CGPoint(x: columnX, y: y))
            context.addLine(to: CGPoint(x: columnX + containerWidth - padding * 2, y: y))
            context.strokePath()
        case .bullet(let indent):
            let diameter: CGFloat = 5.5
            let center = CGPoint(
                x: columnX + indent + LineDecoration.bulletWidth / 2 - 3, y: point.y + firstLineCenterY)
            context.setFillColor((theme.token(.listMarker, raw: false).color ?? theme.caret).cgColor)
            context.fillEllipse(
                in: CGRect(x: center.x - diameter / 2, y: center.y - diameter / 2, width: diameter, height: diameter))
        case .task(let checked, let indent):
            let size = LineDecoration.checkboxSize
            let box = CGRect(
                x: columnX + indent, y: point.y + firstLineCenterY - size / 2, width: size, height: size)
            drawCheckbox(box, checked: checked, in: context)
        case .tableRow(let edges, let isHeader, let isLast):
            let row = CGRect(x: columnX, y: point.y, width: edges.last ?? 0, height: frame.height)
            drawTableRow(row, edges: edges, isHeader: isHeader, isLast: isLast, in: context)
        case .image, .tableDelimiter:
            break
        }
    }

    private func drawCodeBackground(_ rect: CGRect, position: LineDecoration.Position, in context: CGContext) {
        let radius: CGFloat = 8
        let path = CGMutablePath()
        path.addRoundedRect(in: rect, cornerWidth: radius, cornerHeight: radius)
        // Square off the corners that join the neighboring lines.
        switch position {
        case .only: break
        case .middle: path.addRect(rect)
        case .first: path.addRect(CGRect(x: rect.minX, y: rect.midY, width: rect.width, height: rect.height / 2))
        case .last: path.addRect(CGRect(x: rect.minX, y: rect.minY, width: rect.width, height: rect.height / 2))
        }
        context.addPath(path)
        let fill = theme.token(.codeBlock, raw: false).background ?? theme.codeBackground
        context.setFillColor(fill.withAlphaComponent(0.55).cgColor)
        context.fillPath()
    }

    /// One row of the grid: header shading, the line under the row, column edges, and the
    /// outer border's sides (its top on the header, its bottom on the last row).
    private func drawTableRow(_ rect: CGRect, edges: [CGFloat], isHeader: Bool, isLast: Bool, in context: CGContext) {
        let (x, y, width, height) = (rect.minX, rect.minY, rect.width, rect.height)
        let radius: CGFloat = 6
        let outline = CGMutablePath()
        outline.addRoundedRect(in: rect, cornerWidth: radius, cornerHeight: radius)
        if !isHeader { outline.addRect(CGRect(x: rect.minX, y: rect.minY, width: rect.width, height: rect.height / 2)) }
        if !isLast { outline.addRect(CGRect(x: rect.minX, y: rect.midY, width: rect.width, height: rect.height / 2)) }
        if isHeader {
            context.addPath(outline)
            context.setFillColor(theme.codeBackground.withAlphaComponent(0.5).cgColor)
            context.fillPath()
        }
        context.setStrokeColor(theme.surface.cgColor)
        context.setLineWidth(1)
        // Column edges, including the outer sides.
        for edge in edges {
            let lineX = (x + edge).rounded() + 0.5
            context.move(to: CGPoint(x: lineX, y: y))
            context.addLine(to: CGPoint(x: lineX, y: y + height))
        }
        context.move(to: CGPoint(x: x, y: y + 0.5))
        context.addLine(to: CGPoint(x: x + width, y: y + 0.5))
        if isLast {
            context.move(to: CGPoint(x: x, y: y + height - 0.5))
            context.addLine(to: CGPoint(x: x + width, y: y + height - 0.5))
        }
        context.strokePath()
    }

    private func drawCheckbox(_ box: CGRect, checked: Bool, in context: CGContext) {
        context.addPath(CGPath(roundedRect: box, cornerWidth: 4, cornerHeight: 4, transform: nil))
        guard checked else {
            context.setStrokeColor(theme.marker.cgColor)
            context.setLineWidth(1.5)
            context.strokePath()
            return
        }
        context.setFillColor(theme.magic.cgColor)
        context.fillPath()
        context.setStrokeColor(theme.page.cgColor)
        context.setLineWidth(2)
        context.setLineCap(.round)
        context.setLineJoin(.round)
        context.move(to: CGPoint(x: box.minX + 3.5, y: box.midY))
        context.addLine(to: CGPoint(x: box.minX + 6.5, y: box.maxY - 4))
        context.addLine(to: CGPoint(x: box.maxX - 3.5, y: box.minY + 4))
        context.strokePath()
    }

    private func drawImage(url: URL, size: CGSize, at point: CGPoint, in context: CGContext) {
        let image = MainActor.assumeIsolated { ImageCache.shared.image(for: url) }
        guard let image else { return }
        let padding = textLayoutManager?.textContainer?.lineFragmentPadding ?? 5
        let origin = CGPoint(
            x: point.x - layoutFragmentFrame.minX + padding,
            y: point.y + (textLineFragments.last?.typographicBounds.maxY ?? 0)
                + LineDecoration.imageGap)
        let rect = CGRect(origin: origin, size: size)
        context.saveGState()
        context.addPath(CGPath(roundedRect: rect, cornerWidth: 8, cornerHeight: 8, transform: nil))
        context.clip()
        // Core Graphics draws images bottom-up; the text view's context is flipped.
        context.translateBy(x: rect.minX, y: rect.maxY)
        context.scaleBy(x: 1, y: -1)
        context.draw(image, in: CGRect(origin: .zero, size: size))
        context.restoreGState()
    }
}
