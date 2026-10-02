// Captures the real app window for the README, in light and dark: a calculator into
// <folder>/screenshot-light.png and -dark.png, a saved calculation into saved-*.png,
// and a comparison into compare-*.png.
// scripts/screenshot.sh compiles it with the app's sources, in place of the @main file.

import AppKit
import SwiftUI

let output = URL(filePath: CommandLine.arguments[1])
let title = "Calculum"
let width: CGFloat = 1320
// nil fits the window to the content's height. Split views and lists need a fixed height.
let height: CGFloat? = 820

@MainActor
enum Demo {
  // Demo data in memory only: the real library.json is never read or written.
  static let model: AppModel = {
    let engineURL = output.deletingLastPathComponent().appending(path: "Calculum/Resources/engine.js")
    let engine = Engine(source: try! String(contentsOf: engineURL, encoding: .utf8))
    let library = Library(fileURL: nil)
    library.setCountry("US")
    for slug in ["mortgage-payment", "tip-and-bill-split", "road-trip-fuel-cost", "paint-quantity"] {
      library.toggleFavorite(slug)
    }
    for slug in ["paint-quantity", "trip-budget", "rent-affordability"] {
      library.addRecent(slug)
    }
    let model = AppModel(engine: engine, library: library)
    model.select("road-trip-fuel-cost")
    model.saveCalculation()
    library.renameSaved(library.saved[0].id, to: "Summer road trip")
    model.select("mortgage-payment")
    model.saveCalculation()
    library.renameSaved(library.saved[0].id, to: "30 years at 6.25%")
    model.session?.apply(["price": 450_000, "down": 90_000, "rate": 5.75, "years": 25])
    model.saveCalculation()
    library.renameSaved(library.saved[0].id, to: "25 years at 5.75%")
    model.session?.reset()
    return model
  }()

  static func content() -> some View {
    ContentView(model: model)
  }

  /// Each scene sets up the window, then gets captured in light and dark.
  static let scenes: [(name: String, prepare: @MainActor () -> Void)] = [
    ("screenshot", {
      model.sidebar = .category("housing-moving")
      model.select("mortgage-payment")
    }),
    ("saved", {
      model.sidebar = .saved
      model.selectedSavedIDs = [model.library.saved[0].id]
    }),
    ("compare", {
      model.sidebar = .saved
      model.selectedSavedIDs = [model.library.saved[0].id, model.library.saved[1].id]
    }),
  ]
}

@main
enum Screenshot {
  @MainActor
  static func main() {
    let app = NSApplication.shared
    app.setActivationPolicy(.regular)
    let host = NSHostingView(rootView: Demo.content().frame(width: width, height: height))
    host.sceneBridgingOptions = [.toolbars, .title]
    let window = ActiveWindow(
      contentRect: CGRect(x: 0, y: 0, width: width, height: height ?? 480),
      styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
      backing: .buffered,
      defer: false
    )
    window.title = title
    window.toolbarStyle = .unified
    window.contentView = host
    window.center()
    _ = NotificationCenter.default.addObserver(forName: NSApplication.didFinishLaunchingNotification, object: nil, queue: .main) { _ in
      MainActor.assumeIsolated {
        // Stays in the background, so typing in another app never lands in this window.
        window.orderFrontRegardless()
        Task { await capture(window) }
      }
    }
    app.run()
  }
}

/// Draws as the active window even when another app is frontmost, which is the case
/// when this runs from a terminal: macOS doesn't let it take focus.
final class ActiveWindow: NSWindow {
  override var isKeyWindow: Bool { true }
  override var isMainWindow: Bool { true }
  @objc(_hasActiveAppearance) func hasActiveAppearance() -> Bool { true }
  @objc(_hasActiveAppearanceIgnoringKeyFocus) func hasActiveAppearanceIgnoringKeyFocus() -> Bool { true }
  @objc(_hasKeyAppearance) func hasKeyAppearance() -> Bool { true }
  @objc(_hasMainAppearance) func hasMainAppearance() -> Bool { true }
}

@MainActor
func capture(_ window: NSWindow) async {
  for scene in Demo.scenes {
    scene.prepare()
    try? await Task.sleep(for: .seconds(1.5))
    for (name, appearance) in [("light", NSAppearance.Name.aqua), ("dark", .darkAqua)] {
      NSApp.appearance = NSAppearance(named: appearance)
      try? await Task.sleep(for: .seconds(1))
      if height == nil, let host = window.contentView {
        host.layoutSubtreeIfNeeded()
        window.setContentSize(host.fittingSize)
        window.center()
      }
      try? await Task.sleep(for: .seconds(0.5))
      write(framed(snapshot(window)), to: output.appending(path: "\(scene.name)-\(name).png"))
    }
  }
  NSApp.terminate(nil)
}

/// The whole window, title bar included, at the screen's scale.
@MainActor
func snapshot(_ window: NSWindow) -> CGImage {
  let view = window.contentView!.superview!
  let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds)!
  view.cacheDisplay(in: view.bounds, to: rep)
  return rep.cgImage!
}

/// Rounds the corners like a window and adds a soft shadow on a transparent 48pt margin.
func framed(_ image: CGImage) -> CGImage {
  let scale: CGFloat = 2
  let margin = 48 * scale
  let radius = 10 * scale
  let size = CGSize(width: CGFloat(image.width) + 2 * margin, height: CGFloat(image.height) + 2 * margin)
  let context = CGContext(
    data: nil, width: Int(size.width), height: Int(size.height), bitsPerComponent: 8, bytesPerRow: 0,
    space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
  )!
  let rect = CGRect(x: margin, y: margin, width: CGFloat(image.width), height: CGFloat(image.height))
  let window = CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil)

  context.saveGState()
  context.setShadow(offset: CGSize(width: 0, height: -12 * scale), blur: 36 * scale, color: CGColor(gray: 0, alpha: 0.32))
  context.addPath(window)
  context.setFillColor(CGColor(gray: 0.5, alpha: 1))
  context.fillPath()
  context.restoreGState()

  context.addPath(window)
  context.clip()
  context.draw(image, in: rect)
  context.resetClip()
  context.addPath(window)
  context.setStrokeColor(CGColor(gray: 0, alpha: 0.18))
  context.setLineWidth(1)
  context.strokePath()
  return context.makeImage()!
}

func write(_ image: CGImage, to url: URL) {
  let rep = NSBitmapImageRep(cgImage: image)
  try! rep.representation(using: .png, properties: [:])!.write(to: url)
  print(url.path)
}
