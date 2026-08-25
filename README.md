# Raptor Leash

A macOS menu-bar toggle that keeps CrealityScan's root `RPCServer` daemon off
until you actually need it, and makes "off" survive a reboot.

Built for the **Creality Raptor** 3D scanner on Apple Silicon. It does not patch,
re-sign, or reverse-engineer anything Creality ships; it only changes *when* the
vendor's own daemon is allowed to run.

---

## What CrealityScan actually installs

Installing CrealityScan does three things that are never surfaced in the UI, never
mentioned at install time, and that persist long after you close the app:

**1. A passwordless root rule.** The installer drops a file into your sudoers
directory:

```
/etc/sudoers.d/creality_rpcserver
```

granting `NOPASSWD` execution of `/Library/Creality/RPCServer`: a standing
permission for one vendor binary to become root without ever asking you again.

**2. A daemon that starts at every login, forever.** It also installs:

```
/Library/LaunchAgents/com.creality.RPCServer.plist
```

which re-execs that binary through `sudo` at every single login. Not when you open
CrealityScan, but *always*. Install the app once, never open it again, and a
vendor-signed root process is still starting on your machine every time you log in,
holding your scanner's USB device.

**3. No way to turn it off that sticks.** There is no preference for this, and the
obvious command doesn't hold:

```bash
launchctl bootout gui/$(id -u)/com.creality.RPCServer   # off... until next login
```

macOS bootstraps **everything** sitting in `/Library/LaunchAgents` at each login,
with no memory of a previous session having booted it out. So the daemon silently
comes back. Delete the plist and the next CrealityScan update puts it right back:
the `.pkg` wipes `/Library/Creality` and reinstalls the agent, no questions asked.

## Is it malicious?

Nothing here says yes, and that is worth stating precisely rather than vaguely.
Every claim below is reproducible on your own machine with `codesign`, `otool`,
`nm` and `strings`.

What checks out clean:

- Validly signed by `Developer ID Application: CREALITY 3D (HK) TECHNOLOGY LIMITED
  (DMR5SZUGP9)`, hardened runtime, full Apple chain, timestamped.
- `RPCServer` is `root:wheel 755`, and `/Library/Creality` is writable only by
  `wheel`, which contains root alone. The `NOPASSWD` rule cannot be hijacked by
  swapping the binary out, which is the usual way an arrangement like this turns
  into free root.
- The daemon imports no networking symbols of its own, and holds no URLs,
  hostnames, ports or telemetry strings. It links IOKit, Cocoa, Security, libc++
  and Orbbec's SDK, and at 230 KB it is a thin wrapper around `ob::DeviceList`.
  That matches the job it claims to do.
- Its config pins RPC to `127.0.0.1` with `EnumerateNetDevice` off, and its logs
  hold nothing but scanner discovery traffic.

So the case for putting it on a leash does not rest on intent:

1. **It is root with `KeepAlive` set.** It restarts forever, unsupervised, whether
   or not a scanner is attached.
2. **It hosts a network parser as root.** The bundled SDK runs a GigE Vision
   (GVCP) discovery server that parses UDP inside that root process. Bound to
   loopback today, but that binding is a value in an XML config you do not
   control, and the installer rewrites it on every update.
3. **The trust extends past Creality** to Orbbec, whose bundled 23 MB SDK holds
   all of the socket code.
4. **The app is no tidier.** CrealityScan.app itself, running as you rather than
   root, listens on a wildcard TCP port plus two wildcard UDP ports while open.

A permanent unsupervised root process, hosting a third-party network parser, whose
exposure is set by a file that gets rewritten behind your back, is worth bounding
to the minutes you are actually scanning. That holds whether or not anyone means
harm.

Worth reading yourself, since it is the one part that needs root to inspect:

```bash
sudo cat /etc/sudoers.d/creality_rpcserver
```

### Why the daemon needs root at all

Not a Creality bug, and worth stating because it rules out the easy fix. The Raptor
returns `LIBUSB_ERROR_ACCESS` to an unprivileged process even through the public
Orbbec SDK, and only opens once elevated, a macOS platform gate on this device
class. Confirmed empirically, not assumed. Root is genuinely required; the only
question is *when*.

