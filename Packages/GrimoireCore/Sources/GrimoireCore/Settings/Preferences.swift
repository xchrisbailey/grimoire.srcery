import Foundation
import Observation

/// Where pasted and inserted images are saved.
public enum ImageLocation: String, Codable, CaseIterable, Sendable {
    /// An `assets/` folder next to the page.
    case besideFile
    /// One `assets/` folder at the top of the bound folder holding the page.
    case projectFolder
}

/// Whether pasted and inserted images get alt text written for them.
public enum AltTextMode: String, Codable, CaseIterable, Sendable {
    /// Fill it in without asking.
    case always
    /// Offer it, and fill it in only when the offer is taken.
    case ask
    case never
}

/// Where the word count and reading time show.
public enum WordCountDisplay: String, Codable, CaseIterable, Sendable {
    /// At the foot of every page.
    case always
    /// Only in focus mode.
    case focusMode
    case never
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

    // MARK: Fonts

    /// The prose font's family, "Geist" by default.
    public var proseFont: String { didSet { save(proseFont, Key.proseFont) } }
    public var proseSize: Double { didSet { save(proseSize, Key.proseSize) } }
    /// The code and Raw font's family, "Geist Mono" by default.
    public var codeFont: String { didSet { save(codeFont, Key.codeFont) } }
    public var codeSize: Double { didSet { save(codeSize, Key.codeSize) } }

    // MARK: Editor

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
    public var wordCount: WordCountDisplay { didSet { save(wordCount.rawValue, Key.wordCount) } }
    /// Words a minute, for the reading time.
    public var readingSpeed: Double { didSet { save(readingSpeed, Key.readingSpeed) } }

    // MARK: Raw

    /// Whether Raw mode numbers its lines.
    public var showsLineNumbers: Bool { didSet { save(showsLineNumbers, Key.showsLineNumbers) } }
    /// Columns between tab stops in Raw and code blocks.
    public var tabWidth: Int { didSet { save(tabWidth, Key.tabWidth) } }
    /// Whether Tab types a tab character instead of spaces.
    public var indentsWithTabs: Bool { didSet { save(indentsWithTabs, Key.indentsWithTabs) } }

    // MARK: Shortcuts

    /// Shortcuts changed from their defaults. A combo with no key means none; read them
    /// through `shortcut(for:)`.
    public internal(set) var shortcutOverrides: [ShortcutAction: KeyCombo] {
        didSet { save((try? JSONEncoder().encode(shortcutOverrides)) ?? Data(), Key.shortcuts) }
    }

    // MARK: Spelling

    public var checksSpelling: Bool { didSet { save(checksSpelling, Key.checksSpelling) } }
    public var checksGrammar: Bool { didSet { save(checksGrammar, Key.checksGrammar) } }
    public var correctsSpelling: Bool { didSet { save(correctsSpelling, Key.correctsSpelling) } }
    public var smartQuotes: Bool { didSet { save(smartQuotes, Key.smartQuotes) } }
    public var smartDashes: Bool { didSet { save(smartDashes, Key.smartDashes) } }
    public var textReplacement: Bool { didSet { save(textReplacement, Key.textReplacement) } }

    // MARK: Intelligence

    /// Whether the on-device AI features are offered at all.
    public var intelligenceEnabled: Bool { didSet { save(intelligenceEnabled, Key.intelligenceEnabled) } }
    /// Whether long pages may go to Private Cloud Compute. Off unless the user turns it on.
    public var allowsPrivateCloud: Bool { didSet { save(allowsPrivateCloud, Key.allowsPrivateCloud) } }
    /// Alt text for images as they're pasted or inserted. Asks first by default.
    public var altText: AltTextMode { didSet { save(altText.rawValue, Key.altText) } }

