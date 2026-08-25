# Raptor Leash — notes for Claude

Menu-bar app that gates CrealityScan's root `RPCServer` LaunchAgent. Read
`README.md` first; it has the full mechanism. This file is the stuff that isn't
obvious from the code.

## Origin

Extracted 2026-08-24 from `~/Documents/Projects/switchboard`, which is a
personal multi-toggle menu-bar app (HDMI flicker fix + Mess Sorter + this).
Raptor Leash is the shareable, single-purpose version.

**Switchboard still contains its own copy** of this logic
(`Sources/Switchboard/CrealityService.swift`) and its own runbook
(`CREALITY-UPDATE.md`). Both apps read the same template path and stage the same
plist, so running both at once means two menu-bar toggles fighting over one
daemon. Pick one; if Raptor Leash is the keeper, strip the Creality section out
of Switchboard's `MenuContent.swift` and `SwitchboardApp.swift`.

## The one idea

launchd auto-loads every plist in `/Library/LaunchAgents` at login and does not
remember a previous `bootout`. So the plist is parked at
`/Library/Creality/com.creality.RPCServer.plist.template` — outside any scanned
directory — and staged into `~/Library/LaunchAgents` only while the toggle is on.
Off deletes it. That is the entire design; everything else is bookkeeping.

## Do not

- Add `SETENV:` to `/etc/sudoers.d/creality_rpcserver`.
- `codesign --remove-signature` on `/Library/Creality/RPCServer`. Its Team ID must
  stay `DMR5SZUGP9`.

Both were only ever needed for `~/Documents/Projects/raptor-scan/rpc-shim`, an
**abandoned** DYLD-injection experiment from 2026-07-17 that logged IOKit traffic
to RE the scanner protocol. It never worked and was deliberately reverted.
`raptor-scan` is *not* the RPCServer tool — this is. If a task starts drifting
toward shims, injection, or sudoers edits, that is the wrong track.

## Traps

- **Every CrealityScan update wipes the template** and reinstalls the always-on
  agent. Expected, not a bug. Fix is `sudo ./scripts/install.sh`, then quit and
  reopen the app — `isAvailable` is only read on `refresh()`.
- **`~/Documents` is TCC-protected.** `swift build` and `sudo cp` fail in here with
  `Operation not permitted` unless the terminal has Full Disk Access. Stage through
  `/tmp` if needed.
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
