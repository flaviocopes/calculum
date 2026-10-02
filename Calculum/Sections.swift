import Charts
import SwiftUI

struct ChartsCard: View {
  let model: AppModel
  @Bindable var session: Session
  @State private var hoverX: Double?

  private var tone: Color { Theme.tone(session.calculator.category) }
  private var field: Field? { session.numericFields.first { $0.name == session.chartField } }

  var body: some View {
    SectionCard(title: "What changes the result", subtitle: "Pick an input to see how the result moves when only that one changes. It's a sensitivity view, not a forecast.") {
      if session.numericFields.count > 1 {
        Picker("Input", selection: Binding(get: { session.chartField ?? "" }, set: { session.setChartField($0) })) {
          ForEach(session.numericFields) { field in
            Text(field.label).tag(field.name)
          }
        }
        .pickerStyle(.menu)
        .fixedSize()
      }

      if let sensitivity = session.sensitivity {
        chart(sensitivity)
      } else {
        Text("This result is a category rather than a number, so there's nothing to plot. Compare it with the examples instead.")
          .foregroundStyle(.secondary)
          .frame(maxWidth: .infinity, minHeight: 120)
      }
    }
  }

  private func chart(_ sensitivity: Sensitivity) -> some View {
    let xs = sensitivity.points.map(\.x)
    let ys = sensitivity.points.map(\.y) + [sensitivity.currentY]
    let minX = xs.min() ?? 0
    let maxX = max(xs.max() ?? 1, minX + 1e-9)
    let minY = ys.min() ?? 0
    let maxY = ys.max() ?? 1
    let padding = max((maxY - minY) * 0.08, abs(maxY) * 0.01, 1e-6)
    let lowest = minY - padding
    let hovered = hoverX.flatMap { x in sensitivity.points.min { abs($0.x - x) < abs($1.x - x) } }
    let xLabel = field.map { [$0.label, $0.suffix].compactMap { $0 }.joined(separator: ", ") } ?? "Input"

    return Chart {
      ForEach(sensitivity.points) { point in
        AreaMark(x: .value(xLabel, point.x), yStart: .value("Lowest", lowest), yEnd: .value(sensitivity.metricLabel, point.y))
          .foregroundStyle(LinearGradient(colors: [tone.opacity(0.5), tone.opacity(0.05)], startPoint: .top, endPoint: .bottom))
        LineMark(x: .value(xLabel, point.x), y: .value(sensitivity.metricLabel, point.y))
          .foregroundStyle(Color.primary)
          .lineStyle(StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
      }
      RuleMark(x: .value("Now", sensitivity.currentX))
        .foregroundStyle(.secondary)
        .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
      PointMark(x: .value(xLabel, sensitivity.currentX), y: .value(sensitivity.metricLabel, sensitivity.currentY))
        .symbol {
          Circle()
            .fill(tone)
            .stroke(Theme.ink, lineWidth: 2)
            .frame(width: 14, height: 14)
        }
      if let hovered {
        RuleMark(x: .value("Pointer", hovered.x))
          .foregroundStyle(Color.primary.opacity(0.35))
          .annotation(position: .top, overflowResolution: .init(x: .fit(to: .chart), y: .disabled)) {
            readout(x: hovered.x, y: hovered.y)
          }
      }
    }
    .chartXScale(domain: minX...maxX)
    .chartYScale(domain: lowest...(maxY + padding))
    .chartXAxisLabel(xLabel)
    .chartYAxisLabel(sensitivity.metricLabel)
    .chartXSelection(value: $hoverX)
    .frame(height: 260)
  }

  private func readout(x: Double, y: Double) -> some View {
    VStack(alignment: .leading, spacing: 2) {
      Text([field?.prefix, x.formatted(.number.precision(.fractionLength(0...2)).locale(model.locale)), field?.suffix].compactMap { $0 }.joined(separator: " "))
        .foregroundStyle(.secondary)
      Text(y.formatted(.number.precision(.fractionLength(0...2)).locale(model.locale)))
        .fontWeight(.semibold)
    }
    .font(.caption.monospacedDigit())
    .padding(8)
    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
  }
}

struct ProjectionCard: View {
  let projection: Projection
  let country: Country
  let locale: Locale

