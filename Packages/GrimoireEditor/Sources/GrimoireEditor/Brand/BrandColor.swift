import GrimoireCore
import SwiftUI

#if os(macOS)
import AppKit
#else
import UIKit
#endif

extension Color {
    /// A color for one brand role from the chosen themes, following the appearance: the
    /// light theme in light mode, the dark theme in dark mode. `Color.brand(\.magic)`.
    ///
    /// Reading it in a view's body ties the view to the theme library, so the view redraws
    /// when a theme changes.
    @MainActor
    public static func brand(_ role: KeyPath<BrandPalette, PaletteColor>) -> Color {
        let themes = ThemeLibrary.shared
        let light = themes.lightTheme.palette[keyPath: role]
        let dark = themes.darkTheme.palette[keyPath: role]
        #if os(macOS)
        return Color(
            nsColor: NSColor(name: nil) { appearance in
                let isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
                return NSColor(isDark ? dark : light)
            })
        #else
        return Color(
            uiColor: UIColor { traits in UIColor(traits.userInterfaceStyle == .dark ? dark : light) })
        #endif
    }

    /// One fixed palette color, for views that render a specific theme.
    public init(_ color: PaletteColor) {
        self.init(.sRGB, red: Double(color.red) / 255, green: Double(color.green) / 255, blue: Double(color.blue) / 255)
    }
}

#if os(macOS)
extension NSColor {
    public convenience init(_ color: PaletteColor) {
        self.init(
            srgbRed: CGFloat(color.red) / 255, green: CGFloat(color.green) / 255, blue: CGFloat(color.blue) / 255,
            alpha: 1)
    }
}
#else
extension UIColor {
    public convenience init(_ color: PaletteColor) {
        self.init(
            red: CGFloat(color.red) / 255, green: CGFloat(color.green) / 255, blue: CGFloat(color.blue) / 255,
            alpha: 1)
    }
}
#endif
