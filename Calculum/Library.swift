import AppKit
import Foundation
import Observation

/// Everything Number Pantry remembers: favorites, recent calculators, saved
/// calculations, the last numbers entered in each calculator, and the country.
/// It lives in one JSON file, `~/Library/Application Support/Calculum/library.json`.
@MainActor
@Observable
final class Library {
  struct Contents: Codable {
    var favorites: [String] = []
    var recents: [String] = []
    var saved: [SavedCalculation] = []
    var inputs: [String: [String: Double]] = [:]
    var country: String?

    init() {}

    /// Missing keys fall back to their defaults, so a file written by an older
    /// version still opens after a newer one adds a key.
    init(from decoder: Decoder) throws {
      let container = try decoder.container(keyedBy: CodingKeys.self)
      favorites = try container.decodeIfPresent([String].self, forKey: .favorites) ?? []
      recents = try container.decodeIfPresent([String].self, forKey: .recents) ?? []
      saved = try container.decodeIfPresent([SavedCalculation].self, forKey: .saved) ?? []
      inputs = try container.decodeIfPresent([String: [String: Double]].self, forKey: .inputs) ?? [:]
      country = try container.decodeIfPresent(String.self, forKey: .country)
    }
  }

  static let maxRecents = 15

  private(set) var contents: Contents
  @ObservationIgnored let fileURL: URL?
  @ObservationIgnored private var saveTask: Task<Void, Never>?

  static var defaultURL: URL {
    URL.applicationSupportDirectory
      .appending(path: "Calculum", directoryHint: .isDirectory)
      .appending(path: "library.json")
  }

  /// Pass `nil` to keep everything in memory, like the screenshot harness does.
  init(fileURL: URL? = Library.defaultURL) {
    self.fileURL = fileURL
    contents = Self.load(from: fileURL)
    guard fileURL != nil else { return }
    NotificationCenter.default.addObserver(forName: NSApplication.willTerminateNotification, object: nil, queue: .main) { [weak self] _ in
      MainActor.assumeIsolated { self?.flush() }
    }
  }

  private static func load(from fileURL: URL?) -> Contents {
    guard let fileURL, let data = try? Data(contentsOf: fileURL) else { return Contents() }
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    if let contents = try? decoder.decode(Contents.self, from: data) { return contents }
    // Keep a file Number Pantry can't read, instead of overwriting it on the next save.
    let backup = fileURL.deletingPathExtension().appendingPathExtension("broken.json")
    try? FileManager.default.removeItem(at: backup)
    try? FileManager.default.moveItem(at: fileURL, to: backup)
    return Contents()
  }

  var favorites: [String] { contents.favorites }
  var recents: [String] { contents.recents }
  var country: String? { contents.country }

  /// Newest first. Calculations are added in the order they're saved, which stays
  /// right even when two share the same second in the file.
  var saved: [SavedCalculation] { contents.saved.reversed() }

  func isFavorite(_ slug: String) -> Bool {
    contents.favorites.contains(slug)
  }

  func toggleFavorite(_ slug: String) {
    if let index = contents.favorites.firstIndex(of: slug) {
      contents.favorites.remove(at: index)
    } else {
      contents.favorites.append(slug)
    }
    save()
  }

  func moveFavorites(from source: IndexSet, to destination: Int) {
    contents.favorites.move(fromOffsets: source, toOffset: destination)
    save()
  }

  func addRecent(_ slug: String) {
    contents.recents.removeAll { $0 == slug }
    contents.recents.insert(slug, at: 0)
    contents.recents = Array(contents.recents.prefix(Self.maxRecents))
    save()
  }

  func clearRecents() {
    contents.recents = []
    save()
  }

  func saved(_ id: SavedCalculation.ID) -> SavedCalculation? {
    contents.saved.first { $0.id == id }
  }

  func addSaved(_ calculation: SavedCalculation) {
    contents.saved.append(calculation)
    save()
  }

  func renameSaved(_ id: SavedCalculation.ID, to name: String) {
    let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty, let index = contents.saved.firstIndex(where: { $0.id == id }) else { return }
    contents.saved[index].name = trimmed
    save()
  }

  func deleteSaved(_ id: SavedCalculation.ID) {
    contents.saved.removeAll { $0.id == id }
    save()
  }

  func inputs(for slug: String) -> [String: Double]? {
    contents.inputs[slug]
  }

  func setInputs(_ values: [String: Double]?, for slug: String) {
    contents.inputs[slug] = values
    save()
  }

  func setCountry(_ code: String) {
    contents.country = code
    save()
  }

  /// Writes the file half a second after the last change, so typing a number
  /// doesn't write it once per keystroke.
  private func save() {
    guard fileURL != nil else { return }
    saveTask?.cancel()
    saveTask = Task { [weak self] in
      try? await Task.sleep(for: .milliseconds(500))
      guard !Task.isCancelled else { return }
      self?.write()
    }
  }

  /// Writes a change that's still waiting, like the last number typed before quitting.
  func flush() {
    guard saveTask != nil else { return }
    write()
  }

  func write() {
    saveTask?.cancel()
    saveTask = nil
    guard let fileURL else { return }
    do {
      try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
      let encoder = JSONEncoder()
      encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
      encoder.dateEncodingStrategy = .iso8601
      try encoder.encode(contents).write(to: fileURL, options: .atomic)
    } catch {
      print("Number Pantry couldn't save its library: \(error.localizedDescription)")
    }
  }
}
