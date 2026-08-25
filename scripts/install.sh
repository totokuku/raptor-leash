#!/bin/bash
# Raptor Leash -- park Creality's RPCServer LaunchAgent so it stops launching at login.
#
# Run this once after installing CrealityScan, and again after every CrealityScan
# update. See README.md.
#
#   sudo ./install.sh
#   sudo ./install.sh --binary /path/to/pristine/RPCServer
#   sudo ./install.sh --uninstall
#
# The stock .pkg installs an always-on LaunchAgent at
# /Library/LaunchAgents/com.creality.RPCServer.plist. macOS auto-loads anything in
# that directory at every login, so "off" never stays off. Raptor Leash instead wants
# the plist parked at /Library/Creality/com.creality.RPCServer.plist.template, which
# it copies into ~/Library/LaunchAgents on toggle-on and deletes on toggle-off.
#
# This script moves the plist to where Raptor Leash expects it. It is version-agnostic:
# the template is derived from whatever the installer just wrote, so there is nothing
# to update here when Creality ships a new build.

set -euo pipefail

PREFIX=/Library/Creality
SYSTEM_AGENT=/Library/LaunchAgents/com.creality.RPCServer.plist
TEMPLATE="$PREFIX/com.creality.RPCServer.plist.template"
LABEL=com.creality.RPCServer
CREALITY_TEAM_ID=DMR5SZUGP9

[[ $EUID -eq 0 ]] || { echo "error: run with sudo" >&2; exit 1; }
[[ -d "$PREFIX" ]] || { echo "error: $PREFIX missing -- is CrealityScan installed?" >&2; exit 1; }

USER_UID="${SUDO_UID:-$(stat -f %u /dev/console)}"
USER_NAME="$(id -un "$USER_UID")"
USER_HOME="$(dscl . -read "/Users/$USER_NAME" NFSHomeDirectory 2>/dev/null | awk '{print $2}')"
USER_AGENT="${USER_HOME}/Library/LaunchAgents/com.creality.RPCServer.plist"

# ---------------------------------------------------------------- uninstall --
# Hand the machine back to the vendor's always-on arrangement.
if [[ "${1:-}" == "--uninstall" ]]; then
    echo "==> unloading any running RPCServer"
    launchctl bootout "gui/${USER_UID}/${LABEL}" 2>/dev/null || true
    rm -f "$USER_AGENT"

    if [[ -f "$TEMPLATE" ]]; then
        install -m 644 -o root -g wheel "$TEMPLATE" "$SYSTEM_AGENT"
        rm -f "$TEMPLATE"
        launchctl bootstrap "gui/${USER_UID}" "$SYSTEM_AGENT"
        echo "restored the always-on agent at $SYSTEM_AGENT"
    else
        echo "no template to restore from -- reinstall CrealityScan for a clean agent" >&2
    fi
    exit 0
fi

PRISTINE_BINARY=""
if [[ "${1:-}" == "--binary" ]]; then
    PRISTINE_BINARY="${2:-}"
    [[ -f "$PRISTINE_BINARY" ]] || { echo "error: no such file: $PRISTINE_BINARY" >&2; exit 1; }
fi

echo "==> unloading any running RPCServer"
launchctl bootout "gui/${USER_UID}/${LABEL}" 2>/dev/null || true

# Prefer the freshly installed system agent as the template source; fall back to an
# existing template so re-running the script is harmless.
echo "==> establishing template"
if [[ -f "$SYSTEM_AGENT" ]]; then
    install -m 644 -o root -g wheel "$SYSTEM_AGENT" "$TEMPLATE"
    echo "    derived from $SYSTEM_AGENT"
elif [[ -f "$TEMPLATE" ]]; then
    echo "    already present, keeping it"
else
    cat >&2 <<MSG
error: no plist to work from.
       Neither $SYSTEM_AGENT nor
       $TEMPLATE exists.
       Reinstall CrealityScan so the .pkg lays the agent down, then re-run this.
MSG
    exit 1
fi

echo "==> removing always-on agents"
rm -f "$SYSTEM_AGENT"
rm -f "$USER_AGENT"

# An ad-hoc signature here means something re-signed the binary to allow DYLD
# injection. That is not a state to leave the machine in: it strips Creality's
# Developer ID and the hardened runtime. See README, "What this deliberately does not do".
echo "==> checking RPCServer signature"
if [[ -n "$PRISTINE_BINARY" ]]; then
    install -m 755 -o root -g wheel "$PRISTINE_BINARY" "$PREFIX/RPCServer"
    rm -f "$PREFIX/.rpc_shim_signed"
    echo "    restored from $PRISTINE_BINARY"
fi
rm -f "$PREFIX/rpc_shim.dylib"

if codesign -dv "$PREFIX/RPCServer" 2>&1 | grep -q "TeamIdentifier=$CREALITY_TEAM_ID"; then
    echo "    OK -- Creality Developer ID ($CREALITY_TEAM_ID) intact"
else
    cat >&2 <<MSG
    WARNING: RPCServer is not signed by Creality ($CREALITY_TEAM_ID).
             Something re-signed it. Re-run with:
                 --binary /path/to/pristine/RPCServer
             or just reinstall CrealityScan to lay down a clean copy.
MSG
fi

echo
echo "state:"
echo "  template:     $([[ -f "$TEMPLATE" ]] && echo present || echo MISSING)"
echo "  system agent: $([[ -f "$SYSTEM_AGENT" ]] && echo 'STILL PRESENT' || echo removed)"
echo "  user agent:   $([[ -f "$USER_AGENT" ]] && echo 'STILL PRESENT' || echo removed)"
echo "  shim:         $([[ -f "$PREFIX/rpc_shim.dylib" ]] && echo 'STILL PRESENT' || echo absent)"
echo
echo "Now quit and reopen Raptor Leash, then flip the toggle on to test."
