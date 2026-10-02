import Foundation

struct Catalog: Decodable {
  let categories: [Category]
  let calculators: [Calculator]
  let countries: [Country]
  let financialNotice: String
}

struct Category: Decodable, Identifiable, Hashable {
  let slug: String
  let name: String
  let shortName: String
  let mark: String
  let description: String

  var id: String { slug }
}

struct Calculator: Decodable, Identifiable, Hashable {
  let number: String
  let slug: String
  let title: String
  let category: String
  let question: String

  var id: String { slug }
  var webURL: URL { URL(string: "https://calculum.dev/calculators/\(slug)/")! }

  enum CodingKeys: String, CodingKey {
    case number = "id", slug, title, category, question
  }
}

struct Country: Decodable, Identifiable, Hashable {
  let code: String
  let name: String
  let locale: String
  let currency: String
  let measurement: String

  var id: String { code }
}

struct Tool: Decodable {
  let slug: String
  let eyebrow: String
  let formula: String
  let assumptions: [String]
  let fields: [Field]
  let defaults: [String: Double]
  let guide: Guide?
  let examples: [Example]
  let sources: [Source]
  let context: CountryContext?
  let financial: Bool
  let hasProjection: Bool
}

struct Field: Decodable, Identifiable, Hashable {
  let name: String
  let label: String
  let kind: String
  let prefix: String?
  let suffix: String?
  let unit: String
  let step: Double?
  let options: [Option]?

  var id: String { name }
  var isSelect: Bool { kind == "select" }

  struct Option: Decodable, Hashable {
    let value: Double
    let label: String
  }
}

struct Guide: Decodable {
  let intro: String
  let takeaway: String
  let interpretation: [String]
  let edgeCases: [Note]
  let drivers: [Note]
  let mistakes: [Note]
  let useFor: String
  let notFor: String

  struct Note: Decodable, Hashable {
    let title: String
    let body: String
  }
}

struct Example: Decodable, Hashable {
  let title: String
  let description: String
  let values: [String: Double]
}

struct Source: Decodable, Hashable {
  let label: String?
  let organization: String?
  let scope: String?
  let note: String?
  let url: String
}

struct CountryContext: Decodable {
  let title: String
  let body: String
  let sourceLabel: String?
  let sourceURL: String?
}

struct Output: Decodable, Equatable {
  let primary: String
  let label: String
  let details: [[String]]
  let note: String
  let metric: Metric?

  struct Metric: Decodable, Equatable {
    let value: Double
    let label: String
  }
}

struct Sensitivity: Decodable {
  let metricLabel: String
  let currentX: Double
  let currentY: Double
  let points: [Point]

  struct Point: Decodable, Identifiable {
    let x: Double
    let y: Double

    var id: Double { x }
  }
}

struct Projection: Decodable {
  let title: String
  let description: String
  let valueType: String
  let series: [Series]
  let points: [Point]

  struct Series: Decodable, Hashable {
    let key: String
    let label: String
  }

  struct Point: Decodable {
    let x: Double
    let label: String
    let values: [String: Double]
  }
}

extension Output {
  var lines: [SavedCalculation.Line] {
    details.compactMap { $0.count == 2 ? SavedCalculation.Line(label: $0[0], value: $0[1]) : nil }
  }
}

extension Tool {
  /// The inputs as they read on screen, like "Home price: $420,000".
  /// `display` converts a value to the unit shown, like metres to feet.
  func inputLines(values: [String: Double], locale: Locale, display: (Double, String) -> Double) -> [SavedCalculation.Line] {
    fields.map { field in
      let value = values[field.name] ?? defaults[field.name] ?? 0
      if field.isSelect {
        let option = field.options?.first { $0.value == value }?.label
        return .init(label: field.label, value: option ?? NumberText.display(value, locale: locale))
      }
      let number = (field.prefix ?? "") + NumberText.display(display(value, field.unit), locale: locale)
      switch field.suffix {
      case nil: return .init(label: field.label, value: number)
      case "%": return .init(label: field.label, value: number + "%")
      case let suffix?: return .init(label: field.label, value: "\(number) \(suffix)")
      }
    }
  }
}

/// A calculation saved with ⌘S: the inputs as they were shown and the result,
/// frozen at that moment, plus the raw values to open it in the calculator again.
struct SavedCalculation: Codable, Identifiable, Hashable {
  var id = UUID()
  var name: String
  var date: Date
  var slug: String
  var calculator: String
  var question: String
  var category: String
  var country: String
  var inputs: [Line]
  var eyebrow: String
  var primary: String
  var label: String
  var details: [Line]
  var note: String
  var values: [String: Double]
  /// The locale the numbers were written in, to read them back for comparisons.
  var locale: String?

  struct Line: Codable, Hashable {
    var label: String
    var value: String
  }

  /// Plain text for the clipboard.
  var summary: String {
    var lines = [name, "\(calculator), \(date.formatted(date: .abbreviated, time: .shortened))", ""]
    lines += inputs.map { "\($0.label): \($0.value)" }
    lines += ["", "\(eyebrow): \(primary) \(label)"]
    lines += details.map { "\($0.label): \($0.value)" }
    if !note.isEmpty { lines += ["", note] }
    return lines.joined(separator: "\n")
  }
}
