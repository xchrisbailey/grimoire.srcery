// Writes Brand/wordmark-{dark,light}.svg: "grimoire" in Geist 800 with the i dots swapped
// for a pink ring and a lavender dot, and a peach Geist Mono "_" cursor, all as outlines.
// Run from the repo root: swift Brand/scripts/wordmark.swift
import CoreText
import Foundation

let size: CGFloat = 100
let tracking = -0.045 * size

func font(_ file: String, weight: CGFloat) -> CTFont {
    let url = URL(fileURLWithPath: "Resources/Fonts/\(file)") as CFURL
    let descriptor = (CTFontManagerCreateFontDescriptorsFromURL(url) as! [CTFontDescriptor])[0]
    let wght = 0x7767_6874  // 'wght'
    let varied = CTFontDescriptorCreateCopyWithAttributes(
        descriptor, [kCTFontVariationAttribute: [wght: weight]] as CFDictionary)
    return CTFontCreateWithFontDescriptor(varied, size, nil)
}

func glyph(_ font: CTFont, _ char: Character) -> CGGlyph {
    var chars = Array(String(char).utf16)
    var glyphs = [CGGlyph](repeating: 0, count: chars.count)
    CTFontGetGlyphsForCharacters(font, &chars, &glyphs, chars.count)
    return glyphs[0]
}

func svgPath(_ path: CGPath, dx: CGFloat, baseline: CGFloat) -> String {
    var d = ""
    func p(_ pt: CGPoint) -> String { String(format: "%.2f %.2f", pt.x + dx, baseline - pt.y) }
    path.applyWithBlock { element in
        let e = element.pointee
        switch e.type {
        case .moveToPoint: d += "M\(p(e.points[0]))"
        case .addLineToPoint: d += "L\(p(e.points[0]))"
        case .addQuadCurveToPoint: d += "Q\(p(e.points[0])) \(p(e.points[1]))"
        case .addCurveToPoint: d += "C\(p(e.points[0])) \(p(e.points[1])) \(p(e.points[2]))"
        case .closeSubpath: d += "Z"
        @unknown default: break
        }
    }
    return d
}

let geist = font("Geist.ttf", weight: 800)
let mono = font("GeistMono.ttf", weight: 700)
let baseline = CTFontGetAscent(geist) + 0.1 * size
var x: CGFloat = 0.02 * size
var letters = ""
var dotCenters: [CGFloat] = []

// The tittle of a real "i" sets how high the ring and dot sit.
let iBounds = CTFontGetBoundingRectsForGlyphs(geist, .horizontal, [glyph(geist, "i")], nil, 1)
let tittleY = baseline - (iBounds.maxY - 0.04 * size)

for char in "grımoıre" {
    let g = glyph(geist, char)
    var advance = CGSize.zero
    CTFontGetAdvancesForGlyphs(geist, .horizontal, [g], &advance, 1)
    if let path = CTFontCreatePathForGlyph(geist, g, nil) { letters += svgPath(path, dx: x, baseline: baseline) }
    if char == "ı" { dotCenters.append(x + advance.width / 2) }
    x += advance.width + tracking
}
x += 0.04 * size - tracking
let underscore = glyph(mono, "_")
var cursorPath = ""
if let path = CTFontCreatePathForGlyph(mono, underscore, nil) {
    cursorPath = svgPath(path, dx: x, baseline: baseline)
}
var monoAdvance = CGSize.zero
CTFontGetAdvancesForGlyphs(mono, .horizontal, [underscore], &monoAdvance, 1)
let width = x + monoAdvance.width + 0.02 * size
let height = baseline + CTFontGetDescent(geist) + 0.04 * size

let palettes = [
    "dark": (text: "#cdd6f4", pink: "#f5c2e7", lavender: "#b4befe", peach: "#fab387"),
    "light": (text: "#4c4f69", pink: "#ea76cb", lavender: "#7287fd", peach: "#fe640b"),
]
let ringStroke = 0.045 * size
for (name, c) in palettes {
    let svg = """
        <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 \(Int(width.rounded(.up))) \(Int(height.rounded(.up)))" \
        width="\(Int(width.rounded(.up)))" height="\(Int(height.rounded(.up)))" role="img" aria-label="grimoire">
          <path fill="\(c.text)" d="\(letters)"/>
          <circle cx="\(String(format: "%.2f", dotCenters[0]))" cy="\(String(format: "%.2f", tittleY))" \
        r="\(String(format: "%.2f", 0.1 * size - ringStroke / 2))" fill="none" stroke="\(c.pink)" \
        stroke-width="\(String(format: "%.2f", ringStroke))"/>
          <circle cx="\(String(format: "%.2f", dotCenters[1]))" cy="\(String(format: "%.2f", tittleY))" \
        r="\(String(format: "%.2f", 0.08 * size))" fill="\(c.lavender)"/>
          <path fill="\(c.peach)" d="\(cursorPath)"/>
        </svg>

        """
    try! svg.write(toFile: "Brand/wordmark-\(name).svg", atomically: true, encoding: .utf8)
}
print("wordmark \(Int(width))x\(Int(height))")
