import AppKit
import SwiftUI

struct SettingsView: View {
  let model: AppModel
  @AppStorage("AppUpdaterAutomaticChecks") private var automaticUpdates = true

  var body: some View {
    Form {
      Section {
        Picker("Country", selection: Binding(get: { model.country.code }, set: { model.setCountry($0) })) {
          ForEach(model.catalog.countries) { country in
            Text("\(country.name) · \(country.currency)").tag(country.code)
          }
        }
      } footer: {
        Text("Sets the currency, the number format and the units, metric or US customary, in every calculator. Number Pantry never converts currencies: you enter the amounts.")
      }

      Section {
        LabeledContent("Favorites", value: "\(model.library.favorites.count)")
        LabeledContent("Saved calculations", value: "\(model.library.saved.count)")
        HStack {
          Button("Show in Finder") {
            model.library.write()
            NSWorkspace.shared.activateFileViewerSelecting([Library.defaultURL])
          }
          Button("Clear Recent") { model.library.clearRecents() }
            .disabled(model.library.recents.isEmpty)
        }
      } header: {
        Text("Your data")
      } footer: {
        Text("Favorites, saved calculations and the numbers you enter stay on this Mac, in one file: library.json.")
      }

      Section {
        Toggle("Check for updates once a day", isOn: $automaticUpdates)
      } header: {
        Text("Updates")
      } footer: {
        Text("Takes effect the next time Number Pantry opens. Number Pantry → Check for Updates… always works.")
      }
    }
    .formStyle(.grouped)
    .frame(width: 480)
    .fixedSize(horizontal: false, vertical: true)
  }
}
