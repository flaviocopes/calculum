import AppKit
import SwiftUI

/// Two saved calculations from the same calculator, lined up row by row.
/// A is the older one, B the newer.
struct Comparison {
  let a: SavedCalculation
  let b: SavedCalculation
  let inputs: [Row]
  /// The main result first, then its details.
  let results: [Row]
  /// How much the main result changed from A to B, like "+$195.97 (+9.5%)".
  let change: String?

  struct Row: Identifiable {
    let id: Int
    let label: String
    let a: String
    let b: String
    let change: String?

    var differs: Bool { a != b }
  }

  init?(_ a: SavedCalculation, _ b: SavedCalculation, fallbackLocale: Locale) {
    guard a.slug == b.slug else { return nil }
    let locale = a.locale.map(Locale.init(identifier:)) ?? fallbackLocale
    self.a = a
    self.b = b
    inputs = Self.rows(a.inputs, b.inputs, locale: locale)
    results = Self.rows(
      [.init(label: a.eyebrow, value: a.primary)] + a.details,
      [.init(label: b.eyebrow, value: b.primary)] + b.details,
      locale: locale
    )
    change = Delta.between(a.primary, b.primary, locale: locale, percent: true)
  }

  /// Rows matched by label, in A's order, with anything only B has at the end.
  private static func rows(_ a: [SavedCalculation.Line], _ b: [SavedCalculation.Line], locale: Locale) -> [Row] {
    let labels = a.map(\.label) + b.map(\.label).filter { label in !a.contains { $0.label == label } }
    return labels.enumerated().map { index, label in
      let left = a.first { $0.label == label }?.value ?? "—"
      let right = b.first { $0.label == label }?.value ?? "—"
      let change = left == right ? nil : Delta.between(left, right, locale: locale, percent: false)
      return Row(id: index, label: label, a: left, b: right, change: change)
    }
  }

  /// Plain text for the clipboard.
  var summary: String {
    var lines = ["\(a.calculator): \(a.name) (A) and \(b.name) (B)", ""]
    for row in inputs + results {
      lines.append("\(row.label): \(row.a) → \(row.b)" + (row.change.map { " (\($0))" } ?? ""))
    }
    return lines.joined(separator: "\n")
  }
}

/// The difference between two values written the same way, like "$2,068.81" and
/// "$2,264.78". Values that don't share the same text around the number, like
/// "16y 7m" and "18y 2m", have no difference.
enum Delta {
  static func between(_ a: String, _ b: String, locale: Locale, percent: Bool) -> String? {
    guard let left = split(a), let right = split(b),
          left.prefix == right.prefix, left.suffix == right.suffix,
          let x = NumberText.parse(left.number, locale: locale),
          let y = NumberText.parse(right.number, locale: locale) else { return nil }
    let digits = max(fractionDigits(left.number, locale), fractionDigits(right.number, locale))
    let difference = y - x
    let amount = abs(difference).formatted(.number.precision(.fractionLength(digits)).locale(locale))
    guard amount != 0.0.formatted(.number.precision(.fractionLength(digits)).locale(locale)) else { return "Same" }
    var text = (difference > 0 ? "+" : "−") + left.prefix + amount + left.suffix
    if percent, x != 0 {
      let share = (difference / abs(x) * 100).formatted(.number.precision(.fractionLength(1)).sign(strategy: .always()).locale(locale))
      text += " (\(share)%)"
    }
    return text
  }

  private static let separators: Set<Character> = [",", ".", "'", "’", " ", "\u{00A0}", "\u{202F}"]

  /// "$2,068.81" → ("$", "2,068.81", ""). The number is the first run of digits and separators.
  private static func split(_ text: String) -> (prefix: String, number: String, suffix: String)? {
    guard let start = text.firstIndex(where: \.isNumber) else { return nil }
    var end = start
    var index = start
    while index < text.endIndex, text[index].isNumber || separators.contains(text[index]) {
      if text[index].isNumber { end = text.index(after: index) }
      index = text.index(after: index)
    }
    return (String(text[..<start]), String(text[start..<end]), String(text[end...]))
  }

  /// Digits after the decimal separator, when it really is one and not a thousands separator.
  private static func fractionDigits(_ number: String, _ locale: Locale) -> Int {
    guard let separator = locale.decimalSeparator,
          let range = number.range(of: separator, options: .backwards),
          NumberText.parse(number, locale: locale) != NumberText.parse(number.replacingOccurrences(of: separator, with: ""), locale: locale)
    else { return 0 }
    return number[range.upperBound...].count
  }
}

struct ComparisonView: View {
  let model: AppModel
  let comparison: Comparison

