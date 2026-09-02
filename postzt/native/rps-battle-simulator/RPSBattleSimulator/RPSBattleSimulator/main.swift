import Foundation
import AppKit

// Top-level entry point. A `--headless` invocation runs the CLI export and exits
// before SwiftUI builds a window; anything else launches the normal GUI app.
let arguments = CommandLine.arguments

if arguments.contains("--headless") {
    exit(HeadlessRunner.run(arguments: arguments))
}

RPSBattleSimulatorApp.main()
