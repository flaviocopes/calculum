// calculum: the Number Pantry calculators on the command line. It ships inside the app,
// in Number Pantry.app/Contents/Helpers, and runs the same engine.js as the app.

import Foundation

struct CLIError: Error {
  let message: String
}

/// Where engine.js and the app's Info.plist are: next to this binary inside the app,
/// or wherever CALCULUM_ENGINE points while developing.
enum Paths {
  static var executable: URL {
    (Bundle.main.executableURL ?? URL(filePath: CommandLine.arguments[0])).resolvingSymlinksInPath()
  }

  static var engine: URL? {
    if let path = ProcessInfo.processInfo.environment["CALCULUM_ENGINE"] { return URL(filePath: path) }
    let folder = executable.deletingLastPathComponent()
    return [
      folder.appending(path: "../Resources/engine.js"),
      folder.appending(path: "Number Pantry.app/Contents/Resources/engine.js"),
    ].first { FileManager.default.fileExists(atPath: $0.path) }
  }

  static var version: String {
    let plist = executable.deletingLastPathComponent().appending(path: "../Info.plist")
    let info = NSDictionary(contentsOf: plist)
    return info?["CFBundleShortVersionString"] as? String ?? "1.2.0"
  }

  /// The country chosen in the app, if there is one.
  static var appCountry: String? {
    let file = URL.applicationSupportDirectory.appending(path: "Calculum/library.json")
    guard let data = try? Data(contentsOf: file),
          let library = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
    return library["country"] as? String
  }
}

@MainActor
struct CLI {
  let engine: Engine
  let country: Country
  let json: Bool
  let quiet: Bool
  let bold: (String) -> String

  var locale: Locale { Locale(identifier: country.locale) }
  var catalog: Catalog { engine.catalog }

  func run(_ arguments: [String]) throws {
    guard let command = arguments.first else {
      print(Self.usage)
      return
    }
    let rest = Array(arguments.dropFirst())
    switch command {
    case "help": print(Self.usage)
    case "list": try list(rest)
    case "search": try search(rest)
    case "show": try show(rest)
    case "categories": categories()
    case "countries": countries()
    default: try calculate(command, rest)
    }
  }

  // MARK: - Commands

  func list(_ arguments: [String]) throws {
    var calculators = catalog.calculators
    if !arguments.isEmpty {
      let category = try findCategory(arguments.joined(separator: " "))
      calculators = calculators.filter { $0.category == category.slug }
    }
    if json { return output(calculators.map(Self.summary)) }
    if arguments.isEmpty {
      for category in catalog.categories {
        print(bold("\(category.name) (\(calculators.filter { $0.category == category.slug }.count))"))
        rows(calculators.filter { $0.category == category.slug }.map { [$0.slug, $0.title] }, indent: 2)
        print()
      }
    } else {
      rows(calculators.map { [$0.slug, $0.title] })
    }
  }

  func search(_ arguments: [String]) throws {
    guard !arguments.isEmpty else { throw CLIError(message: "search needs some words, like: calculum search split bill") }
    let matches = find(arguments.joined(separator: " "))
    if json { return output(matches.map(Self.summary)) }
    if matches.isEmpty {
      print("Nothing matches \"\(arguments.joined(separator: " "))\". Try fewer words, or calculum list.")
      return
    }
    rows(matches.map { [$0.slug, $0.question] })
  }

  func show(_ arguments: [String]) throws {
    guard let name = arguments.first else { throw CLIError(message: "show needs a calculator, like: calculum show mortgage-payment") }
    let (calculator, tool) = try findTool(name)
    if json {
      return output([
        "calculator": calculator.slug,
        "title": calculator.title,
        "question": calculator.question,
        "category": calculator.category,
        "country": country.code,
        "inputs": tool.fields.map { field -> [String: Any] in
          var entry: [String: Any] = ["name": field.name, "label": field.label, "default": (displayDefault(field, tool) * 1000).rounded() / 1000]
          if let unit = unit(field) { entry["unit"] = unit }
          if let options = field.options { entry["options"] = options.map { ["value": $0.value, "label": $0.label] } }
          return entry
        },
        "formula": tool.formula,
        "assumptions": tool.assumptions,
        "url": calculator.webURL.absoluteString,
      ])
    }
    print(bold(calculator.title))
    print(calculator.question)
    print()
    print(bold("Inputs") + "  name, what it is, example value")
    let examples = tool.inputLines(values: tool.defaults, locale: locale) { engine.toDisplay($0, unit: $1) }
    rows(zip(tool.fields, examples).map { field, example in [field.name, field.label, example.value] }, indent: 2)
    for field in tool.fields {
      guard let options = field.options else { continue }
      print()
      print("  \(field.name) takes " + options.map { "\(NumberText.format($0.value, locale: Locale(identifier: "en_US"))) (\($0.label))" }.joined(separator: " or "))
    }
    print()
    print(bold("Formula"))
    print("  \(tool.formula)")
    if !tool.assumptions.isEmpty {
      print()
      print(bold("Assumptions"))
      tool.assumptions.forEach { print("  - \($0)") }
    }
    print()
    print("Example: calculum \(calculator.slug) \(tool.fields.prefix(2).map { "\($0.name)=\(NumberText.format(displayDefault($0, tool), locale: Locale(identifier: "en_US")))" }.joined(separator: " "))")
  }

