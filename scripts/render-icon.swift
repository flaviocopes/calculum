#!/usr/bin/env swift
// Renders the app icon into Calculum/AppIcon.icon, an Icon Composer bundle:
// a tilted equals sign, the answer, with a sparkle next to it.
// Layers are flat 1024pt PNGs: macOS adds the Liquid Glass, and Xcode derives the
// icons for older macOS releases from the same bundle.
// Usage: swift scripts/render-icon.swift

import AppKit
import ImageIO
import UniformTypeIdentifiers

// The folder of the app target, relative to the repo root.
let target = "Calculum"

let canvas: CGFloat = 1024
let equalsCenter = CGPoint(x: 486, y: 560)
let equalsTilt: CGFloat = -9
let barLength: CGFloat = 580
let barHeight: CGFloat = 158
let barGap: CGFloat = 92
let sparkleCenter = CGPoint(x: 782, y: 258)
let sparkleRadius: CGFloat = 128

let backgroundTop: UInt32 = 0x2B1C66
let backgroundBottom: UInt32 = 0x7445E0
let darkBackgroundTop: UInt32 = 0x120B30
let darkBackgroundBottom: UInt32 = 0x3A2280
let shapeColor: UInt32 = 0xFFF4DC
let accentColor: UInt32 = 0xFFC83D

func rgb(_ hex: UInt32) -> (red: CGFloat, green: CGFloat, blue: CGFloat) {
  (CGFloat((hex >> 16) & 0xFF) / 255, CGFloat((hex >> 8) & 0xFF) / 255, CGFloat(hex & 0xFF) / 255)
}

func cgColor(_ hex: UInt32) -> CGColor {
  let color = rgb(hex)
  return CGColor(srgbRed: color.red, green: color.green, blue: color.blue, alpha: 1)
}

func iconColor(_ hex: UInt32) -> String {
  let color = rgb(hex)
  return "\"extended-srgb:" + [color.red, color.green, color.blue, 1].map { String(format: "%.5f", $0) }.joined(separator: ",") + "\""
}

// A transparent 1024pt layer with a top-left origin, like the Icon Composer canvas.
func layer(_ draw: (CGContext) -> Void) -> CGImage {
  let context = CGContext(
    data: nil,
    width: Int(canvas),
    height: Int(canvas),
    bitsPerComponent: 8,
    bytesPerRow: 0,
    space: CGColorSpace(name: CGColorSpace.sRGB)!,
    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
  )!
  context.translateBy(x: 0, y: canvas)
  context.scaleBy(x: 1, y: -1)
  draw(context)
  return context.makeImage()!
}

let equals = layer { context in
  context.translateBy(x: equalsCenter.x, y: equalsCenter.y)
  context.rotate(by: equalsTilt * .pi / 180)
  context.setFillColor(cgColor(shapeColor))
  for offset in [-(barGap + barHeight) / 2, (barGap + barHeight) / 2] {
    let bar = CGRect(x: -barLength / 2, y: offset - barHeight / 2, width: barLength, height: barHeight)
    context.addPath(CGPath(roundedRect: bar, cornerWidth: barHeight / 2, cornerHeight: barHeight / 2, transform: nil))
  }
  context.fillPath()
}

// A four-point sparkle with curved sides.
let sparkle = layer { context in
  let c = sparkleCenter
  let r = sparkleRadius
  let pinch = r * 0.16
  context.setFillColor(cgColor(accentColor))
  context.move(to: CGPoint(x: c.x, y: c.y - r))
  context.addQuadCurve(to: CGPoint(x: c.x + r, y: c.y), control: CGPoint(x: c.x + pinch, y: c.y - pinch))
  context.addQuadCurve(to: CGPoint(x: c.x, y: c.y + r), control: CGPoint(x: c.x + pinch, y: c.y + pinch))
  context.addQuadCurve(to: CGPoint(x: c.x - r, y: c.y), control: CGPoint(x: c.x - pinch, y: c.y + pinch))
  context.addQuadCurve(to: CGPoint(x: c.x, y: c.y - r), control: CGPoint(x: c.x - pinch, y: c.y - pinch))
  context.fillPath()
}

// The first group draws on top, and so does the first layer inside a group. Each group
// gets its own glass, shadow and highlight, so parts that should read as separate
// objects go in separate groups.
let manifest = """
{
  "fill-specializations" : [
    { "value" : { "linear-gradient" : [\(iconColor(backgroundTop)), \(iconColor(backgroundBottom))] } },
    { "appearance" : "dark", "value" : { "linear-gradient" : [\(iconColor(darkBackgroundTop)), \(iconColor(darkBackgroundBottom))] } }
  ],
  "groups" : [
    {
      "name" : "Sparkle",
      "layers" : [
        { "name" : "Sparkle", "image-name" : "sparkle.png", "glass" : true }
      ],
      "shadow" : { "kind" : "neutral", "opacity" : 0.5 },
      "specular" : true,
      "translucency" : { "enabled" : true, "value" : 0.3 }
    },
    {
      "name" : "Equals",
      "layers" : [
        { "name" : "Equals", "image-name" : "equals.png", "glass" : true }
      ],
      "shadow" : { "kind" : "neutral", "opacity" : 0.5 },
      "specular" : true,
      "translucency" : { "enabled" : true, "value" : 0.3 }
    }
  ],
  "supported-platforms" : {
    "squares" : ["macOS"]
  }
}

"""

func write(_ image: CGImage, to url: URL) {
  let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)!
  CGImageDestinationAddImage(destination, image, nil)
  guard CGImageDestinationFinalize(destination) else { fatalError("Could not write \(url.path)") }
}

let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
let bundle = root.appendingPathComponent("\(target)/AppIcon.icon")
let assets = bundle.appendingPathComponent("Assets")
try? FileManager.default.removeItem(at: bundle)
try! FileManager.default.createDirectory(at: assets, withIntermediateDirectories: true)
write(equals, to: assets.appendingPathComponent("equals.png"))
write(sparkle, to: assets.appendingPathComponent("sparkle.png"))
try! manifest.write(to: bundle.appendingPathComponent("icon.json"), atomically: true, encoding: .utf8)
print("Wrote \(bundle.path)")
