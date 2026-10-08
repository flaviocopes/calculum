import AppKit
import SwiftUI

@main
struct CalculumApp: App {
  @State private var model = AppModel(engine: Engine(), library: Library())

  init() {
    AppUpdater.shared.start(repository: "flaviocopes/number-pantry")
  }

  var body: some Scene {
    Window("Number Pantry", id: "main") {
      ContentView(model: model)
        .frame(minWidth: 980, minHeight: 620)
    }
    .defaultSize(width: 1320, height: 860)
    .commands {
      CalculumCommands(model: model)
    }

    Settings {
      SettingsView(model: model)
    }
  }
}

struct CalculumCommands: Commands {
  let model: AppModel

  var body: some Commands {
    CommandGroup(after: .appInfo) {
      Button("Check for Updates…") {
        AppUpdater.shared.checkForUpdates()
      }
      Button("Install Command Line Tool…") {
        CommandLineTool.install()
      }
    }
    CommandGroup(replacing: .newItem) {}
    CommandGroup(replacing: .textEditing) {
      Button("Find Calculator") {
        model.focusSearch = true
      }
      .keyboardShortcut("f")
    }
    CommandMenu("Calculator") {
      let session = model.activeSession
      let isFavorite = session.map { model.library.isFavorite($0.calculator.slug) } ?? false
      Button(isFavorite ? "Remove from Favorites" : "Add to Favorites") {
        model.toggleFavorite()
      }
      .keyboardShortcut("d")
      .disabled(session == nil)
      Button("Save Calculation") {
        model.saveCalculation()
      }
      .keyboardShortcut("s")
      .disabled(session?.output == nil)
      Button("Copy Result") {
        model.copyResult()
      }
      .keyboardShortcut("c", modifiers: [.command, .shift])
      .disabled(session?.output == nil)
      Button("Reset Numbers") {
        session?.reset()
      }
      .keyboardShortcut("r")
      .disabled(session == nil)
      Divider()
      Button("Open on calculum.dev") {
        if let url = session?.calculator.webURL { NSWorkspace.shared.open(url) }
      }
      .disabled(session == nil)
    }
  }
}