  func categories() {
    if json {
      return output(catalog.categories.map { ["slug": $0.slug, "name": $0.name, "calculators": count(in: $0)] })
    }
    rows(catalog.categories.map { [$0.slug, $0.name, "\(count(in: $0))"] })
  }

  func countries() {
    if json {
      return output(catalog.countries.map { ["code": $0.code, "name": $0.name, "currency": $0.currency, "units": $0.measurement == "imperial" ? "US customary" : "metric"] })
    }
    rows(catalog.countries.map { [$0.code, $0.name, $0.currency, $0.measurement == "imperial" ? "US customary" : "metric"] })
  }

  func calculate(_ name: String, _ arguments: [String]) throws {
    let (calculator, tool) = try findTool(name)
    var values = tool.defaults
    for argument in arguments {
      guard let equals = argument.firstIndex(of: "=") else {
        throw CLIError(message: "\"\(argument)\" isn't an input. Write inputs as name=value, like price=450000. See calculum show \(calculator.slug)")
      }
      let key = String(argument[..<equals])
      let text = String(argument[argument.index(after: equals)...])
      guard let field = tool.fields.first(where: { $0.name.caseInsensitiveCompare(key) == .orderedSame }) else {
        throw CLIError(message: "\(calculator.slug) has no input called \"\(key)\". Its inputs are: \(tool.fields.map(\.name).joined(separator: ", "))")
      }
      values[field.name] = try value(text, for: field)
    }
    guard let result = engine.calculate(calculator.slug, values) else {
      throw CLIError(message: "\(calculator.title) couldn't calculate a result with these inputs.")
    }
    let inputs = tool.inputLines(values: values, locale: locale) { engine.toDisplay($0, unit: $1) }

    if quiet {
      print(result.primary)
      return
    }
    if json {
      return output([
        "calculator": calculator.slug,
        "title": calculator.title,
        "country": country.code,
        "inputs": zip(tool.fields, inputs).map { field, line in
          let value = field.isSelect ? values[field.name] ?? 0 : engine.toDisplay(values[field.name] ?? 0, unit: field.unit)
          return ["name": field.name, "label": line.label, "value": (value * 1000).rounded() / 1000, "text": line.value] as [String: Any]
        },
        "result": [
          "heading": tool.eyebrow,
          "value": result.primary,
          "label": result.label,
          "number": result.metric?.value as Any,
          "details": result.lines.map { ["label": $0.label, "value": $0.value] },
          "note": result.note,
        ] as [String: Any],
      ])
    }
    print(bold(calculator.title))
    print()
    print(bold("Inputs"))
    rows(inputs.map { [$0.label, $0.value] }, indent: 2)
    print()
    print(bold(tool.eyebrow))
    print("  \(bold(result.primary)) \(result.label)")
    if !result.lines.isEmpty {
      print()
      rows(result.lines.map { [$0.label, $0.value] }, indent: 2)
    }
    if !result.note.isEmpty {
      print()
      print("  \(result.note)")
    }
  }

  // MARK: - Helpers

  private func value(_ text: String, for field: Field) throws -> Double {
    if let options = field.options {
      if let number = Double(text), options.contains(where: { $0.value == number }) { return number }
      if let option = options.first(where: { $0.label.lowercased().hasPrefix(text.lowercased()) }) { return option.value }
      throw CLIError(message: "\(field.name) takes one of: " + options.map { "\(NumberText.format($0.value, locale: Locale(identifier: "en_US"))) (\($0.label))" }.joined(separator: ", "))
    }
    let number = text.filter { $0.isNumber || ".,-−'’".contains($0) }
    guard let display = NumberText.parse(number, locale: locale) else {
      throw CLIError(message: "\"\(text)\" isn't a number for \(field.name).")
    }
    return engine.fromDisplay(display, unit: field.unit)
  }

