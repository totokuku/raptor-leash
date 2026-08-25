import AppKit
import SwiftUI

struct MenuContent: View {
    @ObservedObject var agent: RPCServerAgent

    var body: some View {
        if agent.isAvailable {
            Toggle(
                "Scanner Daemon Running",
                isOn: Binding(get: { agent.isRunning }, set: { agent.setRunning($0) })
            )
            Text(agent.isRunning
                 ? "RPCServer is running as root. Turn off when done scanning."
                 : "Off, and stays off across logins.")
                .font(.caption2)
                .foregroundStyle(.secondary)
        } else {
            Text("Leash not installed")
                .font(.caption)
            Text("Run scripts/install.sh, or CrealityScan isn't installed.")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }

        if agent.systemAgentPresent {
            Divider()
            Text("⚠︎ Vendor agent is back")
                .font(.caption)
            Text("CrealityScan reinstalled its always-on agent. Re-run scripts/install.sh.")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }

        Divider()

        Toggle(
            "Launch at Login",
            isOn: Binding(get: { LoginItem.isEnabled }, set: { LoginItem.setEnabled($0) })
        )

        Button("Refresh Status") { agent.refresh() }

        Button("Quit Raptor Leash") {
            NSApplication.shared.terminate(nil)
        }
        .keyboardShortcut("q")
    }
}
