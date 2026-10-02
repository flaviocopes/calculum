import SwiftUI

struct CalculatorView: View {
  let model: AppModel
  @Bindable var session: Session
  @State private var width: CGFloat = 900

  private var calculator: Calculator { session.calculator }
  private var tone: Color { Theme.tone(calculator.category) }
  private var isFavorite: Bool { model.library.isFavorite(calculator.slug) }

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 20) {
        header

        if width > 820 {
          HStack(alignment: .top, spacing: 20) {
            InputsCard(model: model, session: session)
            ResultCard(model: model, session: session)
              .frame(width: min(380, width * 0.4))
          }
        } else {
          InputsCard(model: model, session: session)
          ResultCard(model: model, session: session)
        }

        if session.tool.financial {
          Text(model.catalog.financialNotice.prefix(1).uppercased() + model.catalog.financialNotice.dropFirst() + ".")
            .font(.callout)
            .foregroundStyle(.secondary)
        }

        ChartsCard(model: model, session: session)
        if let projection = session.projection {
          ProjectionCard(projection: projection, country: model.country, locale: model.locale)
        }
        if !session.tool.examples.isEmpty {
          ExamplesCard(session: session)
        }
        MethodCard(tool: session.tool)
        if let guide = session.tool.guide {
          GuideCard(guide: guide, tone: tone)
        }
        if let context = session.tool.context {
          ContextCard(context: context, tone: tone)
        }
        if !session.tool.sources.isEmpty {
          SourcesCard(sources: session.tool.sources)
        }

        Text("Estimates, not guarantees. Check the inputs, the assumptions and your local rules before acting on a result.")
          .font(.footnote)
          .foregroundStyle(.secondary)
          .padding(.top, 4)
      }
      .padding(28)
      .frame(maxWidth: 1080, alignment: .leading)
      .frame(maxWidth: .infinity)
    }
    .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
    .navigationTitle(calculator.title)
    .toolbar {
      ToolbarItemGroup {
        Button {
          model.library.toggleFavorite(calculator.slug)
        } label: {
          Label(isFavorite ? "Remove from Favorites" : "Add to Favorites", systemImage: isFavorite ? "star.fill" : "star")
        }
        .help(isFavorite ? "Remove from Favorites (⌘D)" : "Add to Favorites (⌘D)")
        Button {
          model.saveCalculation()
        } label: {
          Label("Save Calculation", systemImage: "bookmark")
        }
        .help("Save the inputs and the result (⌘S)")
        Link(destination: calculator.webURL) {
          Label("Open on calculum.dev", systemImage: "safari")
        }
        .help("Open this calculator on calculum.dev")
      }
    }
  }

  private var header: some View {
    VStack(alignment: .leading, spacing: 10) {
      HStack(spacing: 8) {
        CategoryIcon(category: calculator.category, size: 22)
        Text(model.category(calculator.category)?.name ?? "")
          .font(.callout.weight(.semibold))
        Text("#\(calculator.number)")
          .font(.callout.monospacedDigit())
          .foregroundStyle(.secondary)
      }
      Text(calculator.title)
        .font(.system(size: 38, weight: .heavy, design: .rounded))
        .fixedSize(horizontal: false, vertical: true)
      Text(calculator.question)
        .font(.title3)
        .foregroundStyle(.secondary)
        .fixedSize(horizontal: false, vertical: true)
    }
    .padding(.bottom, 4)
  }
}

struct InputsCard: View {
  let model: AppModel
  @Bindable var session: Session

  var body: some View {
    VStack(alignment: .leading, spacing: 16) {
      HStack {
        Text("Your numbers")
          .font(.system(.headline, design: .rounded))
        Spacer()
        Button("Reset") { session.reset() }
          .buttonStyle(.borderless)
          .disabled(session.matches(session.tool.defaults))
          .help("Go back to the example numbers (⌘R)")
      }
      LazyVGrid(columns: [GridItem(.adaptive(minimum: 210), spacing: 16, alignment: .top)], alignment: .leading, spacing: 16) {
        ForEach(session.tool.fields) { field in
          if field.isSelect {
            SelectField(field: field, session: session)
          } else {
            NumberField(field: field, session: session, locale: model.locale, tone: Theme.tone(session.calculator.category))
          }
        }
      }
    }
    .padding(22)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(Color(nsColor: .separatorColor)))
  }
}

struct NumberField: View {
  let field: Field
  @Bindable var session: Session
  let locale: Locale
  let tone: Color
  @State private var text = ""
  @State private var shownText = ""
  @FocusState private var focused: Bool

  var body: some View {
    VStack(alignment: .leading, spacing: 6) {
      Text(field.label)
        .font(.callout.weight(.medium))
        .foregroundStyle(.secondary)
        .lineLimit(2, reservesSpace: false)
      HStack(spacing: 6) {
        if let prefix = field.prefix {
          Text(prefix).foregroundStyle(.secondary)
        }
        TextField(field.label, text: $text)
          .labelsHidden()
          .textFieldStyle(.plain)
          .font(.system(.title3, design: .rounded, weight: .semibold).monospacedDigit())
          .focused($focused)
          .onChange(of: text) { commit() }
          .onSubmit { sync() }
          .onKeyPress(.upArrow, phases: .down) { step(by: 1, $0.modifiers) }
          .onKeyPress(.downArrow, phases: .down) { step(by: -1, $0.modifiers) }
        if let suffix = field.suffix {
          Text(suffix)
            .foregroundStyle(.secondary)
            .lineLimit(1)
        }
      }
      .padding(.horizontal, 12)
      .frame(height: 40)
      .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
      .overlay(
        RoundedRectangle(cornerRadius: 10, style: .continuous)
          .strokeBorder(focused ? tone : Color(nsColor: .separatorColor), lineWidth: focused ? 2.5 : 1)
      )
      .contentShape(Rectangle())
      .onTapGesture { focused = true }
    }
    .onAppear { sync() }
    .onChange(of: session.revision) { sync() }
    .onChange(of: focused) { if !focused { sync() } }
  }

