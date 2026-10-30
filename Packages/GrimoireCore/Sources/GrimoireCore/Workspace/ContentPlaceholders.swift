import Foundation

enum ContentPlaceholders {
    static func expand(_ snapshot: Data, filename: String, date: Date, calendar: Calendar) -> Data {
        let parts = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
        func pad(_ value: Int?, _ width: Int = 2) -> String {
            let text = String(value ?? 0)
            return String(repeating: "0", count: max(0, width - text.count)) + text
        }
        // The publisher appends ASCII .md. A trailing stem scalar can share the dot's
        // grapheme, so remove exactly those suffix bytes rather than whole Characters.
        var values = [
            "title": String(decoding: filename.utf8.dropLast(3), as: UTF8.self),
            "filename": filename,
            "date": "\(pad(parts.year, 4))-\(pad(parts.month))-\(pad(parts.day))",
            "time": "\(pad(parts.hour)):\(pad(parts.minute)):\(pad(parts.second))",
        ]
        for (name, value) in values { values[name + ":yaml"] = yamlString(value) }
        return substitute(snapshot, values: values)
    }

    private static func substitute(_ snapshot: Data, values: [String: String]) -> Data {
        // Scan only saved bytes, so inserted names cannot become placeholders and untouched
        // BOMs, line endings and whitespace never pass through a text serializer.
        let source = Array(snapshot)
        let substitutions = values.flatMap { name, value -> [(token: [UInt8], replacement: [UInt8])] in
            let token = "{\(name)}"
            return [
                (Array("{\(token)}".utf8), Array(token.utf8)),
                (Array(token.utf8), Array(value.utf8)),
            ]
        }
        var output = Data()
        var index = 0
        while index < source.count {
            if source[index] == 0x7b,
                let substitution = substitutions.first(where: { source[index...].starts(with: $0.token) })
            {
                output.append(contentsOf: substitution.replacement)
                index += substitution.token.count
            } else {
                output.append(source[index])
                index += 1
            }
        }
        return output
    }

    private static func yamlString(_ value: String) -> String {
        var output = "\""
        for scalar in value.unicodeScalars {
            switch scalar.value {
            case 0x22: output += "\\\""
            case 0x5c: output += "\\\\"
            case 0...0x1f, 0x7f...0x9f, 0x2028, 0x2029, 0xfeff:
                let hex = String(scalar.value, radix: 16, uppercase: true)
                output += "\\u" + String(repeating: "0", count: 4 - hex.count) + hex
            default: output.unicodeScalars.append(scalar)
            }
        }
        return output + "\""
    }
}
