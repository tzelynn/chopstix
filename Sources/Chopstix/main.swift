import AppKit

let arguments = CommandLine.arguments

if let index = arguments.firstIndex(of: "--snapshot"), index + 1 < arguments.count {
    // Dev aid: render the design to PNGs (see specs/chopstix_design.md → Verification).
    _ = NSApplication.shared
    MainActor.assumeIsolated { Snapshots.render(to: URL(fileURLWithPath: arguments[index + 1])) }
    exit(0)
}

if let index = arguments.firstIndex(of: "--export-icon"), index + 1 < arguments.count {
    // Used by scripts/build_app.sh to produce the .icns.
    _ = NSApplication.shared
    MainActor.assumeIsolated { Snapshots.exportIconset(to: URL(fileURLWithPath: arguments[index + 1])) }
    exit(0)
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
