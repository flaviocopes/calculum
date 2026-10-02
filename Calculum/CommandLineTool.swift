import AppKit

/// Installs the calculum command by linking /usr/local/bin/calculum to the copy
/// inside the app, so it stays current when the app updates itself.
@MainActor
enum CommandLineTool {
  static let link = URL(filePath: "/usr/local/bin/calculum")

  static var bundled: URL {
    Bundle.main.bundleURL.appending(path: "Contents/Helpers/calculum")
  }

  static func install() {
    let tool = bundled
    guard FileManager.default.isExecutableFile(atPath: tool.path) else {
      return alert("The calculum command isn't inside this copy of Calculum.", "Download Calculum again from GitHub, or build it with scripts/build-release.sh.")
    }
    guard !tool.path.contains("/AppTranslocation/") else {
      return alert("Move Calculum to your Applications folder first.", "macOS is running it from a temporary location, and the command would stop working.")
    }

    if (try? linkDirectly(to: tool)) != nil {
      return installed()
    }
    // /usr/local/bin belongs to root on most Macs, so ask for an administrator password.
    let path = tool.path.replacingOccurrences(of: "'", with: "'\\''")
    let command = "mkdir -p /usr/local/bin && ln -sf '\(path)' /usr/local/bin/calculum"
    let script = "do shell script \"\(command.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\""))\" with administrator privileges"
    var error: NSDictionary?
    NSAppleScript(source: script)?.executeAndReturnError(&error)
    if error == nil {
      installed()
    } else if (error?[NSAppleScript.errorNumber] as? Int) != -128 {
      alert("Calculum couldn't install the command.", "Run this in Terminal instead:\n\nsudo ln -sf '\(tool.path)' /usr/local/bin/calculum")
    }
  }

  private static func linkDirectly(to tool: URL) throws {
    try FileManager.default.createDirectory(at: link.deletingLastPathComponent(), withIntermediateDirectories: true)
    try? FileManager.default.removeItem(at: link)
    try FileManager.default.createSymbolicLink(at: link, withDestinationURL: tool)
  }

  private static func installed() {
    alert("The calculum command is ready.", "Open a new Terminal window and try:\n\ncalculum mortgage-payment price=450000\ncalculum search paint\ncalculum --help")
  }

  private static func alert(_ message: String, _ information: String) {
    let alert = NSAlert()
    alert.messageText = message
    alert.informativeText = information
    alert.runModal()
  }
}