  private struct Entry: Identifiable {
    let id: String
    let series: String
    let x: Double
    let y: Double
  }

  private var entries: [Entry] {
    projection.series.flatMap { series in
      projection.points.enumerated().compactMap { index, point in
        point.values[series.key].map { Entry(id: "\(series.key)-\(index)", series: series.label, x: point.x, y: $0) }
      }
    }
  }

  private var ticks: [Double] {
    let points = projection.points
    guard points.count > 1 else { return points.map(\.x) }
    let count = min(5, points.count)
    return (0..<count).map { points[($0 * (points.count - 1)) / (count - 1)].x }
  }

  var body: some View {
    SectionCard(title: projection.title, subtitle: projection.description.isEmpty ? nil : projection.description) {
      Chart(entries) { entry in
        LineMark(x: .value("Time", entry.x), y: .value("Value", entry.y), series: .value("Series", entry.series))
          .foregroundStyle(by: .value("Series", entry.series))
          .lineStyle(StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
      }
      .chartForegroundStyleScale(domain: projection.series.map(\.label), range: Array(Theme.seriesColors.prefix(projection.series.count)))
      .chartXAxis {
        AxisMarks(values: ticks) { value in
          AxisGridLine()
          AxisValueLabel {
            if let x = value.as(Double.self) { Text(label(for: x)) }
          }
        }
      }
      .chartYAxis {
        AxisMarks { value in
          AxisGridLine()
          AxisValueLabel {
            if let y = value.as(Double.self) { Text(format(y)) }
          }
        }
      }
      .chartLegend(position: .top, alignment: .leading)
      .frame(height: 280)

      Text("This carries the calculator's current assumptions forward in time. It's an illustration, not a prediction.")
        .font(.footnote)
        .foregroundStyle(.secondary)
    }
  }

  private func label(for x: Double) -> String {
    projection.points.min { abs($0.x - x) < abs($1.x - x) }?.label ?? ""
  }

  private func format(_ value: Double) -> String {
    if projection.valueType == "money" {
      return value.formatted(.currency(code: country.currency).notation(.compactName).locale(locale))
    }
    return value.formatted(.number.notation(.compactName).locale(locale))
  }
}

struct ExamplesCard: View {
  @Bindable var session: Session

  var body: some View {
    SectionCard(title: "Examples", subtitle: "Start from a realistic example, then change what's different for you.") {
      LazyVGrid(columns: [GridItem(.adaptive(minimum: 230), spacing: 14, alignment: .top)], spacing: 14) {
        ForEach(session.tool.examples, id: \.title) { example in
          card(example)
        }
      }
    }
  }

  private func card(_ example: Example) -> some View {
    let output = session.output(for: example.values)
    let isActive = session.matches(example.values)
    let tone = Theme.tone(session.calculator.category)
    return VStack(alignment: .leading, spacing: 8) {
      Text(example.title)
        .font(.system(.headline, design: .rounded))
      Text(example.description)
        .font(.callout)
        .foregroundStyle(.secondary)
        .fixedSize(horizontal: false, vertical: true)
      Spacer(minLength: 4)
      Text(output?.primary ?? "—")
        .font(.system(.title2, design: .rounded, weight: .heavy).monospacedDigit())
      Text(output?.label ?? "")
        .font(.caption)
        .foregroundStyle(.secondary)
      Button(isActive ? "Showing" : "Use This Example") { session.apply(example.values) }
        .disabled(isActive)
        .padding(.top, 4)
    }
    .padding(16)
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    .background(isActive ? tone.opacity(0.18) : Color(nsColor: .windowBackgroundColor), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    .overlay(
      RoundedRectangle(cornerRadius: 14, style: .continuous)
        .strokeBorder(isActive ? tone : Color(nsColor: .separatorColor), lineWidth: isActive ? 2 : 1)
    )
  }
}

struct MethodCard: View {
  let tool: Tool

