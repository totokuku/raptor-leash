# Raptor Leash — notes for Claude

Menu-bar app that gates CrealityScan's root `RPCServer` LaunchAgent. Read
`README.md` first; it has the full mechanism. This file is the stuff that isn't
obvious from the code.

## The one idea

launchd auto-loads every plist in `/Library/LaunchAgents` at login and does not
remember a previous `bootout`. So the plist is parked at
`/Library/Creality/com.creality.RPCServer.plist.template` — outside any scanned
directory — and staged into `~/Library/LaunchAgents` only while the toggle is on.
Off deletes it. That is the entire design; everything else is bookkeeping.

## Do not

- Add `SETENV:` to `/etc/sudoers.d/creality_rpcserver`. That would let `DYLD_*`
  through to a `NOPASSWD` root command — strictly worse than the problem being
  solved.
- `codesign --remove-signature` on `/Library/Creality/RPCServer`. Its Team ID must
  stay `DMR5SZUGP9`.

Both are only ever needed to inject a library into the daemon, e.g. to trace its
IOKit traffic and reverse-engineer the USB protocol. That was tried and abandoned:
it doesn't work without weakening both sudo policy and the binary's code identity,
and neither is worth it. If a task starts drifting toward shims, DYLD injection, or
sudoers edits, that is the wrong track — parking the plist is the whole tool.

## Traps

- **Every CrealityScan update wipes the template** and reinstalls the always-on
  agent. Expected, not a bug. Fix is `sudo ./scripts/install.sh`, then quit and
  reopen the app — `isAvailable` is only read on `refresh()`.
- **`~/Documents` is TCC-protected.** `swift build` and `sudo cp` fail from a
  checkout in there with `Operation not permitted` unless the terminal has Full
  Disk Access. Stage through `/tmp` if needed.
- **Root is genuinely required.** The Raptor returns `LIBUSB_ERROR_ACCESS`
  unprivileged even via the public Orbbec SDK (confirmed 2026-07-17). Don't go
  looking for a rootless path; the goal is only to bound *when* root runs.
- **Stray `RPCServer` processes** hold the USB handle exclusively and present as
  "scanner not detected". `pgrep -fl RPCServer`; anything not under `/usr/bin/sudo`
  is stray.

## Layout

```
Sources/RaptorLeash/RPCServerAgent.swift   the leash — template staging + launchctl
Sources/RaptorLeash/MenuContent.swift      menu UI, incl. vendor-agent-is-back warning
Sources/RaptorLeash/RaptorLeashApp.swift   MenuBarExtra, single-instance guard
Sources/RaptorLeash/LoginItem.swift        plain LaunchAgent login item
scripts/install.sh                         parks the plist; --uninstall reverses it
scripts/build-app.sh                       swift build + .app bundle + ad-hoc sign
```

Version-agnostic by design: no CrealityScan version numbers anywhere. The template
is derived from whatever the vendor installer last wrote.
