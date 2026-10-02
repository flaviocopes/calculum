import SwiftUI

struct ContentView: View {
  @Bindable var model: AppModel

  var body: some View {
    NavigationSplitView {
      SidebarView(model: model)
        .navigationSplitViewColumnWidth(min: 200, ideal: 220, max: 300)
    } content: {
      CalculatorList(model: model)
        .navigationSplitViewColumnWidth(min: 280, ideal: 330, max: 440)
    } detail: {
      if model.showsSaved {
        switch model.savedDetail {
        case .nothing:
          ContentUnavailableView {
            Label("Pick a saved calculation", systemImage: "bookmark")
          } description: {
            Text("Each one keeps the inputs and the result from when you saved it. ⌘-click two from the same calculator to compare them.")
          }
        case .one(let calculation):
          SavedCalculationView(model: model, calculation: calculation)
            .id(calculation.id)
        case .comparison(let comparison):
          ComparisonView(model: model, comparison: comparison)
        case .differentCalculators:
          ContentUnavailableView {
            Label("These come from different calculators", systemImage: "arrow.left.arrow.right")
          } description: {
            Text("Compare works with two calculations from the same calculator.")
          }
        case .tooMany(let count):
          ContentUnavailableView {
            Label("\(count) calculations selected", systemImage: "arrow.left.arrow.right")
          } description: {
            Text("Select two calculations from the same calculator to compare them.")
          }
        }
      } else if let session = model.session {
        CalculatorView(model: model, session: session)
          .id(session.calculator.slug)
      } else {
        ContentUnavailableView {
          Label("Pick a calculator", systemImage: "equal.square")
        } description: {
          Text("Choose one from the list, or search all \(model.catalog.calculators.count) calculators with ⌘F.")
        }
      }
    }
    .onChange(of: model.sidebar) {
      model.search = ""
    }
  }
}

struct SidebarView: View {
  @Bindable var model: AppModel

  var body: some View {
    List(selection: $model.sidebar) {
      Section {
        item("All Calculators", symbol: "equal", tone: Theme.sun, count: model.catalog.calculators.count)
          .tag(SidebarItem.all)
        item("Favorites", symbol: "star.fill", tone: Theme.tangerine, count: model.library.favorites.count)
          .tag(SidebarItem.favorites)
        item("Recent", symbol: "clock.fill", tone: Theme.sky, count: model.library.recents.count)
          .tag(SidebarItem.recent)
        item("Saved", symbol: "bookmark.fill", tone: Theme.mint, count: model.library.saved.count)
          .tag(SidebarItem.saved)
      }

      Section("Categories") {
        ForEach(model.catalog.categories) { category in
          Label {
            Text(category.shortName)
          } icon: {
            CategoryIcon(category: category.slug)
          }
          .badge(model.calculators(in: category.slug).count)
          .tag(SidebarItem.category(category.slug))
        }
      }
    }
    .safeAreaInset(edge: .bottom, spacing: 0) {
      CountryPicker(model: model)
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }
  }

  private func item(_ title: String, symbol: String, tone: Color, count: Int) -> some View {
    Label {
      Text(title)
    } icon: {
      ToneIcon(symbol: symbol, tone: tone)
    }
    .badge(count)
  }
}

struct CountryPicker: View {
  let model: AppModel

  var body: some View {
    Picker(selection: Binding(get: { model.country.code }, set: { model.setCountry($0) })) {
      ForEach(model.catalog.countries) { country in
        Text("\(country.name) · \(country.currency)").tag(country.code)
      }
    } label: {
      Image(systemName: "globe")
    }
    .pickerStyle(.menu)
    .help("Currency, number format and units for every calculator")
  }
}

struct CalculatorList: View {
  @Bindable var model: AppModel
  @FocusState private var searchFocused: Bool

  /// Lists that mix categories show each calculator's category icon.
  private var showsIcons: Bool {
    if model.isSearching { return true }
    switch model.sidebar ?? .all {
    case .favorites, .recent, .saved: return true
    case .all, .category: return false
    }
  }

  var body: some View {
    Group {
      if model.showsSaved {
        SavedList(model: model)
      } else {
        calculatorList
      }
    }
    .navigationTitle(model.listTitle)
    .navigationSubtitle(subtitle)
    .searchable(text: $model.search, placement: .toolbar, prompt: "Search \(model.catalog.calculators.count) calculators")
    .searchFocused($searchFocused)
    .onChange(of: model.focusSearch) {
      guard model.focusSearch else { return }
      searchFocused = true
      model.focusSearch = false
    }
  }

  private var subtitle: String {
    let count = model.showsSaved ? model.library.saved.count : model.listCalculators.count
    let noun = model.showsSaved ? "saved calculation" : "calculator"
    return count == 1 ? "1 \(noun)" : "\(count) \(noun)s"
  }

  private var calculatorList: some View {
    let calculators = model.listCalculators
    return List(selection: Binding(get: { model.selection }, set: { model.select($0) })) {
      if model.showsGroupedList {
        ForEach(model.catalog.categories) { category in
          Section(category.name) {
            ForEach(model.calculators(in: category.slug)) { calculator in
              row(calculator)
            }
          }
        }
      } else if model.sidebar == .favorites && !model.isSearching {
        ForEach(calculators) { calculator in
          row(calculator)
        }
        .onMove { model.library.moveFavorites(from: $0, to: $1) }
      } else {
        ForEach(calculators) { calculator in
          row(calculator)
        }
      }
    }
    .overlay {
      if calculators.isEmpty { emptyState }
    }
  }

  private func row(_ calculator: Calculator) -> some View {
    CalculatorRow(calculator: calculator, isFavorite: model.library.isFavorite(calculator.slug), showsIcon: showsIcons)
      .tag(calculator.slug)
      .contextMenu {
        Button(model.library.isFavorite(calculator.slug) ? "Remove from Favorites" : "Add to Favorites") {
          model.library.toggleFavorite(calculator.slug)
        }
        Link("Open on calculum.dev", destination: calculator.webURL)
      }
  }

  @ViewBuilder
  private var emptyState: some View {
    if model.isSearching {
      ContentUnavailableView.search(text: model.search)
    } else {
      switch model.sidebar ?? .all {
      case .favorites:
        ContentUnavailableView("No favorites yet", systemImage: "star", description: Text("Press ⌘D on a calculator to keep it here."))
      case .recent:
        ContentUnavailableView("Nothing here yet", systemImage: "clock", description: Text("The calculators you open show up here."))
      default:
        EmptyView()
      }
    }
  }
}

struct CalculatorRow: View {
  let calculator: Calculator
  let isFavorite: Bool
  var showsIcon = true

  var body: some View {
    HStack(alignment: .top, spacing: 10) {
      if showsIcon {
        CategoryIcon(category: calculator.category, size: 24)
          .padding(.top, 1)
      }
      VStack(alignment: .leading, spacing: 2) {
        HStack(spacing: 5) {
          Text(calculator.title)
            .font(.body.weight(.semibold))
          if isFavorite {
            Image(systemName: "star.fill")
              .font(.caption2)
              .foregroundStyle(Theme.tangerine)
          }
        }
        Text(calculator.question)
          .font(.callout)
          .foregroundStyle(.secondary)
          .lineLimit(2)
      }
    }
    .padding(.vertical, 4)
  }
}
