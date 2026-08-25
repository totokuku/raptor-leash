import AppKit
import SwiftUI

@main
struct RaptorLeashApp: App {
    @StateObject private var agent = RPCServerAgent()

    init() {
        if Self.anotherInstanceIsRunning() {
            exit(0)
        }
        NSApplication.shared.setActivationPolicy(.accessory)
    }

    var body: some Scene {
        MenuBarExtra("Raptor Leash", systemImage: agent.isRunning ? "dot.radiowaves.left.and.right" : "lock") {
            MenuContent(agent: agent)
        }
        .menuBarExtraStyle(.menu)
    }

    private static func anotherInstanceIsRunning() -> Bool {
        guard let bundleID = Bundle.main.bundleIdentifier else { return false }
        let currentPID = ProcessInfo.processInfo.processIdentifier
        return NSWorkspace.shared.runningApplications.contains {
            $0.bundleIdentifier == bundleID && $0.processIdentifier != currentPID
        }
    }
}