  var body: some View {
    SectionCard(title: "How it's calculated") {
      Text(tool.formula)
        .font(.system(.body, design: .monospaced))
        .textSelection(.enabled)
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: .windowBackgroundColor), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
      if !tool.assumptions.isEmpty {
        Text("Assumptions")
          .font(.headline)
        BulletList(items: tool.assumptions)
      }
    }
  }
}

struct GuideCard: View {
  let guide: Guide
  let tone: Color

  var body: some View {
    SectionCard(title: "Guide", subtitle: guide.intro) {
      Grid(alignment: .topLeading, horizontalSpacing: 28, verticalSpacing: 22) {
        GridRow {
          block("How to read the result") { BulletList(items: guide.interpretation) }
          block("Edge cases worth checking") { NoteList(notes: guide.edgeCases, tone: tone) }
        }
        if !guide.drivers.isEmpty || !guide.mistakes.isEmpty {
          GridRow {
            block("What changes the result most") { NoteList(notes: guide.drivers, tone: tone) }
            block("Common mistakes") { NoteList(notes: guide.mistakes, tone: tone) }
          }
        }
        if !guide.useFor.isEmpty || !guide.notFor.isEmpty {
          GridRow {
            block("Use it for") { Text(guide.useFor).foregroundStyle(.secondary) }
            block("Don't use it as") { Text(guide.notFor).foregroundStyle(.secondary) }
          }
        }
      }
      Text(guide.takeaway)
        .font(.callout.weight(.medium))
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(tone.opacity(0.18), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
  }

  private func block<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
    VStack(alignment: .leading, spacing: 8) {
      Text(title).font(.headline)
      content()
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .fixedSize(horizontal: false, vertical: true)
  }
}

struct ContextCard: View {
  let context: CountryContext
  let tone: Color

  var body: some View {
    VStack(alignment: .leading, spacing: 6) {
      Text(context.title)
        .font(.system(.headline, design: .rounded))
      Text(context.body)
        .foregroundStyle(.secondary)
        .fixedSize(horizontal: false, vertical: true)
      if let label = context.sourceLabel, let link = context.sourceURL.flatMap(URL.init(string:)) {
        Link("\(label) ↗", destination: link)
      }
    }
    .padding(20)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(tone.opacity(0.16), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
  }
}

struct SourcesCard: View {
  let sources: [Source]

  var body: some View {
    SectionCard(title: "Sources", subtitle: "These explain the definitions and rules behind this calculator. Check the date and the scope before relying on them.") {
      VStack(alignment: .leading, spacing: 14) {
        ForEach(sources, id: \.url) { source in
          if let url = URL(string: source.url) {
            VStack(alignment: .leading, spacing: 2) {
              Link(destination: url) {
                Text(source.organization ?? source.label ?? source.url)
                  .fontWeight(.semibold)
              }
              Text([source.label, source.scope.map { "Scope: \($0)" }].compactMap { $0 }.joined(separator: " · "))
                .font(.caption)
                .foregroundStyle(.secondary)
              if let note = source.note {
                Text(note)
                  .font(.callout)
                  .foregroundStyle(.secondary)
                  .fixedSize(horizontal: false, vertical: true)
              }
            }
          }
        }
      }
    }
  }
}

struct BulletList: View {
  let items: [String]

  var body: some View {
    VStack(alignment: .leading, spacing: 6) {
      ForEach(items, id: \.self) { item in
        HStack(alignment: .firstTextBaseline, spacing: 8) {
          Text("•").fontWeight(.bold)
          Text(item)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
        }
      }
    }
  }
}

struct NoteList: View {
  let notes: [Guide.Note]
  let tone: Color

  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      ForEach(notes, id: \.title) { note in
        HStack(alignment: .firstTextBaseline, spacing: 8) {
          Circle()
            .fill(tone)
            .stroke(Theme.ink, lineWidth: 1.5)
            .frame(width: 9, height: 9)
          VStack(alignment: .leading, spacing: 2) {
            Text(note.title).fontWeight(.semibold)
            Text(note.body)
              .foregroundStyle(.secondary)
              .fixedSize(horizontal: false, vertical: true)
          }
        }
      }
    }
  }
}