## How Raptor Leash works

The trick is that launchd can only auto-load a plist it can **find**. So the real
plist is parked somewhere launchd never looks:

```
/Library/Creality/com.creality.RPCServer.plist.template
```

`scripts/install.sh` moves it there and deletes the copy in `/Library/LaunchAgents`.
From then on the menu-bar app owns the daemon's lifetime:

| Toggle | What happens |
| --- | --- |
| **On** | copy the template → `~/Library/LaunchAgents/com.creality.RPCServer.plist`, then `launchctl bootstrap gui/<uid>` it |
| **Off** | `launchctl bootout`, then **delete** the staged plist |

Because "off" leaves no plist on disk in any scanned directory, the next login has
nothing to auto-load. Off stays off. Root runs only while the toggle is on.

The app also watches for `/Library/LaunchAgents/com.creality.RPCServer.plist`
reappearing and warns in the menu when it does. See below.

## Install

Requires macOS 13+, Xcode command line tools, and CrealityScan already installed.

```bash
git clone https://github.com/totokuku/raptor-leash.git
cd raptor-leash
./scripts/build-app.sh
cp -R ".build/Raptor Leash.app" /Applications/
sudo ./scripts/install.sh
```

Then open Raptor Leash from `/Applications` and enable **Launch at Login**.

To hand the machine back to Creality's always-on arrangement:

```bash
sudo ./scripts/install.sh --uninstall
```

## After every CrealityScan update, re-run the installer

**This will break on every update, by design of the vendor's `.pkg`, and it is not
a bug in Raptor Leash.** The installer:

1. wipes `/Library/Creality`, **deleting the template**, and
2. reinstalls the always-on agent in `/Library/LaunchAgents`.

Symptom: the menu reads *Leash not installed* (and flags the vendor agent as back),
while `RPCServer` runs unconditionally at every login again. Fix:

```bash
sudo ./scripts/install.sh
```

Then **quit and reopen the app**. Availability is read on launch and refresh, not
watched, so it won't notice the template reappearing on its own.

The script derives the template from whatever the installer just wrote, so it is
version-agnostic. Nothing to bump when Creality ships a new build.

### Verifying

```bash
ls -la /Library/Creality/com.creality.RPCServer.plist.template   # must exist
ls -la /Library/LaunchAgents/com.creality.RPCServer.plist        # must NOT exist
launchctl list | grep creality                                   # empty when off
```

Toggle on, and `launchctl list | grep creality` should show the job with a PID and
exit code 0, with CrealityScan seeing the scanner.

## What this deliberately does not do

Two tempting paths were tried and rejected. Both weaken the machine's security
posture for no real gain:

- **No `SETENV:` in sudoers.** Adding that tag to
  `/etc/sudoers.d/creality_rpcserver` would let `DYLD_*` variables through to a
  `NOPASSWD` root command. Only ever needed for DYLD injection into the daemon.
- **No re-signing `RPCServer`.** Injection also requires
  `codesign --remove-signature` to drop the hardened runtime, which strips
  Creality's Developer ID (Team ID `DMR5SZUGP9`). `scripts/install.sh` checks the
  signature on every run and warns if it isn't intact.

If you find yourself editing sudoers or re-signing binaries, you are on the wrong
track. Parking the plist is the whole tool.

## Troubleshooting

**"Scanner not detected" with the toggle on.** A stray `RPCServer` holds the USB
handle exclusively. Anything not parented by `/usr/bin/sudo` under launchd is stray:

```bash
pgrep -fl RPCServer
```

**`Operation not permitted` running the scripts.** `~/Documents` is TCC-protected,
so `sudo cp` and `swift build` fail from there unless your terminal has Full Disk
Access. Grant it in System Settings → Privacy & Security → Full Disk Access, or
clone somewhere outside `~/Documents`.

**Menu still says not installed after running the installer.** Quit and reopen the
app.

## License

MIT
