import Foundation

/// Where new files go when nothing says otherwise.
public enum NewFileLocation: String, Codable, CaseIterable, Sendable {
    /// Beside the open file, else at the top of the first folder.
    case besideSelection
    /// At the top of the first bound folder.
    case firstFolder
    /// In a named folder inside the first bound folder, made if it's missing.
    case subfolder
}

/// Names for new files from a template such as `{date} Notes`.
public enum FileNaming {
    public static let defaultTemplate = "Untitled"

    /// `template` with `{date}` as 2026-10-02 and `{time}` as 0930, made safe for a file
    /// name. An empty result falls back to "Untitled".
    public static func name(from template: String, date: Date = .now, calendar: Calendar = .current) -> String {
        let parts = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        func pad(_ value: Int?, _ width: Int) -> String {
            let text = String(value ?? 0)
            return String(repeating: "0", count: max(0, width - text.count)) + text
        }
        let day = "\(pad(parts.year, 4))-\(pad(parts.month, 2))-\(pad(parts.day, 2))"
        let time = pad(parts.hour, 2) + pad(parts.minute, 2)
        let name =
            template
            .replacingOccurrences(of: "{date}", with: day)
            .replacingOccurrences(of: "{time}", with: time)
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let visible = String(name.drop { $0 == "." })
        return visible.isEmpty ? defaultTemplate : visible
    }

    /// A folder path typed in Settings, like `notes/inbox`, as safe path components.
    /// Empty, `.` and `..` parts are dropped.
    public static func folderComponents(_ path: String) -> [String] {
        path.split(separator: "/")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && $0 != "." && $0 != ".." }
    }
}
