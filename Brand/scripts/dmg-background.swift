// Writes Brand/dmg-background.tiff, the artwork behind the release DMG's Finder window:
// the Mocha base, the mark and wordmark, and an arrow from the app to Applications.
// It is a two-representation TIFF (1x and 2x), so the window is sharp on Retina and
// non-Retina displays. The window and icon geometry come from Brand/dmg-layout.json,
// which scripts/dmg-layout.py reads too, so the arrow lands between the icons.
// Run from the repo root: swift Brand/scripts/dmg-background.swift
import AppKit
import CoreText
import Foundation

let mocha = (
    base: NSColor(srgbRed: 0x1e / 255, green: 0x1e / 255, blue: 0x2e / 255, alpha: 1),
    mantle: NSColor(srgbRed: 0x18 / 255, green: 0x18 / 255, blue: 0x25 / 255, alpha: 1),
    surface2: NSColor(srgbRed: 0x58 / 255, green: 0x5b / 255, blue: 0x70 / 255, alpha: 1),
    subtext: NSColor(srgbRed: 0xa6 / 255, green: 0xad / 255, blue: 0xc8 / 255, alpha: 1),
    mauve: NSColor(srgbRed: 0xcb / 255, green: 0xa6 / 255, blue: 0xf7 / 255, alpha: 1),
    ink: NSColor(srgbRed: 0xcd / 255, green: 0xd6 / 255, blue: 0xf4 / 255, alpha: 1)
)

let layout = try JSONSerialization.jsonObject(
    with: Data(contentsOf: URL(fileURLWithPath: "Brand/dmg-layout.json"))) as! [String: Any]
let window = layout["window"] as! [String: Int]
let icons = layout["icons"] as! [String: [Double]]
let width = Double(window["width"]!)
let height = Double(window["height"]!)
let app = icons["Grimoire.app"]!
let applications = icons["Applications"]!
let labels = layout["labels"] as! [String: String]
let iconSize = layout["iconSize"] as! Double
let textSize = layout["textSize"] as! Double

func svg(_ name: String) -> NSImage {
    NSImage(contentsOf: URL(fileURLWithPath: "Brand/\(name).svg"))!
}

func caption(_ text: String, size: CGFloat) -> NSAttributedString {
    let url = URL(fileURLWithPath: "Resources/Fonts/Geist.ttf") as CFURL
    let descriptor = (CTFontManagerCreateFontDescriptorsFromURL(url) as! [CTFontDescriptor])[0]
    let wght = 0x7767_6874  // 'wght'
    let varied = CTFontDescriptorCreateCopyWithAttributes(
        descriptor, [kCTFontVariationAttribute: [wght: 500]] as CFDictionary)
    let font = CTFontCreateWithFontDescriptor(varied, size, nil) as NSFont
    return NSAttributedString(
        string: text, attributes: [.font: font, .foregroundColor: mocha.subtext, .kern: 0.2])
}

// Draws the artwork with a top-left origin, in points.
func draw(in ctx: CGContext) {
    ctx.setFillColor(mocha.base.cgColor)
    ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
    ctx.translateBy(x: 0, y: height)
    ctx.scaleBy(x: 1, y: -1)

    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: true)
    NSGraphicsContext.current?.imageInterpolation = .high

    // A soft lift behind the mark, from the base to the mantle at the edges.
    let glow = NSGradient(colors: [mocha.mauve.withAlphaComponent(0.10), mocha.base.withAlphaComponent(0)])!
    glow.draw(fromCenter: CGPoint(x: width / 2, y: 98), radius: 0,
              toCenter: CGPoint(x: width / 2, y: 98), radius: 150, options: [])

    let mark = svg("mark-dark")
    mark.draw(
        in: NSRect(x: width / 2 - 52, y: 40, width: 104, height: 104), from: .zero,
        operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)

    let wordmark = svg("wordmark-dark")
    let wordmarkWidth = 132.0
    wordmark.draw(
        in: NSRect(
            x: width / 2 - wordmarkWidth / 2, y: 150, width: wordmarkWidth,
            height: wordmarkWidth * 145 / 464),
        from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)

    let hint = caption("Drag Grimoire into Applications", size: 13)
    let hintSize = hint.size()
    hint.draw(at: NSPoint(x: (width - hintSize.width) / 2, y: 206))

    // The arrow runs between the two icons, level with their centres.
    let y = app[1] - 8
    let startX = app[0] + iconSize / 2 + 22
    let endX = applications[0] - iconSize / 2 - 22
    let arrow = NSBezierPath()
    arrow.move(to: NSPoint(x: startX, y: y))
    arrow.line(to: NSPoint(x: endX, y: y))
    arrow.move(to: NSPoint(x: endX - 11, y: y - 11))
    arrow.line(to: NSPoint(x: endX, y: y))
    arrow.line(to: NSPoint(x: endX - 11, y: y + 11))
    arrow.lineWidth = 3
    arrow.lineCapStyle = .round
    arrow.lineJoinStyle = .round
    mocha.surface2.setStroke()
    arrow.stroke()

    // Finder draws icon labels in black whatever sits behind them, which a Mocha base would
    // swallow, so each label gets a light plate. The plate is as wide as the label at the
    // system font and sits where Finder puts the label: just under the icon.
    let labelFont = NSFont.systemFont(ofSize: textSize)
    for (name, text) in labels {
        guard let place = icons[name] else { continue }
        let textWidth = (text as NSString).size(withAttributes: [.font: labelFont]).width
        let plate = NSRect(
            x: place[0] - (textWidth + 14) / 2, y: place[1] + iconSize / 2 + 5,
            width: textWidth + 14, height: textSize + 8)
        mocha.ink.setFill()
        NSBezierPath(roundedRect: plate, xRadius: 6, yRadius: 6).fill()
    }

    NSGraphicsContext.restoreGraphicsState()
}

func render(scale: Int) -> Data {
    let pixelsWide = Int(width) * scale
    let pixelsHigh = Int(height) * scale
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: pixelsWide, pixelsHigh: pixelsHigh, bitsPerSample: 8,
        samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
        bytesPerRow: 0, bitsPerPixel: 0)!
    // Setting the size in points makes the 2x image 144 dpi, which tiffutil pairs by, and
    // makes the graphics context scale drawing in points up to its pixels.
    rep.size = NSSize(width: width, height: height)
    let ctx = NSGraphicsContext(bitmapImageRep: rep)!.cgContext
    draw(in: ctx)
    return rep.representation(using: .png, properties: [:])!
}

let work = FileManager.default.temporaryDirectory.appendingPathComponent("dmg-background-\(getpid())")
try FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)
defer { try? FileManager.default.removeItem(at: work) }
try render(scale: 1).write(to: work.appendingPathComponent("background.png"))
try render(scale: 2).write(to: work.appendingPathComponent("background@2x.png"))

let tiffutil = Process()
tiffutil.executableURL = URL(fileURLWithPath: "/usr/bin/tiffutil")
tiffutil.arguments = [
    "-cathidpicheck", work.appendingPathComponent("background.png").path,
    work.appendingPathComponent("background@2x.png").path, "-out", "Brand/dmg-background.tiff",
]
try tiffutil.run()
tiffutil.waitUntilExit()
exit(tiffutil.terminationStatus)
