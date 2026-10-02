import AppKit
import SwiftUI

/// A font family menu: the brand font first, then everything installed.
struct FontPicker: View {
    let title: String
    @Binding var family: String
    let brandFamily: String
    let monospacedOnly: Bool

    var body: some View {
        Picker(title, selection: $family) {
            Text(brandFamily).tag(brandFamily)
            Divider()
            ForEach((monospacedOnly ? Self.monospaced : Self.all).filter { $0 != brandFamily }, id: \.self) { name in
                Text(name).tag(name)
            }
        }
    }

    @MainActor static let all = families(monospaced: false)
    @MainActor static let monospaced = families(monospaced: true)

    /// Installed families, monospaced ones only for code.
    static func families(monospaced: Bool) -> [String] {
        let manager = NSFontManager.shared
        guard monospaced else { return manager.availableFontFamilies }
        return manager.availableFontFamilies.filter { family in
            guard let member = manager.availableMembers(ofFontFamily: family)?.first,
                let name = member.first as? String, let font = NSFont(name: name, size: 12)
            else { return false }
            return font.isFixedPitch || font.fontDescriptor.symbolicTraits.contains(.monoSpace)
        }
    }
}
