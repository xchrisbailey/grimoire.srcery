#if os(macOS)
import AppKit
import PDFKit
import WebKit

/// Lays an exported HTML page out in a web view and turns it into a paginated PDF, for
/// Export as PDF, Print and sharing. Pages break between blocks where they can, with the
/// title in the header and the page number in the footer.
@MainActor
public final class PagePrinter: NSObject, WKNavigationDelegate {
    private let webView: WKWebView
    private var loaded: CheckedContinuation<Void, Error>?

    /// The paper, in points.
    public var pageSize: CGSize
    public var margin: CGFloat = 54
    /// Shown at the top of every page; empty for no header.
    public var title = ""

    public enum PrintError: LocalizedError {
        case couldNotLoad
        case couldNotSave

        public var errorDescription: String? {
            switch self {
            case .couldNotLoad: String(localized: "The page couldn't be laid out for printing.")
            case .couldNotSave: String(localized: "The PDF couldn't be made.")
            }
        }
    }

    public init(pageSize: CGSize = NSPrintInfo.shared.paperSize) {
        self.pageSize = pageSize.width > 0 ? pageSize : CGSize(width: 612, height: 792)
        webView = WKWebView(frame: NSRect(x: 0, y: 0, width: 600, height: 800))
        super.init()
        webView.navigationDelegate = self
    }

    private var contentSize: CGSize {
        CGSize(width: pageSize.width - margin * 2, height: pageSize.height - margin * 2 - 24)
    }

    /// Loads `html` laid out at the page's text width, and waits for it to finish.
    public func load(_ html: String) async throws {
        webView.frame = NSRect(x: 0, y: 0, width: contentSize.width, height: contentSize.height)
        try await withCheckedThrowingContinuation { continuation in
            loaded = continuation
            webView.loadHTMLString(html, baseURL: nil)
        }
    }

    // MARK: - PDF

    /// The loaded page as a PDF, one sheet of paper per page.
    public func pdf() async throws -> Data {
        let layout = try await pageLayout()
        let breaks = Self.pageBreaks(height: layout.height, blockTops: layout.tops, pageHeight: contentSize.height)
        let output = NSMutableData()
        var mediaBox = CGRect(origin: .zero, size: pageSize)
        guard let consumer = CGDataConsumer(data: output as CFMutableData),
            let context = CGContext(consumer: consumer, mediaBox: &mediaBox, nil)
        else { throw PrintError.couldNotSave }
        for (number, slice) in breaks.enumerated() {
            let configuration = WKPDFConfiguration()
            configuration.rect = CGRect(
                x: 0, y: slice.lowerBound, width: contentSize.width, height: slice.upperBound - slice.lowerBound)
            let data = try await webView.pdf(configuration: configuration)
            guard let provider = CGDataProvider(data: data as CFData), let document = CGPDFDocument(provider),
                let page = document.page(at: 1)
            else { throw PrintError.couldNotSave }
            context.beginPDFPage(nil)
            let box = page.getBoxRect(.mediaBox)
            // Top-align the slice inside the margins.
            context.saveGState()
            context.translateBy(x: margin, y: pageSize.height - margin - 24 - box.height)
            context.drawPDFPage(page)
            context.restoreGState()
            drawChrome(in: context, page: number + 1, of: breaks.count)
            context.endPDFPage()
        }
        context.closePDF()
        return output as Data
    }

    public func savePDF(to url: URL) async throws {
        try await pdf().write(to: url, options: .atomic)
    }

    /// Shows the print panel for the loaded page, as a sheet on `parent`.
    public func print(attachedTo parent: NSWindow?, jobTitle: String) async throws {
        guard let document = PDFDocument(data: try await pdf()) else { throw PrintError.couldNotSave }
        let info = (NSPrintInfo.shared.copy() as? NSPrintInfo) ?? NSPrintInfo()
        info.topMargin = 0
        info.bottomMargin = 0
        info.leftMargin = 0
        info.rightMargin = 0
        guard let operation = document.printOperation(for: info, scalingMode: .pageScaleDownToFit, autoRotate: true)
        else { throw PrintError.couldNotSave }
        operation.jobTitle = jobTitle
        operation.showsPrintPanel = true
        operation.showsProgressPanel = true
        retained = document
        if let parent {
            operation.runModal(for: parent, delegate: nil, didRun: nil, contextInfo: nil)
        } else {
            operation.run()
        }
    }

    /// Keeps the document alive while a print sheet is up.
    private var retained: PDFDocument?

    // MARK: - Layout

    private struct Layout {
        var height: CGFloat
        var tops: [CGFloat]
    }

    /// The page's height and where each block starts, so pages can break between blocks.
    private func pageLayout() async throws -> Layout {
        let script = """
            (() => {
              const tops = [];
              const walk = (element) => {
                for (const child of element.children) {
                  tops.push(child.getBoundingClientRect().top + window.scrollY);
                  if (['UL', 'OL', 'TABLE', 'TBODY', 'THEAD', 'BLOCKQUOTE'].includes(child.tagName)) walk(child);
                }
              };
              walk(document.querySelector('main'));
              return [document.documentElement.scrollHeight].concat(tops);
            })()
            """
        let result = try await webView.evaluateJavaScript(script)
        let numbers = (result as? [NSNumber])?.map { CGFloat($0.doubleValue) } ?? []
        guard let height = numbers.first else { throw PrintError.couldNotLoad }
        return Layout(height: height, tops: Array(numbers.dropFirst()))
    }

    /// Where each page starts and ends: at the last block start that fits, unless that
    /// would leave the page less than half full, in which case the page is cut at its foot.
    static func pageBreaks(height: CGFloat, blockTops: [CGFloat], pageHeight: CGFloat) -> [Range<CGFloat>] {
        guard height > 0, pageHeight > 0 else { return [0..<max(1, height)] }
        let tops = blockTops.sorted()
        var pages: [Range<CGFloat>] = []
        var start: CGFloat = 0
        while start < height - 1 {
            let limit = start + pageHeight
            if limit >= height {
                pages.append(start..<height)
                break
            }
            let candidate = tops.last { $0 > start + pageHeight / 2 && $0 <= limit }
            let end = candidate ?? limit
            pages.append(start..<end)
            start = end
        }
        return pages
    }

    private func drawChrome(in context: CGContext, page: Int, of count: Int) {
        let font = BrandFont.ctFont(.metadata, size: 9)
        let color = NSColor(white: 0.45, alpha: 1)
        func draw(_ text: String, at point: CGPoint, alignRight: Bool = false) {
            let attributed = NSAttributedString(string: text, attributes: [.font: font, .foregroundColor: color])
            let line = CTLineCreateWithAttributedString(attributed)
            let width = CTLineGetTypographicBounds(line, nil, nil, nil)
            context.textPosition = CGPoint(x: alignRight ? point.x - width : point.x, y: point.y)
            CTLineDraw(line, context)
        }
        if !title.isEmpty { draw(title, at: CGPoint(x: margin, y: pageSize.height - margin + 12)) }
        draw("\(page) / \(count)", at: CGPoint(x: pageSize.width - margin, y: margin - 24), alignRight: true)
    }

    // MARK: - Navigation

    public func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        loaded?.resume()
        loaded = nil
    }

    public func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        loaded?.resume(throwing: PrintError.couldNotLoad)
        loaded = nil
    }

    public func webView(
        _ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error
    ) {
        loaded?.resume(throwing: PrintError.couldNotLoad)
        loaded = nil
    }
}
#endif
