import SwiftUI

/// Single binary, two roles:
///   - `LubbyBar hook <event>`  -> tiny CLI invoked by Claude Code hooks; writes
///     the local status file and exits (no GUI).
///   - `LubbyBar`               -> the menu-bar app.
@main
enum Entry {
    static func main() {
        let args = CommandLine.arguments
        if args.count >= 2, args[1] == "hook" {
            HookCLI.run(event: args.count >= 3 ? args[2] : "")
            return
        }
        LubbyBarApp.main()
    }
}