    /// Whether AI features are on for `project`.
    public func intelligenceEnabled(for project: Project?) -> Bool {
        intelligenceEnabled && project?.overrides.intelligenceOff != true
    }

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
        static let wordCount = "settings.wordCount"
        static let readingSpeed = "settings.readingSpeed"
        static let showsLineNumbers = "settings.showsLineNumbers"
        static let tabWidth = "settings.tabWidth"
        static let indentsWithTabs = "settings.indentsWithTabs"
        static let shortcuts = "settings.shortcuts"
        static let checksSpelling = "settings.checksSpelling"
        static let checksGrammar = "settings.checksGrammar"
        static let correctsSpelling = "settings.correctsSpelling"
        static let smartQuotes = "settings.smartQuotes"
        static let smartDashes = "settings.smartDashes"
        static let textReplacement = "settings.textReplacement"
        static let intelligenceEnabled = "settings.intelligenceEnabled"
        static let allowsPrivateCloud = "settings.allowsPrivateCloud"
        static let altText = "settings.altText"
    }

    /// The system's own Keyboard settings, which the substitutions start from.
    private enum SystemKey {
        static let correction = "NSAutomaticSpellingCorrectionEnabled"
        static let quotes = "NSAutomaticQuoteSubstitutionEnabled"
        static let dashes = "NSAutomaticDashSubstitutionEnabled"
        static let replacement = "NSAutomaticTextReplacementEnabled"
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
        wordCount = defaults.string(forKey: Key.wordCount).flatMap(WordCountDisplay.init) ?? .focusMode
        readingSpeed = defaults.object(forKey: Key.readingSpeed) as? Double ?? 230
        showsLineNumbers = defaults.object(forKey: Key.showsLineNumbers) as? Bool ?? false
        tabWidth = defaults.object(forKey: Key.tabWidth) as? Int ?? 4
        indentsWithTabs = defaults.object(forKey: Key.indentsWithTabs) as? Bool ?? false
        shortcutOverrides =
            defaults.data(forKey: Key.shortcuts).flatMap {
                try? JSONDecoder().decode([ShortcutAction: KeyCombo].self, from: $0)
            } ?? [:]
        checksSpelling = defaults.object(forKey: Key.checksSpelling) as? Bool ?? true
        checksGrammar = defaults.object(forKey: Key.checksGrammar) as? Bool ?? true
        func system(_ key: String) -> Bool { defaults.object(forKey: key) as? Bool ?? true }
        correctsSpelling = defaults.object(forKey: Key.correctsSpelling) as? Bool ?? system(SystemKey.correction)
        smartQuotes = defaults.object(forKey: Key.smartQuotes) as? Bool ?? system(SystemKey.quotes)
        smartDashes = defaults.object(forKey: Key.smartDashes) as? Bool ?? system(SystemKey.dashes)
        textReplacement = defaults.object(forKey: Key.textReplacement) as? Bool ?? system(SystemKey.replacement)
        intelligenceEnabled = defaults.object(forKey: Key.intelligenceEnabled) as? Bool ?? true
        allowsPrivateCloud = defaults.object(forKey: Key.allowsPrivateCloud) as? Bool ?? false
        altText = defaults.string(forKey: Key.altText).flatMap(AltTextMode.init) ?? .ask
    }

    /// Puts the fonts and sizes back to Geist and Geist Mono at the brand sizes.
    public func resetFonts() {
        proseFont = Self.defaultProseFont
        proseSize = 15.5
        codeFont = Self.defaultCodeFont
        codeSize = 14
    }

    /// Puts the Editor settings back to their defaults. Fonts live in Appearance and
    /// aren't touched.
    public func resetEditor() {
        lineHeight = 1.7
        maxLineWidth = 680
        showsMarkers = false
        typewriterScrolling = false
        focusDimming = true
        wordCount = .focusMode
        readingSpeed = 230
        showsLineNumbers = false
        tabWidth = 4
        indentsWithTabs = false
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
    /// True when the project has AI features turned off.
    public var intelligenceOff: Bool?

    public init(fileExtensions: [String]? = nil, imageLocation: ImageLocation? = nil, intelligenceOff: Bool? = nil) {
        self.fileExtensions = fileExtensions
        self.imageLocation = imageLocation
        self.intelligenceOff = intelligenceOff
    }
}
