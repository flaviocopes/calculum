import AppKit
import Observation
import SwiftUI

enum SidebarItem: Hashable {
  case all, favorites, recent, saved
  case category(String)
}

/// What the detail column shows for the calculations selected in Saved.
enum SavedDetail {
  case nothing
  case one(SavedCalculation)
  case comparison(Comparison)
  case differentCalculators
  case tooMany(Int)
}

@MainActor
@Observable
final class AppModel {
  let engine: Engine
  let library: Library
  var sidebar: SidebarItem? = .all
  var search = ""
  var focusSearch = false
  var selectedSavedIDs: Set<SavedCalculation.ID> = []
  private(set) var selection: String?
  private(set) var session: Session?
  private(set) var country: Country
  /// When the last calculation was saved, so the Save button can confirm it.
  private(set) var lastSavedAt: Date?
  @ObservationIgnored private let calculatorsBySlug: [String: Calculator]
  @ObservationIgnored private let categoriesBySlug: [String: Category]

  init(engine: Engine, library: Library) {
    self.engine = engine
    self.library = library
    let countries = engine.catalog.countries
    let code = library.country ?? Locale.current.region?.identifier ?? "US"
    country = countries.first { $0.code == code } ?? countries.first { $0.code == "US" } ?? countries[0]
    calculatorsBySlug = Dictionary(uniqueKeysWithValues: engine.catalog.calculators.map { ($0.slug, $0) })
    categoriesBySlug = Dictionary(uniqueKeysWithValues: engine.catalog.categories.map { ($0.slug, $0) })
    engine.setCountry(country.code)
  }

  var catalog: Catalog { engine.catalog }
  var locale: Locale { Locale(identifier: country.locale) }

  func calculator(_ slug: String) -> Calculator? { calculatorsBySlug[slug] }
  func category(_ slug: String) -> Category? { categoriesBySlug[slug] }

  func calculators(in category: String) -> [Calculator] {
    catalog.calculators.filter { $0.category == category }
  }

  var isSearching: Bool { !search.trimmingCharacters(in: .whitespaces).isEmpty }

  /// Saved shows saved calculations, not calculators, in the list and the detail.
  var showsSaved: Bool { !isSearching && sidebar == .saved }

  /// The calculator the Calculator menu acts on: none while Saved is showing.
  var activeSession: Session? { showsSaved ? nil : session }

  var savedDetail: SavedDetail {
    let selected = library.saved.filter { selectedSavedIDs.contains($0.id) }
    switch selected.count {
    case 0: return .nothing
    case 1: return .one(selected[0])
    case 2:
      // The list is newest first, so the older calculation is A.
      guard let comparison = Comparison(selected[1], selected[0], fallbackLocale: locale) else { return .differentCalculators }
      return .comparison(comparison)
    default: return .tooMany(selected.count)
    }
  }

  /// The other saved calculations from the same calculator, to compare with.
  func comparable(with calculation: SavedCalculation) -> [SavedCalculation] {
    library.saved.filter { $0.slug == calculation.slug && $0.id != calculation.id }
  }

  /// The "All Calculators" list is grouped by category. Every other list is flat.
  var showsGroupedList: Bool { !isSearching && (sidebar ?? .all) == .all }

  var listCalculators: [Calculator] {
    if isSearching {
      let words = search.lowercased().split(separator: " ")
      return catalog.calculators.filter { calculator in
        let text = "\(calculator.title) \(calculator.question) \(category(calculator.category)?.name ?? "")".lowercased()
        return words.allSatisfy { text.contains($0) }
      }
    }
    switch sidebar ?? .all {
    case .all: return catalog.calculators
    case .favorites: return library.favorites.compactMap(calculator)
    case .recent: return library.recents.compactMap(calculator)
    case .saved: return []
    case .category(let slug): return calculators(in: slug)
    }
  }

  var listTitle: String {
    if isSearching { return "Search" }
    switch sidebar ?? .all {
    case .all: return "All Calculators"
    case .favorites: return "Favorites"
    case .recent: return "Recent"
    case .saved: return "Saved"
    case .category(let slug): return category(slug)?.name ?? "Calculators"
    }
  }

  func select(_ slug: String?) {
    selection = slug
    guard let slug, session?.calculator.slug != slug else { return }
    guard let calculator = calculator(slug), let tool = engine.tool(slug) else {
      session = nil
      return
    }
    let values = tool.defaults.merging(library.inputs(for: slug) ?? [:]) { $1 }
    session = Session(calculator: calculator, tool: tool, values: values, engine: engine) { [library] values in
      library.setInputs(values, for: slug)
    }
    // Reordering Recent while it's on screen would move the row away from the pointer.
    if sidebar != .recent || isSearching {
      library.addRecent(slug)
    }
  }

  func setCountry(_ code: String) {
    guard let match = catalog.countries.first(where: { $0.code == code }), match != country else { return }
    country = match
    engine.setCountry(code)
    library.setCountry(code)
    session?.reloadTool()
  }

  func toggleFavorite() {
    guard let slug = activeSession?.calculator.slug else { return }
    library.toggleFavorite(slug)
  }

  func saveCalculation() {
    guard let session = activeSession, let output = session.output else { return }
    let calculation = SavedCalculation(
      name: session.calculator.title,
      date: .now,
      slug: session.calculator.slug,
      calculator: session.calculator.title,
      question: session.calculator.question,
      category: session.calculator.category,
      country: country.name,
      inputs: session.inputLines(locale: locale),
      eyebrow: session.tool.eyebrow,
      primary: output.primary,
      label: output.label,
      details: output.lines,
      note: output.note,
      values: session.values,
      locale: country.locale
    )
    library.addSaved(calculation)
    lastSavedAt = calculation.date
  }

