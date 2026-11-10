#!/usr/bin/env bash
# Checks dimming end to end on the real built-in display: the real engine, gamma controller and
# activation monitor, with every result read back by `peek`, a separate process that never
# writes gamma. It switches between Terminal and Finder, so it takes over the screen for about
# 30 seconds. Not part of scripts/check.
#
# Exits non-zero on the first wrong reading. Every way out ends the harness, and macOS resets
# a gamma writer's tables when it exits, so the screen is never left dim.
set -euo pipefail
cd "$(dirname "$0")"
swift build -q
bin=.build/debug
work=$(mktemp -d)
mkfifo "$work/in"

"$bin/harness" <"$work/in" >"$work/log" 2>&1 &
harness=$!
exec 3>"$work/in"
cleanup() {
    exec 3>&- || true
    kill -9 "$harness" 2>/dev/null || true
    rm -rf "$work"
}
trap cleanup EXIT

failures=0
expect() { # expect <label> <peak>
    sleep 0.7
    local got
    got=$("$bin/peek" --built-in)
    if [[ "$got" == "$2" ]]; then
        echo "ok    $1: $got"
    else
        echo "FAIL  $1: expected $2, got $got"
        failures=$((failures + 1))
    fi
}

until grep -q READY "$work/log"; do sleep 0.1; done
expect "before" 1.0000
echo "set com.apple.Terminal 0.4" >&3
echo "set com.apple.finder 1.0" >&3
open -b com.apple.Terminal
expect "40% app in front" 0.4000
open -b com.apple.finder
expect "100% app in front" 1.0000
open -b com.apple.Terminal
expect "40% app in front again" 0.4000
echo "--- switch timing (fade; dim by the time the new app's window is in front, brighten only after)"
"$bin/switch-timing" com.apple.finder com.apple.Terminal 2 || failures=$((failures + 1))
expect "40% app in front after switching" 0.4000
echo "activate com.apple.Spotlight" >&3
expect "Spotlight leaves the level" 0.4000
echo "activate cathemeral.harness" >&3
expect "Cathemeral itself leaves the level" 0.4000
echo "set com.apple.Terminal 0.55" >&3
expect "owner's level changes live" 0.5500
echo "set com.apple.Terminal 0.02" >&3
expect "level below the floor" 0.1000
echo "set com.apple.Terminal 0.4" >&3
expect "40% app in front before hiding" 0.4000
echo "hide com.apple.Terminal" >&3
expect "hiding the owner hands the display over (nothing else set, so 100%)" 1.0000
open -b com.apple.Terminal
expect "showing it again" 0.4000
echo "displays-changed" >&3
expect "display change re-captures the original and re-applies" 0.4000
echo "displays-changed" >&3
expect "a second display change doesn't dim twice" 0.4000
echo "suspend" >&3
expect "suspended (screen locked) shows the original curve" 1.0000
echo "set com.apple.Terminal 0.5" >&3
expect "a change while suspended isn't shown" 1.0000
echo "unsuspend" >&3
expect "unlocking re-applies the owner's level" 0.5000
echo "quit" >&3
wait "$harness"
expect "after quit" 1.0000

echo "--- harness log"
cat "$work/log"
exit $((failures > 0))
