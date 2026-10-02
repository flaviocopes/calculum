import SwiftUI

/// The middle column while Saved is selected: saved calculations, newest first.
struct SavedList: View {
  @Bindable var model: AppModel

  var body: some View {
    let calculations = model.library.saved
    List(selection: $model.selectedSavedIDs) {
      ForEach(calculations) { calculation in
        SavedRow(calculation: calculation)
          .tag(calculation.id)
          .contextMenu {
            Button("Open in Calculator") { model.open(calculation) }
              .disabled(model.calculator(calculation.slug) == nil)
            Button("Copy") { model.copy(calculation) }
            Divider()
            Button("Delete", role: .destructive) { model.deleteSaved(calculation.id) }
          }
      }
    }
    .onDeleteCommand {
      model.deleteSaved(model.selectedSavedIDs)
    }
    .overlay {
      if calculations.isEmpty {
        ContentUnavailableView("No saved calculations", systemImage: "bookmark", description: Text("Press ⌘S on a calculator to save its inputs and its result here."))
      }
    }
  }
}

struct SavedRow: View {
  let calculation: SavedCalculation

  var body: some View {
    HStack(alignment: .top, spacing: 10) {
      CategoryIcon(category: calculation.category, size: 24)
        .padding(.top, 1)
      VStack(alignment: .leading, spacing: 2) {
        Text(calculation.name)
          .font(.body.weight(.semibold))
          .lineLimit(1)
        HStack(spacing: 5) {
          Text(calculation.primary)
            .fontWeight(.semibold)
            .monospacedDigit()
          Text(calculation.label)
            .foregroundStyle(.secondary)
        }
        .font(.callout)
        .lineLimit(1)
        Text(caption)
          .font(.caption)
          .foregroundStyle(.secondary)
          .lineLimit(1)
      }
    }
    .padding(.vertical, 4)
  }

  private var caption: String {
    let date = calculation.date.formatted(date: .abbreviated, time: .shortened)
    return calculation.name == calculation.calculator ? date : "\(calculation.calculator) · \(date)"
  }
}

/// A saved calculation as a summary: what went in and what came out.
struct SavedCalculationView: View {
  let model: AppModel
  let calculation: SavedCalculation
  @State private var width: CGFloat = 900
  @State private var renaming = false
  @State private var newName = ""

  private var tone: Color { Theme.tone(calculation.category) }
  private var canOpen: Bool { model.calculator(calculation.slug) != nil }

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 20) {
        header

        if width > 820 {
          HStack(alignment: .top, spacing: 20) {
            InputsSummary(inputs: calculation.inputs)
            result
              .frame(width: min(380, width * 0.4))
          }
        } else {
          InputsSummary(inputs: calculation.inputs)
          result
        }

        Text("Saved for \(calculation.country), with the currency, number format and units used then. Opening it in the calculator recalculates it with today's settings.")
          .font(.footnote)
          .foregroundStyle(.secondary)
          .fixedSize(horizontal: false, vertical: true)
      }
      .padding(28)
      .frame(maxWidth: 1080, alignment: .leading)
      .frame(maxWidth: .infinity)
    }
    .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
    .navigationTitle(calculation.name)
    .toolbar {
      ToolbarItemGroup {
        Button {
          model.copy(calculation)
        } label: {
          Label("Copy", systemImage: "doc.on.doc")
        }
        .help("Copy the inputs and the result")
        Button(role: .destructive) {
          model.deleteSaved(calculation.id)
        } label: {
          Label("Delete", systemImage: "trash")
        }
        .help("Delete this saved calculation")
      }
    }
    .alert("Rename Calculation", isPresented: $renaming) {
      TextField("Name", text: $newName)
      Button("Rename") { model.library.renameSaved(calculation.id, to: newName) }
      Button("Cancel", role: .cancel) {}
    }
  }

  private var header: some View {
    VStack(alignment: .leading, spacing: 10) {
      HStack(spacing: 8) {
        CategoryIcon(category: calculation.category, size: 22)
        if calculation.name != calculation.calculator {
          Text(calculation.calculator)
            .font(.callout.weight(.semibold))
        }
        Text(calculation.date.formatted(date: .long, time: .shortened))
          .font(.callout)
          .foregroundStyle(.secondary)
      }
      Text(calculation.name)
        .font(.system(size: 38, weight: .heavy, design: .rounded))
        .fixedSize(horizontal: false, vertical: true)
      Text(calculation.question)
        .font(.title3)
        .foregroundStyle(.secondary)
        .fixedSize(horizontal: false, vertical: true)
      HStack(spacing: 10) {
        Button("Open in Calculator", systemImage: "equal.square") { model.open(calculation) }
          .buttonStyle(.borderedProminent)
          .disabled(!canOpen)
          .help("Open \(calculation.calculator) with these numbers")
        Button("Rename…") {
          newName = calculation.name
          renaming = true
        }
        Button("Copy") { model.copy(calculation) }
        compareMenu
      }
      .controlSize(.large)
      .padding(.top, 6)
    }
    .padding(.bottom, 4)
  }

  private var compareMenu: some View {
    let others = model.comparable(with: calculation)
    return Menu("Compare With…") {
      ForEach(others) { other in
        Button("\(other.name) · \(other.primary) · \(other.date.formatted(date: .abbreviated, time: .shortened))") {
          model.selectedSavedIDs = [calculation.id, other.id]
        }
      }
    }
    .fixedSize()
    .disabled(others.isEmpty)
    .help(others.isEmpty
      ? "Save another \(calculation.calculator) calculation to compare it with this one"
      : "Compare with another \(calculation.calculator) calculation. You can also ⌘-click two in the list.")
  }

  private var result: some View {
    ResultPanel(
      eyebrow: calculation.eyebrow,
      primary: calculation.primary,
      label: calculation.label,
      details: calculation.details,
      note: calculation.note,
      tone: tone
    ) {
      EmptyView()
    }
  }
}

struct InputsSummary: View {
  let inputs: [SavedCalculation.Line]

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      Text("Inputs")
        .font(.system(.headline, design: .rounded))
      VStack(spacing: 0) {
        ForEach(Array(inputs.enumerated()), id: \.offset) { index, input in
          HStack(alignment: .firstTextBaseline, spacing: 16) {
            Text(input.label)
              .foregroundStyle(.secondary)
            Spacer(minLength: 8)
            Text(input.value)
              .font(.system(.title3, design: .rounded, weight: .semibold).monospacedDigit())
              .multilineTextAlignment(.trailing)
          }
          .padding(.vertical, 10)
          .overlay(alignment: .top) {
            if index > 0 { Divider() }
          }
        }
      }
      .textSelection(.enabled)
    }
    .padding(22)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(Color(nsColor: .separatorColor)))
  }
}
