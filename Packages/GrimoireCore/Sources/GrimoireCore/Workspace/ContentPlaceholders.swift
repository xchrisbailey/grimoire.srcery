import Foundation

enum ContentPlaceholders {
    static func expand(_ snapshot: Data, filename: String, date: Date, calendar: Calendar) -> Data {
        let parts = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
        func pad(_ value: Int?, _ width: Int = 2) -> String {
            let text = String(value ?? 0)
            return String(repeating: "0", count: max(0, width - text.count)) + text
        }
        var values = [
            "title": String(filename.dropLast(3)),
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
        var output = Data()
        var index = 0
        while index < source.count {
            guard source[index] == 0x7b else {
                output.append(source[index])
                index += 1
                continue
            }
            guard let end = source[(index + 1)...].firstIndex(of: 0x7d) else {
                output.append(contentsOf: source[index...])
                break
            }
            let doubled = source[index + 1] == 0x7b
            let tokenStart = index + (doubled ? 2 : 1)
            let token = String(decoding: source[tokenStart..<end], as: UTF8.self)
            if doubled, end + 1 < source.count, source[end + 1] == 0x7d {
                if values[token] != nil {
                    output.append(contentsOf: source[(index + 1)...end])
                } else {
                    output.append(contentsOf: source[index...(end + 1)])
                }
                index = end + 2
                continue
            } else if !doubled, let value = values[token] {
                output.append(contentsOf: value.utf8)
            } else {
                output.append(contentsOf: source[index...end])
            }
            index = end + 1
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