  private func sync() {
    shownText = NumberText.format(session.displayValue(of: field), locale: locale)
    text = shownText
  }

  /// Only an edit changes the value. Showing a converted value, like 528.166 mi,
  /// and reading it back would otherwise round the stored one.
  private func commit() {
    guard text != shownText, let value = NumberText.parse(text, locale: locale) else { return }
    session.setDisplayValue(value, for: field)
    shownText = text
  }

  private func step(by direction: Double, _ modifiers: EventModifiers) -> KeyPress.Result {
    let base = field.step ?? 1
    let amount = modifiers.contains(.shift) ? base * 10 : base
    let value = (NumberText.parse(text, locale: locale) ?? session.displayValue(of: field)) + direction * amount
    text = NumberText.format(value, locale: locale)
    return .handled
  }
}

struct SelectField: View {
  let field: Field
  @Bindable var session: Session

  var body: some View {
    VStack(alignment: .leading, spacing: 6) {
      Text(field.label)
        .font(.callout.weight(.medium))
        .foregroundStyle(.secondary)
      Picker(field.label, selection: Binding(get: { session.value(of: field) }, set: { session.set($0, for: field) })) {
        ForEach(field.options ?? [], id: \.value) { option in
          Text(option.label).tag(option.value)
        }
      }
      .labelsHidden()
      .pickerStyle(.menu)
      .frame(height: 40)
    }
  }
}

struct ResultCard: View {
  let model: AppModel
  @Bindable var session: Session
  @State private var justSaved = false

  var body: some View {
    let output = session.output
    ResultPanel(
      eyebrow: session.tool.eyebrow,
      primary: output?.primary,
      label: output?.label ?? "",
      details: output?.lines ?? [],
      note: output?.note ?? "",
      tone: Theme.tone(session.calculator.category)
    ) {
      HStack(spacing: 8) {
        Button { model.copyResult() } label: { Label("Copy", systemImage: "doc.on.doc") }
          .help("Copy the result (⇧⌘C)")
        Button { model.saveCalculation() } label: {
          Label(justSaved ? "Saved" : "Save", systemImage: justSaved ? "checkmark" : "bookmark")
        }
        .help("Save the inputs and the result (⌘S)")
      }
      .buttonStyle(InkButtonStyle())
    }
    .task(id: model.lastSavedAt) {
      guard let date = model.lastSavedAt, Date.now.timeIntervalSince(date) < 1 else { return }
      withAnimation(.snappy) { justSaved = true }
      try? await Task.sleep(for: .seconds(1.6))
      withAnimation(.snappy) { justSaved = false }
    }
  }
}

/// The bright result card, used by the calculator and by saved calculations.
struct ResultPanel<Actions: View>: View {
  let eyebrow: String
  let primary: String?
  let label: String
  let details: [SavedCalculation.Line]
  let note: String
  let tone: Color
  @ViewBuilder var actions: Actions

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      Text(eyebrow)
        .font(.callout.weight(.semibold))
        .foregroundStyle(Theme.ink.opacity(0.72))

      Text(primary ?? "—")
        .font(.system(size: 50, weight: .heavy, design: .rounded))
        .contentTransition(.numericText())
        .lineLimit(1)
        .minimumScaleFactor(0.35)
        .padding(.top, 8)
        .textSelection(.enabled)
      Text(label)
        .font(.body.weight(.medium))
        .foregroundStyle(Theme.ink.opacity(0.75))
        .padding(.top, 2)

      if !details.isEmpty {
        VStack(spacing: 0) {
          ForEach(Array(details.enumerated()), id: \.offset) { _, detail in
            HStack(alignment: .firstTextBaseline, spacing: 12) {
              Text(detail.label)
                .foregroundStyle(Theme.ink.opacity(0.75))
              Spacer(minLength: 8)
              Text(detail.value)
                .fontWeight(.semibold)
                .monospacedDigit()
                .multilineTextAlignment(.trailing)
                .contentTransition(.numericText())
            }
            .padding(.vertical, 9)
            .overlay(alignment: .top) { Rectangle().fill(Theme.ink.opacity(0.14)).frame(height: 1) }
          }
        }
        .padding(.top, 16)
        .textSelection(.enabled)
      }

      if !note.isEmpty {
        Text(note)
          .font(.callout)
          .padding(12)
          .frame(maxWidth: .infinity, alignment: .leading)
          .background(Theme.ink.opacity(0.08), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
          .padding(.top, 12)
      }

      actions
        .padding(.top, 18)
    }
    .foregroundStyle(Theme.ink)
    .padding(22)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(tone, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    .environment(\.colorScheme, .light)
  }
}

/// A small dark capsule button that reads well on the bright result card.
struct InkButtonStyle: ButtonStyle {
  func makeBody(configuration: Configuration) -> some View {
    configuration.label
      .font(.callout.weight(.semibold))
      .foregroundStyle(Color.white)
      .padding(.horizontal, 12)
      .padding(.vertical, 6)
      .background(Theme.ink.opacity(configuration.isPressed ? 0.7 : 1), in: Capsule())
      .scaleEffect(configuration.isPressed ? 0.96 : 1)
      .animation(.snappy(duration: 0.15), value: configuration.isPressed)
  }
}
