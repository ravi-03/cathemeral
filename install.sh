#!/usr/bin/env bash
# Installs or updates Cathemeral from the latest GitHub Release. No Xcode needed.
#
#   curl -fsSL https://raw.githubusercontent.com/ravi-03/cathemeral/main/install.sh | bash
#   curl -fsSL https://raw.githubusercontent.com/ravi-03/cathemeral/main/install.sh | bash -s -- --uninstall
#
# The release is ad-hoc signed, not notarized. curl sets no quarantine flag, so Gatekeeper lets
# the app open without a warning.
#
# Environment, mainly for testing: CATHEMERAL_VERSION (a tag such as v0.2.0, default the latest
# release), CATHEMERAL_URL (the zip's URL; its .sha256 must sit next to it), CATHEMERAL_DEST (default
# /Applications), CATHEMERAL_NO_OPEN=1 (install without opening).
#
# Everything is inside main, called on the last line, so a download cut short runs nothing.
set -euo pipefail

main() {
    local repo="ravi-03/cathemeral"
    local bundle_id="io.github.ravi-03.cathemeral"
    local dest="${CATHEMERAL_DEST:-/Applications}"
    local app="$dest/Cathemeral.app"

    if [[ "$(uname -s)" != Darwin ]]; then
        fail "Cathemeral runs on macOS only."
    fi
    local major
    major=$(sw_vers -productVersion | cut -d. -f1)
    if ((major < 14)); then
        fail "Cathemeral needs macOS 14 or later (this Mac has $(sw_vers -productVersion))."
    fi

    if [[ "${1:-}" == "--uninstall" ]]; then
        quit_running "$bundle_id"
        rm -rf "$app"
        say "Removed $app."
        say "Your settings are still in ~/Library/Application Support/Cathemeral. Delete that folder to remove them too."
        return
    elif [[ -n "${1:-}" ]]; then
        fail "Unknown option: $1 (the only option is --uninstall)."
    fi

    local url
    if [[ -n "${CATHEMERAL_URL:-}" ]]; then
        url="$CATHEMERAL_URL"
    elif [[ -n "${CATHEMERAL_VERSION:-}" ]]; then
        url="https://github.com/$repo/releases/download/$CATHEMERAL_VERSION/Cathemeral.zip"
    else
        url="https://github.com/$repo/releases/latest/download/Cathemeral.zip"
    fi

    # Global, not local: the EXIT trap runs after main has returned.
    tmp=$(mktemp -d)
    trap 'rm -rf "$tmp"' EXIT

    say "Downloading $url"
    curl -fL --progress-bar -o "$tmp/Cathemeral.zip" "$url" || fail "Download failed."
    curl -fsSL -o "$tmp/Cathemeral.zip.sha256" "$url.sha256" || fail "Checksum download failed."
    (cd "$tmp" && shasum -a 256 -c -s Cathemeral.zip.sha256) || fail "Checksum mismatch: the download is damaged. Try again."

    ditto -x -k "$tmp/Cathemeral.zip" "$tmp/unzipped"
    local new="$tmp/unzipped/Cathemeral.app"
    codesign --verify --strict --deep "$new" 2>/dev/null || fail "The downloaded app's signature is broken."
    if [[ ! -x "$new/Contents/MacOS/GammaWatchdog" ]]; then
        fail "The downloaded app has no watchdog helper, so it couldn't restore the screen if it crashed."
    fi

    # Two copies would both write gamma, so quit the old one first. It restores the screen as it quits.
    quit_running "$bundle_id"

    mkdir -p "$dest"
    [[ -w "$dest" ]] || fail "Can't write to $dest. Run this as an administrator, or set CATHEMERAL_DEST=~/Applications."
    rm -rf "$app"
    ditto "$new" "$app"
    xattr -dr com.apple.quarantine "$app" 2>/dev/null || true

    local version
    version=$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" "$app/Contents/Info.plist")
    say "Installed Cathemeral $version in $app."

    if [[ "${CATHEMERAL_NO_OPEN:-}" != 1 ]]; then
        open "$app"
        say "It's running: look for its icon in the menu bar (there's no Dock icon)."
        say "Turn on Launch at login in its popover to keep it running."
    fi
}

quit_running() {
    pgrep -x Cathemeral >/dev/null || return 0
    say "Quitting the running Cathemeral"
    osascript -e "quit app id \"$1\"" >/dev/null 2>&1 || true
    local i
    for i in {1..50}; do
        pgrep -x Cathemeral >/dev/null || return 0
        sleep 0.1
    done
    fail "Cathemeral didn't quit. Quit it from its menu bar icon, then run this again."
}

say() { printf '==> %s\n' "$*"; }
fail() {
    printf 'Error: %s\n' "$*" >&2
    exit 1
}

main "$@"