  private func displayDefault(_ field: Field, _ tool: Tool) -> Double {
    let value = tool.defaults[field.name] ?? 0
    return field.isSelect ? value : engine.toDisplay(value, unit: field.unit)
  }

  private func unit(_ field: Field) -> String? {
    if field.isSelect { return nil }
    return [field.prefix, field.suffix].compactMap { $0 }.joined(separator: " ").nilIfEmpty
  }

  private func count(in category: Category) -> Int {
    catalog.calculators.filter { $0.category == category.slug }.count
  }

  private func find(_ query: String) -> [Calculator] {
    let words = query.lowercased().split(separator: " ")
    return catalog.calculators.filter { calculator in
      let category = catalog.categories.first { $0.slug == calculator.category }?.name ?? ""
      let text = "\(calculator.slug) \(calculator.title) \(calculator.question) \(category)".lowercased()
      return words.allSatisfy { text.contains($0) }
    }
  }

  private func findTool(_ name: String) throws -> (Calculator, Tool) {
    let slug = name.lowercased()
    guard let calculator = catalog.calculators.first(where: { $0.slug == slug || $0.number == slug.leftPadded(to: 3) }) else {
      let words = slug.split(separator: "-").filter { $0.count > 2 }
      let suggestions = catalog.calculators.filter { calculator in words.contains { calculator.slug.contains($0) } }.prefix(5)
      var message = "There's no calculator called \"\(name)\"."
      if !suggestions.isEmpty { message += " Did you mean: \(suggestions.map(\.slug).joined(separator: ", "))?" }
      throw CLIError(message: message + " Find one with calculum search <words>.")
    }
    guard let tool = engine.tool(calculator.slug) else { throw CLIError(message: "\(calculator.title) has no inputs.") }
    return (calculator, tool)
  }

  private func findCategory(_ name: String) throws -> Category {
    let query = name.lowercased()
    if let category = catalog.categories.first(where: { [$0.slug, $0.name.lowercased(), $0.shortName.lowercased()].contains(query) })
      ?? catalog.categories.first(where: { $0.slug.contains(query) || $0.name.lowercased().contains(query) }) {
      return category
    }
    throw CLIError(message: "There's no category called \"\(name)\". See calculum categories.")
  }

  private static func summary(_ calculator: Calculator) -> [String: Any] {
    ["slug": calculator.slug, "title": calculator.title, "category": calculator.category, "question": calculator.question]
  }

  /// Prints columns padded to the widest value, with the last column left as is.
  private func rows(_ rows: [[String]], indent: Int = 0) {
    let columns = rows.map(\.count).max() ?? 0
    let widths = (0..<max(columns - 1, 0)).map { column in rows.map { $0.count > column ? $0[column].count : 0 }.max() ?? 0 }
    for row in rows {
      let padded = row.enumerated().map { index, cell in
        index < widths.count ? cell.padding(toLength: widths[index], withPad: " ", startingAt: 0) : cell
      }
      print(String(repeating: " ", count: indent) + padded.joined(separator: "  "))
    }
  }

  private func output(_ value: Any) {
    let data = try! JSONSerialization.data(withJSONObject: value, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
    print(String(decoding: data, as: UTF8.self))
  }

  static let usage = """
    Number Pantry: 281 everyday calculators on the command line.

    Usage:
      calculum <calculator> [name=value ...]   Calculate. Inputs you leave out keep their example values
      calculum show <calculator>               The inputs, their example values, the formula and the assumptions
      calculum search <words>                  Find calculators
      calculum list [category]                 Every calculator, or the ones in a category
      capabilities                             What the tool can do, and its release history
      calculum categories                      The 20 categories
      calculum countries                       The countries for --country

    Options:
      --country <code>   Currency, number format and units, like US or IT. Defaults to the country set in the app
      --json             Print JSON
      -q, --quiet        Print only the result
      -h, --help         Show this help
      -v, --version      Show the version

    Examples:
      calculum mortgage-payment price=450000 rate=5.5
      calculum tip-and-bill-split bill=186 people=4 -q
      calculum search paint
      calculum show road-trip-fuel-cost
    """
}

extension String {
  var nilIfEmpty: String? { isEmpty ? nil : self }

