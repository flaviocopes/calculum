// Runs every calculator in Calculum/Resources/engine.js through JavaScriptCore,
// the same runtime the app uses, with its defaults and its examples, for a
// US profile and a metric one. Exits with 1 if any calculator fails.
// Usage: swift scripts/check-engine.swift [path/to/engine.js]
import Foundation
import JavaScriptCore

let path = CommandLine.arguments.dropFirst().first ?? "Calculum/Resources/engine.js"
guard let source = try? String(contentsOfFile: path, encoding: .utf8) else {
  print("Can't read \(path)")
  exit(1)
}

let context = JSContext()!
var exceptions: [String] = []
context.exceptionHandler = { _, value in exceptions.append(value?.toString() ?? "unknown error") }
context.evaluateScript(source)
let engine = context.objectForKeyedSubscript("CalculumEngine")!

func call(_ name: String, _ arguments: [Any]) -> Any? {
  let text = engine.invokeMethod(name, withArguments: arguments)?.toString() ?? "null"
  return try? JSONSerialization.jsonObject(with: Data(text.utf8), options: [.fragmentsAllowed])
}

func valuesJSON(_ values: Any) -> String {
  let data = try! JSONSerialization.data(withJSONObject: values)
  return String(decoding: data, as: UTF8.self)
}

guard let catalog = call("catalog", []) as? [String: Any],
      let calculators = catalog["calculators"] as? [[String: Any]],
      let categories = catalog["categories"] as? [[String: Any]] else {
  print("The engine didn't return a catalog. \(exceptions.joined(separator: "\n"))")
  exit(1)
}

var failures: [String] = []
var charts = 0
var projections = 0

for country in ["US", "IT"] {
  _ = call("setCountry", [country])
  for calculator in calculators {
    let slug = calculator["slug"] as! String
    guard let tool = call("tool", [slug]) as? [String: Any],
          let defaults = tool["defaults"] as? [String: Any],
          let fields = tool["fields"] as? [[String: Any]] else {
      failures.append("\(country) \(slug): no tool")
      continue
    }
    guard let output = call("calculate", [slug, valuesJSON(defaults)]) as? [String: Any],
          let primary = output["primary"] as? String, !primary.isEmpty,
          !primary.contains("NaN"), !primary.contains("undefined") else {
      failures.append("\(country) \(slug): defaults give no result")
      continue
    }
    for example in tool["examples"] as? [[String: Any]] ?? [] {
      var values = defaults
      for (key, value) in example["values"] as? [String: Any] ?? [:] { values[key] = value }
      if call("calculate", [slug, valuesJSON(values)]) as? [String: Any] == nil {
        failures.append("\(country) \(slug): example \"\(example["title"] ?? "")\" gives no result")
      }
    }
    if let field = fields.first(where: { $0["kind"] as? String == "number" })?["name"] as? String,
       call("sensitivity", [slug, valuesJSON(defaults), field]) as? [String: Any] != nil {
      charts += 1
    }
    if tool["hasProjection"] as? Bool == true {
      if call("projection", [slug, valuesJSON(defaults)]) as? [String: Any] != nil {
        projections += 1
      } else {
        failures.append("\(country) \(slug): projection chart missing")
      }
    }
  }
}

if !exceptions.isEmpty { failures.append(contentsOf: exceptions.map { "JavaScript exception: \($0)" }) }

print("\(calculators.count) calculators in \(categories.count) categories, \(charts / 2) with a sensitivity chart, \(projections / 2) with a projection")
if failures.isEmpty {
  print("All calculators work in JavaScriptCore")
} else {
  print(failures.joined(separator: "\n"))
  exit(1)
}