  /// Opens the calculator a saved calculation came from, with its numbers.
  func open(_ calculation: SavedCalculation) {
    sidebar = .category(calculation.category)
    select(calculation.slug)
    session?.apply(calculation.values)
  }

  func deleteSaved(_ id: SavedCalculation.ID) {
    deleteSaved([id])
  }

  /// Deletes calculations. When that empties the selection, the next one in the list is selected.
  func deleteSaved(_ ids: Set<SavedCalculation.ID>) {
    let all = library.saved.map(\.id)
    let remaining = all.filter { !ids.contains($0) }
    let wasSelected = !selectedSavedIDs.isDisjoint(with: ids)
    selectedSavedIDs.subtract(ids)
    if wasSelected, selectedSavedIDs.isEmpty, !remaining.isEmpty, let first = all.firstIndex(where: { ids.contains($0) }) {
      selectedSavedIDs = [remaining[min(first, remaining.count - 1)]]
    }
    ids.forEach(library.deleteSaved)
  }

  func copy(_ calculation: SavedCalculation) {
    NSPasteboard.general.clearContents()
    NSPasteboard.general.setString(calculation.summary, forType: .string)
  }

  func copyResult() {
    guard let session = activeSession, let output = session.output else { return }
    var lines = ["\(session.calculator.title): \(output.primary) \(output.label)"]
    lines += output.details.compactMap { $0.count == 2 ? "\($0[0]): \($0[1])" : nil }
    NSPasteboard.general.clearContents()
    NSPasteboard.general.setString(lines.joined(separator: "\n"), forType: .string)
  }
}

/// The calculator that's open: its numbers, its result and its charts.
/// Values are kept in the units the calculator uses, and converted for display.
@MainActor
@Observable
final class Session {
  let calculator: Calculator
  private(set) var tool: Tool
  private(set) var values: [String: Double]
  private(set) var output: Output?
  private(set) var sensitivity: Sensitivity?
  private(set) var projection: Projection?
  private(set) var chartField: String?
  /// Goes up when the numbers change from outside the fields, like loading an
  /// example or switching country, so the fields show the new values.
  private(set) var revision = 0
  @ObservationIgnored private let engine: Engine
  @ObservationIgnored private let onChange: @MainActor ([String: Double]?) -> Void

  init(
    calculator: Calculator,
    tool: Tool,
    values: [String: Double],
    engine: Engine,
    onChange: @escaping @MainActor ([String: Double]?) -> Void
  ) {
    self.calculator = calculator
    self.tool = tool
    self.values = values
    self.engine = engine
    self.onChange = onChange
    recalculate(animated: false)
  }

  var numericFields: [Field] { tool.fields.filter { !$0.isSelect } }

  func value(of field: Field) -> Double {
    values[field.name] ?? tool.defaults[field.name] ?? 0
  }

  func displayValue(of field: Field) -> Double {
    engine.toDisplay(value(of: field), unit: field.unit)
  }

  /// The inputs as they read on screen, like "Home price: $420,000".
  func inputLines(locale: Locale) -> [SavedCalculation.Line] {
    tool.inputLines(values: values, locale: locale) { engine.toDisplay($0, unit: $1) }
  }

  func setDisplayValue(_ display: Double, for field: Field) {
    set(engine.fromDisplay(display, unit: field.unit), for: field)
  }

  func set(_ value: Double, for field: Field) {
    guard value.isFinite, values[field.name].map({ abs($0 - value) > 1e-9 }) ?? true else { return }
    values[field.name] = value
    recalculate(animated: true)
    onChange(values)
  }

  func apply(_ newValues: [String: Double]) {
    values = tool.defaults.merging(newValues) { $1 }
    revision += 1
    recalculate(animated: true)
    onChange(values)
  }

  func reset() {
    values = tool.defaults
    revision += 1
    recalculate(animated: true)
    onChange(nil)
  }

  func matches(_ other: [String: Double]) -> Bool {
    let merged = tool.defaults.merging(other) { $1 }
    return tool.fields.allSatisfy { field in
      abs((merged[field.name] ?? 0) - value(of: field)) < 1e-6
    }
  }

  func output(for other: [String: Double]) -> Output? {
    engine.calculate(calculator.slug, tool.defaults.merging(other) { $1 })
  }

  func setChartField(_ name: String) {
    chartField = name
    sensitivity = engine.sensitivity(calculator.slug, values, field: name)
  }

  /// Reloads labels, units and currency after the country changes.
  func reloadTool() {
    if let tool = engine.tool(calculator.slug) { self.tool = tool }
    revision += 1
    recalculate(animated: false)
  }

  private func recalculate(animated: Bool) {
    let result = engine.calculate(calculator.slug, values)
    if animated {
      withAnimation(.snappy) { output = result }
    } else {
      output = result
    }
    if chartField == nil || !numericFields.contains(where: { $0.name == chartField }) {
      chartField = numericFields.first?.name
    }
    sensitivity = chartField.flatMap { engine.sensitivity(calculator.slug, values, field: $0) }
    projection = tool.hasProjection ? engine.projection(calculator.slug, values) : nil
  }
}