  func leftPadded(to length: Int) -> String {
    count >= length ? self : String(repeating: "0", count: length - count) + self
  }
}

@MainActor
func printCapabilities(json: Bool) throws {
  let manifest: [String: Any] = [
    "name": "calculum",
    "version": Paths.version,
    "summary": "Run the 281 Number Pantry calculators with country-specific units and formatting.",
    "capabilities": [
      ["description": "Find calculators by name or topic", "command": "calculum search paint"],
      ["description": "List calculators in a category", "command": "calculum list taxes --json"],
      ["description": "Show the inputs and assumptions of a calculator", "command": "calculum show mortgage-payment --json"],
      ["description": "Calculate a result with your inputs", "command": "calculum mortgage-payment price=450000 rate=5.5 --country US"],
      ["description": "Calculate with country-specific units and formatting", "command": "calculum paint-quantity perimeter=52.493 --country US -q"],
      ["description": "List supported countries", "command": "calculum countries --json"]
    ],
    "changelog": [
      ["version": "1.2.0", "date": "2026-10-08", "changes": ["Renamed the app to Number Pantry. The calculum command keeps its existing name.", "New capabilities command lists tasks and release history."]],
      ["version": "1.1.0", "date": "2026-10-03", "changes": ["Signed and notarized Mac release."]],
      ["version": "1.0.0", "date": "2026-10-02", "changes": ["First release: 281 calculators with country-specific units and formatting."]]
    ]
  ]
  if json {
    let data = try JSONSerialization.data(withJSONObject: manifest, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
    print(String(decoding: data, as: UTF8.self))
  } else {
    print("calculum \(Paths.version)\n" + (manifest["summary"] as! String) + "\n\nWhat it can do:")
    for capability in manifest["capabilities"] as! [[String: String]] {
      print("  \(capability["description"]!)\n    $ \(capability["command"]!)")
    }
    print("\nChanges:")
    for release in manifest["changelog"] as! [[String: Any]] {
      print("  \(release["version"]!) (\(release["date"]!))")
      for change in release["changes"] as! [String] { print("    - \(change)") }
    }
  }
}

// MARK: - Main

var arguments = Array(CommandLine.arguments.dropFirst())
var json = false
var quiet = false
var countryCode: String?

@MainActor
func takeFlag(_ names: String...) -> Bool {
  guard let index = arguments.firstIndex(where: names.contains) else { return false }
  arguments.remove(at: index)
  return true
}

do {
  if takeFlag("-h", "--help") || arguments.first == "--help" {
    print(CLI.usage)
    exit(0)
  }
  if takeFlag("-v", "--version") || arguments == ["version"] {
    print("calculum \(Paths.version)")
    exit(0)
  }
  json = takeFlag("--json")
  if arguments.first == "capabilities" {
    try printCapabilities(json: json)
    exit(0)
  }
  quiet = takeFlag("-q", "--quiet")
  if let index = arguments.firstIndex(where: { $0 == "--country" || $0.hasPrefix("--country=") }) {
    let argument = arguments.remove(at: index)
    if argument.hasPrefix("--country=") {
      countryCode = String(argument.dropFirst("--country=".count))
    } else if index < arguments.count {
      countryCode = arguments.remove(at: index)
    } else {
      throw CLIError(message: "--country needs a code, like --country US. See calculum countries.")
    }
  }
  if let unknown = arguments.first(where: { $0.hasPrefix("-") && !$0.contains("=") && Double($0) == nil }) {
    throw CLIError(message: "Unknown option \(unknown). See calculum --help.")
  }

  guard let engineURL = Paths.engine, let source = try? String(contentsOf: engineURL, encoding: .utf8) else {
    throw CLIError(message: "Can't find engine.js. Run calculum from Number Pantry.app/Contents/Helpers, or set CALCULUM_ENGINE.")
  }
  let engine = Engine(source: source)
  let countries = engine.catalog.countries
  let code = (countryCode ?? Paths.appCountry ?? Locale.current.region?.identifier ?? "US").uppercased()
  guard let country = countries.first(where: { $0.code == code }) ?? (countryCode == nil ? countries.first { $0.code == "US" } : nil) else {
    throw CLIError(message: "There's no country \"\(code)\". Pick one of: \(countries.map(\.code).joined(separator: ", "))")
  }
  engine.setCountry(country.code)
  let styled = isatty(STDOUT_FILENO) == 1 && ProcessInfo.processInfo.environment["NO_COLOR"] == nil
  let cli = CLI(engine: engine, country: country, json: json, quiet: quiet) { styled ? "\u{1B}[1m\($0)\u{1B}[0m" : $0 }
  try cli.run(arguments)
} catch let error as CLIError {
  FileHandle.standardError.write(Data("calculum: \(error.message)\n".utf8))
  exit(1)
}
