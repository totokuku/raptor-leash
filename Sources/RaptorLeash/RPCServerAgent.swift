import Combine
import Foundation

/// The leash itself.
///
/// CrealityScan installs `com.creality.RPCServer.plist` into
/// `/Library/LaunchAgents`, and macOS bootstraps *everything* in that directory
/// at every login regardless of whether a previous session booted it out. So a
/// plain `launchctl bootstrap`/`bootout` toggle only ever holds until the next
/// reboot -- the root daemon quietly comes back on.
///
/// Instead, the real plist is parked at
/// `/Library/Creality/com.creality.RPCServer.plist.template`, outside any
/// directory launchd scans, and copied into `~/Library/LaunchAgents` only while
/// the leash is off. Off therefore stays off across logins: there is no plist
/// anywhere for launchd to find.
///
/// `scripts/install.sh` is what moves the vendor's plist to the template path.
/// Re-run it after every CrealityScan update -- the .pkg wipes
/// `/Library/Creality` and reinstalls the always-on agent.
@MainActor
final class RPCServerAgent: ObservableObject {
    private let templatePath = "/Library/Creality/com.creality.RPCServer.plist.template"
    private let label = "com.creality.RPCServer"

    private var installedPath: String {
        "\(NSHomeDirectory())/Library/LaunchAgents/com.creality.RPCServer.plist"
    }

    /// True while the root daemon is loaded -- i.e. the scanner is usable.
    @Published private(set) var isRunning = false

    /// True once the template exists. False means either CrealityScan isn't
    /// installed, or an update wiped the template and `scripts/install.sh`
    /// needs re-running.
    @Published private(set) var isAvailable = false

    /// Set when the vendor's always-on agent is back in /Library/LaunchAgents.
    /// The daemon is then launching at every login behind the app's back, which
    /// is the exact situation this tool exists to prevent.
    @Published private(set) var systemAgentPresent = false

    init() {
        refresh()
    }

    func refresh() {
        let fm = FileManager.default
        isAvailable = fm.fileExists(atPath: templatePath)
        systemAgentPresent = fm.fileExists(atPath: "/Library/LaunchAgents/\(label).plist")
        guard isAvailable else {
            isRunning = false
            return
        }
        isRunning = fm.fileExists(atPath: installedPath) && isLoaded()
    }

    func setRunning(_ running: Bool) {
        guard isAvailable else { return }
        running ? slip() : leash()
        refresh()
    }

    /// Let the daemon run: stage the plist into the user's LaunchAgents and
    /// bootstrap it into the GUI domain.
    private func slip() {
        let fm = FileManager.default
        do {
            if fm.fileExists(atPath: installedPath) {
                try fm.removeItem(atPath: installedPath)
            }
            try fm.createDirectory(
                atPath: "\(NSHomeDirectory())/Library/LaunchAgents",
                withIntermediateDirectories: true
            )
            try fm.copyItem(atPath: templatePath, toPath: installedPath)
            runLaunchctl(["bootstrap", "gui/\(getuid())", installedPath])
        } catch {
            NSLog("RaptorLeash: failed to stage RPCServer plist: \(error)")
        }
    }

    /// Stop the daemon and remove the staged plist, so nothing survives to be
    /// auto-loaded at the next login.
    private func leash() {
        runLaunchctl(["bootout", "gui/\(getuid())", installedPath])
        try? FileManager.default.removeItem(atPath: installedPath)
    }

    private func isLoaded() -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        process.arguments = ["print", "gui/\(getuid())/\(label)"]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus == 0
        } catch {
            return false
        }
    }

    private func runLaunchctl(_ arguments: [String]) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        process.arguments = arguments
        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            NSLog("RaptorLeash: launchctl \(arguments.joined(separator: " ")) failed: \(error)")
        }
    }
}
