#!/usr/bin/env swift
// Renders the README banner, docs/banner.png, at 2x: the icon, the name, a tagline and
// feature chips on the left, the real window on the right, on the warm cream of
// calculum.dev. An .icon is rendered through Icon Composer's ictool, so it has the
// real Liquid Glass. The window is docs/screenshot-light.png, made by scripts/screenshot.sh.
// Usage: swift scripts/render-banner.swift

import AppKit
import SwiftUI

let name = "Calculum"
let tagline = "281 everyday calculators,\nnative on your Mac."
let chips: [(text: String, tone: Color)] = [
  ("Works offline", Color(hex: 0x4FD1A1)),
  ("Saved results", Color(hex: 0x5AA9FF)),
  ("Command line", Color(hex: 0xFFA04D)),
]
let size = CGSize(width: 1280, height: 560)
// Where the window's top-left corner sits, and how much it's scaled down.
let windowOrigin = CGPoint(x: 560, y: 70)
let windowScale: CGFloat = 0.52

// The calculum.dev palette: cream, ink, and the bright category tones.
let backgroundTop = Color(hex: 0xFFF8EC)
let backgroundBottom = Color(hex: 0xF8EDD8)
let ink = Color(hex: 0x1F1A14)
let sun = Color(hex: 0xFFC83D)
let sky = Color(hex: 0x5AA9FF)

let root = URL(filePath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
let iconSource = root.appending(path: "\(name)/AppIcon.icon")
let screenshot = root.appending(path: "docs/screenshot-light.png")
let output = root.appending(path: "docs/banner.png")
// scripts/screenshot.sh leaves a 48pt margin around the window for its shadow.
let shadowMargin: CGFloat = 48

extension Color {
  init(hex: UInt32) {
    self.init(red: Double((hex >> 16) & 0xFF) / 255, green: Double((hex >> 8) & 0xFF) / 255, blue: Double(hex & 0xFF) / 255)
  }
}

func run(_ tool: String, _ arguments: [String]) -> String {
  let process = Process()
  let pipe = Pipe()
  process.executableURL = URL(filePath: tool)
  process.arguments = arguments
  process.standardOutput = pipe
  try! process.run()
  process.waitUntilExit()
  return String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
    .trimmingCharacters(in: .whitespacesAndNewlines)
}

// A PNG icon is used as is. It should already have the squircle and its padding.
func renderIcon() -> NSImage {
  guard iconSource.pathExtension == "icon" else { return NSImage(contentsOf: iconSource)! }
  let developer = run("/usr/bin/xcode-select", ["-p"])
  let ictool = URL(filePath: developer).deletingLastPathComponent()
    .appending(path: "Applications/Icon Composer.app/Contents/Executables/ictool").path
  let file = FileManager.default.temporaryDirectory.appending(path: "\(name)-banner-icon.png")
  _ = run(ictool, [
    iconSource.path, "--export-image", "--output-file", file.path, "--platform", "macOS",
    "--rendition", "Default", "--width", "512", "--height", "512", "--scale", "2",
  ])
  return NSImage(contentsOf: file)!
}

/// A pill like the category filters on calculum.dev: an ink border and a hard shadow.
struct Chip: View {
  let text: String
  let tone: Color

  var body: some View {
    HStack(spacing: 8) {
      Circle()
        .fill(tone)
        .stroke(ink, lineWidth: 1.5)
        .frame(width: 11, height: 11)
      Text(text)
        .font(.system(size: 16, weight: .semibold, design: .rounded))
        .foregroundStyle(ink)
    }
    .padding(.leading, 12)
    .padding(.trailing, 15)
    .padding(.vertical, 8)
    .background(Capsule().fill(.white))
    .overlay(Capsule().strokeBorder(ink, lineWidth: 2))
    .background(Capsule().fill(ink).offset(x: 2.5, y: 2.5))
  }
}

struct Banner: View {
  let icon: NSImage
  let window: NSImage

  var body: some View {
    ZStack(alignment: .topLeading) {
      LinearGradient(colors: [backgroundTop, backgroundBottom], startPoint: .top, endPoint: .bottom)
      RadialGradient(colors: [sun.opacity(0.42), sun.opacity(0)], center: UnitPoint(x: 0.14, y: 0.3), startRadius: 0, endRadius: 380)
      RadialGradient(colors: [sky.opacity(0.22), sky.opacity(0)], center: UnitPoint(x: 0.82, y: 1), startRadius: 0, endRadius: 520)

      // The screenshot is 2x, so its size in points is half its pixels.
      Image(nsImage: window)
        .resizable()
        .interpolation(.high)
        .frame(width: CGFloat(window.representations[0].pixelsWide) / 2 * windowScale, height: CGFloat(window.representations[0].pixelsHigh) / 2 * windowScale)
        .offset(x: windowOrigin.x - shadowMargin * windowScale, y: windowOrigin.y - shadowMargin * windowScale)

      VStack(alignment: .leading, spacing: 0) {
        Image(nsImage: icon)
          .resizable()
          .interpolation(.high)
          .frame(width: 132, height: 132)
          .shadow(color: .black.opacity(0.18), radius: 16, y: 8)
        Text(name)
          .font(.system(size: 78, weight: .heavy, design: .rounded))
          .tracking(-1.8)
          .foregroundStyle(ink)
          .padding(.top, 22)
        Text(tagline)
          .font(.system(size: 27, weight: .regular))
          .lineSpacing(4)
          .foregroundStyle(ink.opacity(0.72))
          .padding(.top, 6)
        HStack(spacing: 12) {
          ForEach(chips, id: \.text) { chip in
            Chip(text: chip.text, tone: chip.tone)
          }
        }
        .padding(.top, 26)
      }
      .offset(x: 84, y: 72)
    }
    .frame(width: size.width, height: size.height)
    .clipShape(.rect(cornerRadius: 28))
  }
}

MainActor.assumeIsolated {
  let renderer = ImageRenderer(content: Banner(icon: renderIcon(), window: NSImage(contentsOf: screenshot)!))
  renderer.scale = 2
  // ImageRenderer produces 16 bits per channel. Redraw at 8 bits for a small PNG.
  let image = renderer.cgImage!
  let context = CGContext(
    data: nil, width: image.width, height: image.height, bitsPerComponent: 8, bytesPerRow: 0,
    space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
  )!
  context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
  let rep = NSBitmapImageRep(cgImage: context.makeImage()!)
  try! rep.representation(using: .png, properties: [:])!.write(to: output)
  print("Wrote \(output.path)")
}
