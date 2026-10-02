// Checks the app's models against the real engine. Run it with scripts/test.sh.
import AppKit
import SwiftUI

@main
enum Tests {
  @MainActor
  static func main() async {
    var failures: [String] = []
    func check(_ condition: Bool, _ message: String) {
      print(condition ? "ok   \(message)" : "FAIL \(message)")
      if !condition { failures.append(message) }
    }

    let root = URL(filePath: CommandLine.arguments[1])
    let engine = Engine(source: try! String(contentsOf: root.appending(path: "Calculum/Resources/engine.js"), encoding: .utf8))
    let file = URL.temporaryDirectory.appending(path: "calculum-selftest-\(UUID().uuidString)/library.json")
    let library = Library(fileURL: file)
    library.setCountry("US")
    let model = AppModel(engine: engine, library: library)

    check(model.catalog.calculators.count == 281, "catalog has 281 calculators")
    check(model.country.code == "US", "country starts as US")

    model.select("mortgage-payment")
    guard let session = model.session else { print("FAIL no session"); exit(1) }
    check(session.output?.primary == "$2,068.81", "mortgage default result is $2,068.81 (got \(session.output?.primary ?? "nil"))")
    check(library.recents.first == "mortgage-payment", "opening a calculator adds it to Recent")
    check(session.sensitivity != nil, "mortgage has a sensitivity chart")
    check(session.projection != nil, "mortgage has a projection")

    let price = session.tool.fields.first { $0.name == "price" }!
    session.setDisplayValue(500_000, for: price)
    check(session.output?.primary == "$2,561.38", "changing the home price recalculates (got \(session.output?.primary ?? "nil"))")
    check(library.inputs(for: "mortgage-payment")?["price"] == 500_000, "edited inputs are remembered")

    model.toggleFavorite()
    check(library.isFavorite("mortgage-payment"), "⌘D adds a favorite")
    model.sidebar = .favorites
    check(model.listCalculators.map(\.slug) == ["mortgage-payment"], "Favorites lists the favorite")

    model.saveCalculation()
    check(library.saved.count == 1, "⌘S saves a calculation")
    let saved = library.saved[0]
    check(saved.inputs.map(\.label) == ["Home price", "Down payment", "Annual interest rate", "Loan term"], "the saved calculation lists every input")
    check(saved.inputs.first?.value == "$500,000", "inputs read as they did on screen (got \(saved.inputs.first?.value ?? "nil"))")
    check(saved.inputs[2].value == "6.25%" && saved.inputs[3].value == "30 years", "inputs keep their units (got \(saved.inputs[2].value), \(saved.inputs[3].value))")
    check(saved.primary == "$2,561.38" && saved.label == "principal + interest / month", "the saved calculation keeps the result")
    check(saved.details.contains { $0.label == "Loan amount" && $0.value == "$416,000.00" }, "the saved calculation keeps the result's details")
    check(saved.summary.contains("Home price: $500,000") && saved.summary.contains("$2,561.38"), "Copy puts the inputs and the result in the summary")
    check(model.lastSavedAt == saved.date, "the Save button learns about the save")

    session.reset()
    check(session.output?.primary == "$2,068.81", "reset goes back to the example numbers")
    check(library.inputs(for: "mortgage-payment") == nil, "reset forgets the edited inputs")
    check(library.saved[0].primary == "$2,561.38", "changing the calculator doesn't change what was saved")

    model.sidebar = .saved
    model.selectedSavedIDs = [saved.id]
    check(model.showsSaved && model.activeSession == nil, "Saved shows saved calculations, and the Calculator menu stays off")
    model.saveCalculation()
    check(library.saved.count == 1, "⌘S does nothing while Saved is showing")
    model.open(saved)
    check(model.sidebar == .category("housing-moving") && model.session?.calculator.slug == "mortgage-payment", "Open in Calculator shows the calculator")
    check(session.output?.primary == "$2,561.38" && session.matches(saved.values), "Open in Calculator brings the saved numbers back")

    let rate = session.tool.fields.first { $0.name == "rate" }!
    session.setDisplayValue(5.5, for: rate)
    model.saveCalculation()
    let second = library.saved[0]
    model.select("road-trip-fuel-cost")
    model.saveCalculation()
    let trip = library.saved[0]
    check(model.comparable(with: saved).map(\.id) == [second.id], "Compare With lists the other calculations from the same calculator")

    model.sidebar = .saved
    model.selectedSavedIDs = [second.id, saved.id]
    if case .comparison(let comparison) = model.savedDetail {
      let changedInput = comparison.inputs.first { $0.differs }
      check(comparison.a.id == saved.id && comparison.b.id == second.id, "A is the older calculation, B the newer")
      check(comparison.inputs.filter(\.differs).map(\.label) == ["Annual interest rate"], "only the changed input differs")
      check(changedInput?.change == "−0.75%", "the input change reads −0.75% (got \(changedInput?.change ?? "nil"))")
      check(comparison.change?.hasPrefix("−$") == true && comparison.change?.hasSuffix("%)") == true, "the result change reads like −$199.38 (−7.8%) (got \(comparison.change ?? "nil"))")
      check(comparison.results.first?.label == "Monthly principal and interest" && comparison.results.first?.differs == true, "the main result comes first in the results")
      check(comparison.results.first { $0.label == "Loan amount" }?.differs == false, "unchanged details don't differ")
      check(comparison.summary.contains("Annual interest rate: 6.25% → 5.5% (−0.75%)"), "Copy writes every row with its change")
    } else {
      check(false, "two calculations from the same calculator show a comparison")
    }
    model.selectedSavedIDs = [saved.id, trip.id]
    if case .differentCalculators = model.savedDetail { check(true, "two different calculators can't be compared") } else { check(false, "two different calculators can't be compared") }
    model.selectedSavedIDs = [saved.id, second.id, trip.id]
    if case .tooMany(3) = model.savedDetail { check(true, "three selected asks for two") } else { check(false, "three selected asks for two") }

    let english = Locale(identifier: "en_US")
    let italy = Locale(identifier: "it_IT")
    check(Delta.between("16y 7m", "18y 2m", locale: english, percent: false) == nil, "durations show no change")
    check(Delta.between("1.8 gal", "2.1 gal", locale: english, percent: false) == "+0.3 gal", "units stay in the change")
    let thousands = Delta.between("€420.000", "€450.000", locale: italy, percent: false)
    check(thousands == "+€30.000", "Italian thousands read right (got \(thousands ?? "nil"))")
    let euros = Delta.between("2068,81 €", "2264,78 €", locale: italy, percent: true)
    check(euros == "+195,97 € (+9,5%)", "Italian money changes keep the euro (got \(euros ?? "nil"))")
    model.sidebar = .all
    model.select("mortgage-payment")

    model.search = "split bill"
    check(model.listCalculators.contains { $0.slug == "tip-and-bill-split" }, "search finds the tip and bill split")
    model.search = ""

    model.select("paint-quantity")
    let us = model.session!.output?.primary ?? ""
    let storedBefore = model.session!.values["perimeter"]
    let perimeter = model.session!.tool.fields.first { $0.name == "perimeter" }!
    check(perimeter.suffix == "ft", "US shows feet for the paint perimeter (got \(perimeter.suffix ?? "nil"))")
    model.setCountry("IT")
    let it = model.session!.output?.primary ?? ""
    let metricPerimeter = model.session!.tool.fields.first { $0.name == "perimeter" }!
    check(metricPerimeter.suffix == "m", "Italy shows metres (got \(metricPerimeter.suffix ?? "nil"))")
    check(us.contains("gal") && it.contains("L"), "paint result switches from gallons to litres (\(us) → \(it))")
    check(model.session!.values["perimeter"] == storedBefore && abs(model.session!.displayValue(of: metricPerimeter) - (storedBefore ?? 0)) < 0.001, "the stored value stays the same, only the display changes")

    model.select("mortgage-payment")
    check(model.session!.output?.primary.contains("€") == true, "money shows in euros in Italy (got \(model.session!.output?.primary ?? "nil"))")
    check(model.session!.tool.fields.first { $0.name == "price" }?.prefix == "€", "the currency prefix follows the country")

    check(NumberText.parse("6,25", locale: Locale(identifier: "en_US")) == 6.25, "parses 6,25 as a decimal")
    check(NumberText.parse("1,500", locale: Locale(identifier: "en_US")) == 1500, "parses 1,500 as thousands in the US")
    check(NumberText.parse("1.234,5", locale: Locale(identifier: "it_IT")) == 1234.5, "parses 1.234,5 in Italy")
    check(NumberText.format(6.25, locale: Locale(identifier: "it_IT")) == "6,25", "formats 6,25 for Italy")
    check(NumberText.parse("1.500", locale: Locale(identifier: "it_IT")) == 1500, "parses 1.500 as thousands in Italy")
    check(NumberText.parse("1.500", locale: Locale(identifier: "en_US")) == 1.5, "parses 1.500 as a decimal in the US")
    check(NumberText.parse("0.125", locale: Locale(identifier: "it_IT")) == 0.125, "parses 0.125 as a decimal in Italy")
    check(NumberText.parse("0,125", locale: Locale(identifier: "en_US")) == 0.125, "parses 0,125 as a decimal in the US")
    check(NumberText.parse("1,234,567", locale: Locale(identifier: "en_US")) == 1_234_567, "parses repeated separators as thousands")

    model.sidebar = .recent
    let recentOrder = library.recents
    model.select(recentOrder.last!)
    check(library.recents == recentOrder, "opening a calculator from Recent doesn't reorder the list under the pointer")
    model.sidebar = .all

    library.write()
    let reloaded = Library(fileURL: file)
    check(reloaded.favorites == ["mortgage-payment"], "favorites survive a relaunch")
    check(reloaded.saved.count == 3 && reloaded.saved.last?.values["price"] == 500_000 && reloaded.saved.last?.primary == "$2,561.38", "saved calculations survive a relaunch")
    check(reloaded.saved.last?.locale == "en-US", "saved calculations remember their locale")
    reloaded.renameSaved(reloaded.saved[0].id, to: "  Summer trip ")
    check(reloaded.saved[0].name == "Summer trip", "a saved calculation can be renamed")
    model.selectedSavedIDs = [library.saved[1].id]
    model.deleteSaved(library.saved[1].id)
    check(library.saved.count == 2 && model.selectedSavedIDs.count == 1, "deleting the selected calculation selects the next one")
    model.deleteSaved(Set(library.saved.map(\.id)))
    check(library.saved.isEmpty && model.selectedSavedIDs.isEmpty, "deleting everything clears the selection")
    check(reloaded.country == "IT", "the country survives a relaunch")
    check(reloaded.recents.first == "mortgage-payment", "recents survive a relaunch")

    try! Data("{\"favorites\": [\"paint-quantity\"]}".utf8).write(to: file)
    check(Library(fileURL: file).favorites == ["paint-quantity"], "a file with missing keys still opens")

    try! Data("not json".utf8).write(to: file)
    let fresh = Library(fileURL: file)
    let backup = file.deletingPathExtension().appendingPathExtension("broken.json")
    check(fresh.favorites.isEmpty && FileManager.default.fileExists(atPath: backup.path), "an unreadable file is kept as library.broken.json")
    check(!FileManager.default.fileExists(atPath: file.path), "the unreadable file isn't overwritten")

    try? FileManager.default.removeItem(at: file.deletingLastPathComponent())
    print(failures.isEmpty ? "\nAll checks passed" : "\n\(failures.count) failed")
    exit(failures.isEmpty ? 0 : 1)
  }
}
