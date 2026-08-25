import Foundation

/// Plain LaunchAgent login item -- no App Store distribution, so no need for
/// the SMAppService ceremony. Same approach as hdmi-defrag and switchboard.
enum LoginItem {
    private static let label = "com.tomkucy.raptorleash"

    private static var plistURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/LaunchAgents/\(label).plist")
    }

    static var isEnabled: Bool {
        FileManager.default.fileExists(atPath: plistURL.path)
    }

    static func setEnabled(_ enabled: Bool) {
        enabled ? install() : uninstall()
    }

    private static func install() {
        guard let executablePath = Bundle.main.executablePath else {
            NSLog("RaptorLeash: no executable path available, cannot install login item")
            return
        }

        let plist: [String: Any] = [
            "Label": label,
            "ProgramArguments": [executablePath],
            "RunAtLoad": true,
            "KeepAlive": false,
            "ProcessType": "Interactive",
        ]

        do {
            let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
            try FileManager.default.createDirectory(
                at: plistURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try data.write(to: plistURL)
            runLaunchctl(["bootstrap", "gui/\(getuid())", plistURL.path])
        } catch {
            NSLog("RaptorLeash: failed to install login item: \(error)")
        }
    }

    private static func uninstall() {
        runLaunchctl(["bootout", "gui/\(getuid())", plistURL.path])
        try? FileManager.default.removeItem(at: plistURL)
    }

    private static func runLaunchctl(_ arguments: [String]) {
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
