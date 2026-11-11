import Foundation

enum FrequencyScale {
    static let lower = 87.5
    static let upper = 108.0
    static func fm(_ label: String) -> Double? {
        let pattern = #"^\s*([0-9]{2,3}(?:[.,][0-9]{1,2})?)\s*(?:FM|MHz)\s*$"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
              let match = regex.firstMatch(in: label, range: NSRange(label.startIndex..., in: label)),
              let range = Range(match.range(at: 1), in: label),
              let value = Double(label[range].replacingOccurrences(of: ",", with: ".")),
              (lower...upper).contains(value) else { return nil }
        return value
    }
    static func position(_ frequency: Double) -> Double {
        guard frequency.isFinite else { return 0 }
        return min(1, max(0, (frequency - lower) / (upper - lower)))
    }
}
