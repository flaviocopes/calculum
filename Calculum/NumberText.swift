import Foundation

/// Formats and reads numbers. Input fields drop the thousands separator, so
/// "420000" is easy to edit, and accept a comma or a dot as the decimal
/// separator whatever the country.
enum NumberText {
  static func format(_ value: Double, locale: Locale) -> String {
    let formatter = NumberFormatter()
    formatter.locale = locale
    formatter.numberStyle = .decimal
    formatter.usesGroupingSeparator = false
    formatter.minimumFractionDigits = 0
    formatter.maximumFractionDigits = 3
    return formatter.string(from: NSNumber(value: value)) ?? String(value)
  }

  /// A number for reading, with thousands separators: "420,000".
  static func display(_ value: Double, locale: Locale) -> String {
    value.formatted(.number.precision(.fractionLength(0...3)).locale(locale))
  }

  static func parse(_ text: String, locale: Locale) -> Double? {
    var text = text.filter { !$0.isWhitespace && $0 != "'" && $0 != "’" }
    text = text.replacingOccurrences(of: "−", with: "-")
    guard !text.isEmpty else { return nil }
    let lastComma = text.lastIndex(of: ",")
    let lastDot = text.lastIndex(of: ".")

    if let lastComma, let lastDot {
      if lastComma > lastDot {
        text = text.replacingOccurrences(of: ".", with: "").replacingOccurrences(of: ",", with: ".")
      } else {
        text = text.replacingOccurrences(of: ",", with: "")
      }
    } else if let lastComma {
      let groups = groupsThousands(text, separator: ",", at: lastComma, localDecimal: locale.decimalSeparator == ",")
      text = groups ? text.replacingOccurrences(of: ",", with: "") : text.replacingOccurrences(of: ",", with: ".")
    } else if let lastDot, groupsThousands(text, separator: ".", at: lastDot, localDecimal: locale.decimalSeparator == ".") {
      text = text.replacingOccurrences(of: ".", with: "")
    }
    return Double(text)
  }

  /// Decides whether a lone separator splits thousands, like "1,500" in the US or
  /// "1.500" in Italy, or marks the decimals. Repeated separators always group,
  /// and a number that starts with 0, like "0,125", always has decimals.
  private static func groupsThousands(_ text: String, separator: Character, at index: String.Index, localDecimal: Bool) -> Bool {
    if text.filter({ $0 == separator }).count > 1 { return true }
    let whole = text[..<index].filter(\.isNumber)
    guard !whole.isEmpty, whole != "0" else { return false }
    return text[text.index(after: index)...].count == 3 && !localDecimal
  }
}