  private var tone: Color { Theme.tone(comparison.a.category) }

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 20) {
        header

        HStack(alignment: .top, spacing: 16) {
          tile(comparison.a, letter: "A")
          tile(comparison.b, letter: "B")
        }

        if let change = comparison.change {
          Label {
            Text("The result changes by \(Text(change).fontWeight(.bold)) from A to B")
          } icon: {
            Image(systemName: "arrow.right.circle.fill")
              .foregroundStyle(tone)
          }
          .font(.title3)
        }

        table("Inputs", rows: comparison.inputs)
        table("Results", rows: comparison.results)

        Text("Rows that differ are in bold. The changes compare values written the same way, so durations like 16y 7m show both values instead.")
          .font(.footnote)
          .foregroundStyle(.secondary)
          .fixedSize(horizontal: false, vertical: true)
      }
      .padding(28)
      .frame(maxWidth: 1080, alignment: .leading)
      .frame(maxWidth: .infinity)
    }
    .navigationTitle("Comparison")
    .toolbar {
      ToolbarItemGroup {
        Button {
          NSPasteboard.general.clearContents()
          NSPasteboard.general.setString(comparison.summary, forType: .string)
        } label: {
          Label("Copy", systemImage: "doc.on.doc")
        }
        .help("Copy the comparison")
      }
    }
  }

  private var header: some View {
    VStack(alignment: .leading, spacing: 10) {
      HStack(spacing: 8) {
        CategoryIcon(category: comparison.a.category, size: 22)
        Text(comparison.a.calculator)
          .font(.callout.weight(.semibold))
      }
      Text("Comparison")
        .font(.system(size: 38, weight: .heavy, design: .rounded))
      Text(comparison.a.question)
        .font(.title3)
        .foregroundStyle(.secondary)
        .fixedSize(horizontal: false, vertical: true)
    }
    .padding(.bottom, 4)
  }

  private func tile(_ calculation: SavedCalculation, letter: String) -> some View {
    VStack(alignment: .leading, spacing: 4) {
      HStack(spacing: 8) {
        LetterBadge(letter: letter)
        VStack(alignment: .leading, spacing: 0) {
          Text(calculation.name)
            .font(.callout.weight(.semibold))
            .lineLimit(1)
          Text(calculation.date.formatted(date: .abbreviated, time: .shortened))
            .font(.caption)
            .foregroundStyle(Theme.ink.opacity(0.7))
        }
      }
      Text(calculation.primary)
        .font(.system(size: 40, weight: .heavy, design: .rounded))
        .lineLimit(1)
        .minimumScaleFactor(0.4)
        .padding(.top, 8)
        .textSelection(.enabled)
      Text(calculation.label)
        .font(.callout.weight(.medium))
        .foregroundStyle(Theme.ink.opacity(0.75))
      Button("Open in Calculator") { model.open(calculation) }
        .buttonStyle(InkButtonStyle())
        .disabled(model.calculator(calculation.slug) == nil)
        .padding(.top, 12)
    }
    .foregroundStyle(Theme.ink)
    .padding(20)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(tone, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    .environment(\.colorScheme, .light)
  }

  private func table(_ title: String, rows: [Comparison.Row]) -> some View {
    VStack(alignment: .leading, spacing: 12) {
      Text(title)
        .font(.system(.headline, design: .rounded))
      Grid(alignment: .leading, horizontalSpacing: 18, verticalSpacing: 0) {
        GridRow {
          Color.clear.frame(height: 1)
          LetterBadge(letter: "A", tone: tone).gridColumnAlignment(.trailing)
          LetterBadge(letter: "B", tone: tone).gridColumnAlignment(.trailing)
          Text("Change").font(.caption.weight(.semibold)).foregroundStyle(.secondary).gridColumnAlignment(.trailing)
        }
        .padding(.bottom, 8)
        ForEach(rows) { row in
          Divider()
          GridRow {
            Text(row.label)
              .frame(maxWidth: .infinity, alignment: .leading)
            Text(row.a).monospacedDigit()
            Text(row.b).monospacedDigit()
            Text(row.differs ? (row.change ?? "") : "—")
              .monospacedDigit()
              .foregroundStyle(row.differs ? Color.primary : Color.secondary.opacity(0.6))
          }
          .multilineTextAlignment(.trailing)
          .fontWeight(row.differs ? .semibold : .regular)
          .foregroundStyle(row.differs ? Color.primary : Color.secondary)
          .padding(.vertical, 9)
        }
      }
      .textSelection(.enabled)
    }
    .padding(22)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(Color(nsColor: .separatorColor)))
  }
}

/// "A" or "B" in a small circle: dark on the bright tiles, in the category tone in the tables.
struct LetterBadge: View {
  let letter: String
  var tone: Color?

  var body: some View {
    Text(letter)
      .font(.system(size: 12, weight: .heavy, design: .rounded))
      .foregroundStyle(tone == nil ? Color.white : Theme.ink)
      .frame(width: 22, height: 22)
      .background(tone ?? Theme.ink, in: Circle())
  }
}
