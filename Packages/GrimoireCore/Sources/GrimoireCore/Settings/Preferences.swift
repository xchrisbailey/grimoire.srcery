import Foundation
import Observation

/// Where pasted and inserted images are saved.
public enum ImageLocation: String, Codable, CaseIterable, Sendable {
    /// An `assets/` folder next to the page.
    case besideFile
    /// One `assets/` folder at the top of the bound folder holding the page.
    case projectFolder
}

/// The user's settings, saved in `UserDefaults`. Views and windows read them from the
/// shared instance, so a change applies everywhere at once.
@MainActor @Observable
public final class Preferences {
    public static let shared = Preferences()

    // MARK: General

    /// Whether files open in Raw unless they were last left in Preview.
    public var opensInRaw: Bool { didSet { save(opensInRaw, Key.opensInRaw) } }
    /// Whether a window reopens the file it showed when the app last quit.
    public var restoresLastSession: Bool { didSet { save(restoresLastSession, Key.restoresLastSession) } }
    /// Seconds of quiet before edits save themselves.
    public var autosaveDelay: Double { didSet { save(autosaveDelay, Key.autosaveDelay) } }
    /// File extensions listed in the sidebar, lowercased and without dots.
    public var fileExtensions: [String] { didSet { save(fileExtensions, Key.fileExtensions) } }
    public var imageLocation: ImageLocation { didSet { save(imageLocation.rawValue, Key.imageLocation) } }

    // MARK: Editor

    /// The prose font's family, "Geist" by default.
    public var proseFont: String { didSet { save(proseFont, Key.proseFont) } }
    public var proseSize: Double { didSet { save(proseSize, Key.proseSize) } }
    /// The code and Raw font's family, "Geist Mono" by default.
    public var codeFont: String { didSet { save(codeFont, Key.codeFont) } }
    public var codeSize: Double { didSet { save(codeSize, Key.codeSize) } }
    /// Prose line height as a multiple of the font size, as CSS measures it.
    public var lineHeight: Double { didSet { save(lineHeight, Key.lineHeight) } }
    /// Widest the text column grows, in points.
    public var maxLineWidth: Double { didSet { save(maxLineWidth, Key.maxLineWidth) } }
    /// Whether markdown markers show on every line, not just the caret's block.
    public var showsMarkers: Bool { didSet { save(showsMarkers, Key.showsMarkers) } }
    /// Whether the caret's line stays in the middle of the window while typing.
    public var typewriterScrolling: Bool { didSet { save(typewriterScrolling, Key.typewriterScrolling) } }
    /// Whether focus mode fades every block but the caret's.
    public var focusDimming: Bool { didSet { save(focusDimming, Key.focusDimming) } }

    public static let defaultExtensions = ["md", "mdx"]
    public static let defaultProseFont = "Geist"
    public static let defaultCodeFont = "Geist Mono"

    @ObservationIgnored private let defaults: UserDefaults

    enum Key {
        static let opensInRaw = "settings.opensInRaw"
        static let restoresLastSession = "settings.restoresLastSession"
        static let autosaveDelay = "settings.autosaveDelay"
        static let fileExtensions = "settings.fileExtensions"
        static let imageLocation = "settings.imageLocation"
        static let proseFont = "settings.proseFont"
        static let proseSize = "settings.proseSize"
        static let codeFont = "settings.codeFont"
        static let codeSize = "settings.codeSize"
        static let lineHeight = "settings.lineHeight"
        static let maxLineWidth = "settings.maxLineWidth"
        static let showsMarkers = "settings.showsMarkers"
        static let typewriterScrolling = "settings.typewriterScrolling"
        static let focusDimming = "settings.focusDimming"
    }

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        opensInRaw = defaults.object(forKey: Key.opensInRaw) as? Bool ?? false
        restoresLastSession = defaults.object(forKey: Key.restoresLastSession) as? Bool ?? true
        autosaveDelay = defaults.object(forKey: Key.autosaveDelay) as? Double ?? 1
        fileExtensions = defaults.stringArray(forKey: Key.fileExtensions) ?? Self.defaultExtensions
        imageLocation = defaults.string(forKey: Key.imageLocation).flatMap(ImageLocation.init) ?? .besideFile
        proseFont = defaults.string(forKey: Key.proseFont) ?? Self.defaultProseFont
        proseSize = defaults.object(forKey: Key.proseSize) as? Double ?? 15.5
        codeFont = defaults.string(forKey: Key.codeFont) ?? Self.defaultCodeFont
        codeSize = defaults.object(forKey: Key.codeSize) as? Double ?? 14
        lineHeight = defaults.object(forKey: Key.lineHeight) as? Double ?? 1.7
        maxLineWidth = defaults.object(forKey: Key.maxLineWidth) as? Double ?? 680
        showsMarkers = defaults.object(forKey: Key.showsMarkers) as? Bool ?? false
        typewriterScrolling = defaults.object(forKey: Key.typewriterScrolling) as? Bool ?? false
        focusDimming = defaults.object(forKey: Key.focusDimming) as? Bool ?? true
    }

    /// Puts the Editor settings back to their defaults.
    public func resetEditor() {
        proseFont = Self.defaultProseFont
        proseSize = 15.5
        codeFont = Self.defaultCodeFont
        codeSize = 14
        lineHeight = 1.7
        maxLineWidth = 680
        showsMarkers = false
        typewriterScrolling = false
        focusDimming = true
    }

    // MARK: Per project

    /// The extensions listed for `project`: its own list when it has one, else the default.
    public func fileExtensions(for project: Project?) -> [String] {
        project?.overrides.fileExtensions ?? fileExtensions
    }

    public func imageLocation(for project: Project?) -> ImageLocation {
        project?.overrides.imageLocation ?? imageLocation
    }

    /// Reads a comma- or space-separated list like `md, .mdx, Markdown` as
    /// `["md", "mdx", "markdown"]`, dropping duplicates. Empty input gives the default list.
    public static func parseExtensions(_ text: String) -> [String] {
        var seen: Set<String> = []
        let parsed =
            text
            .split { $0 == "," || $0 == " " || $0 == ";" }
            .map { $0.trimmingCharacters(in: CharacterSet(charactersIn: ". ")).lowercased() }
            .filter { !$0.isEmpty && !$0.contains("/") && seen.insert($0).inserted }
        return parsed.isEmpty ? defaultExtensions : parsed
    }

    private func save(_ value: Any, _ key: String) {
        defaults.set(value, forKey: key)
    }
}

/// Settings a project keeps for itself, overriding the app's. Nil means "use the default".
public struct ProjectOverrides: Codable, Hashable, Sendable {
    public var fileExtensions: [String]?
    public var imageLocation: ImageLocation?

    public init(fileExtensions: [String]? = nil, imageLocation: ImageLocation? = nil) {
        self.fileExtensions = fileExtensions
        self.imageLocation = imageLocation
    }
}
