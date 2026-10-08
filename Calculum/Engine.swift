import Foundation
import JavaScriptCore

/// Runs the calculator modules from calculum.dev, bundled in `engine.js`,
/// in JavaScriptCore. Every call returns JSON, decoded into the models.
@MainActor
final class Engine {
  let catalog: Catalog
  private let context: JSContext
  private let api: JSValue

  convenience init() {
    guard let url = Bundle.main.url(forResource: "engine", withExtension: "js"),
          let source = try? String(contentsOf: url, encoding: .utf8) else {
      fatalError("engine.js is missing from the app bundle. Run scripts/build-engine.sh and rebuild.")
    }
    self.init(source: source)
  }

  init(source: String) {
    context = JSContext()!
    context.exceptionHandler = { _, exception in
      print("Number Pantry engine: \(exception?.toString() ?? "unknown error")")
    }
    context.evaluateScript(source)
    api = context.objectForKeyedSubscript("CalculumEngine")
    let text = api.invokeMethod("catalog", withArguments: [])?.toString() ?? "null"
    guard let catalog = try? JSONDecoder().decode(Catalog.self, from: Data(text.utf8)) else {
      fatalError("engine.js didn't return a catalog. Run swift scripts/check-engine.swift to see why.")
    }
    self.catalog = catalog
  }

  func setCountry(_ code: String) {
    _ = api.invokeMethod("setCountry", withArguments: [code])
  }

  func tool(_ slug: String) -> Tool? {
    decode(call("tool", [slug]))
  }

  func calculate(_ slug: String, _ values: [String: Double]) -> Output? {
    decode(call("calculate", [slug, encode(values)]))
  }

  func sensitivity(_ slug: String, _ values: [String: Double], field: String) -> Sensitivity? {
    decode(call("sensitivity", [slug, encode(values), field]))
  }

  func projection(_ slug: String, _ values: [String: Double]) -> Projection? {
    decode(call("projection", [slug, encode(values)]))
  }

  /// Converts a value from the unit the calculator uses to the one shown,
  /// like metres to feet for the United States.
  func toDisplay(_ value: Double, unit: String) -> Double {
    api.invokeMethod("toDisplay", withArguments: [value, unit])?.toDouble() ?? value
  }

  func fromDisplay(_ value: Double, unit: String) -> Double {
    api.invokeMethod("fromDisplay", withArguments: [value, unit])?.toDouble() ?? value
  }

  private func call(_ name: String, _ arguments: [Any]) -> String {
    api.invokeMethod(name, withArguments: arguments)?.toString() ?? "null"
  }

  private func encode(_ values: [String: Double]) -> String {
    let finite = values.filter { $0.value.isFinite }
    let data = (try? JSONEncoder().encode(finite)) ?? Data("{}".utf8)
    return String(decoding: data, as: UTF8.self)
  }

  private func decode<T: Decodable>(_ text: String) -> T? {
    try? JSONDecoder().decode(T.self, from: Data(text.utf8))
  }
}
