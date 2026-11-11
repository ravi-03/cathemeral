#!/usr/bin/env bash
# Checks dimming end to end on the real built-in display: the real engine, gamma controller and
# activation monitor, with every result read back by `peek`, a separate process that never
# writes gamma. It switches between Terminal and Finder, then checks the safety net (termination
# signals, kill -9, a hang caught by the watchdog, a dead watchdog), so it takes over the screen
# for about a minute. Not part of scripts/check.
#
# Exits non-zero if any reading is wrong. Every way out ends the harness (resuming it first if
# it was stopped), and macOS resets a gamma writer's tables when it exits, so the screen is never
# left dim.
set -euo pipefail
cd "$(dirname "$0")"
swift build -q
bin=.build/debug
work=$(mktemp -d)
# The watchdog is built into the app bundle by Xcode; here it is built straight from its sources.
swiftc -O ../App/GammaWatchdog/*.swift -o "$work/GammaWatchdog"
mkfifo "$work/in"

harness=
runs=0
# Starts a harness with its own log, and waits for it to listen. Commands go to fd 3.
start_harness() {
    runs=$((runs + 1))
    log="$work/log.$runs"
    "$bin/harness" "$work/GammaWatchdog" <"$work/in" >"$log" 2>&1 &
    harness=$!
    exec 3>"$work/in"
    until grep -q READY "$log"; do sleep 0.1; done
}
# Waits for the harness to exit, however it went, and closes its input.
harness_exited() {
    wait "$harness" 2>/dev/null || true
    exec 3>&-
}
watchdog_of() { pgrep -P "$1" GammaWatchdog || true; }
cleanup() {
    exec 3>&- || true
    if [[ -n "$harness" ]]; then
        kill -CONT "$harness" 2>/dev/null || true
        kill -9 "$harness" 2>/dev/null || true
    fi
    pkill -9 -f "$work/GammaWatchdog" 2>/dev/null || true
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

check() { # check <label> <command...>: ok if the command succeeds
    local label=$1
    shift
    if "$@"; then
        echo "ok    $label"
    else
        echo "FAIL  $label"
        failures=$((failures + 1))
    fi
}

is_millis() { [[ $1 =~ ^[0-9]+$ ]]; }

start_harness
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
harness_exited
expect "after quit" 1.0000

echo "--- safety net"
# Dims the built-in display to 40% for Terminal, reported straight to the fresh harness.
dim() {
    echo "set com.apple.Terminal 0.4" >&3
    echo "activate com.apple.Terminal" >&3
    expect "$1: dimmed" 0.4000
}
for sig in TERM INT HUP; do
    start_harness
    dim "SIG$sig"
    kill -"$sig" "$harness"
    harness_exited
    expect "SIG$sig restores before exiting" 1.0000
done

start_harness
dim "kill -9"
watchdog=$(watchdog_of "$harness")
kill -9 "$harness"
harness_exited
expect "kill -9 restores (macOS resets a dead writer)" 1.0000
sleep 0.3
check "the watchdog exits with the app" bash -c "[[ -n '$watchdog' ]] && ! kill -0 '$watchdog' 2>/dev/null"

start_harness
dim "watchdog"
watchdog=$(watchdog_of "$harness")
check "the watchdog is running" test -n "$watchdog"

# Main-thread stalls just under 1 s, landing at different points in the heartbeat cycle.
for delay in 0.05 0.12 0.19 0.24; do
    sleep "$delay"
    echo "stall 0.95" >&3
    sleep 1.1
done
check "stalls under 1 s never trigger a restore" bash -c "! grep -q 'restored from outside' '$log'"
expect "stalls under 1 s leave the dimming" 0.4000

cpu_seconds() { ps -o cputime= -p "$1" | awk -F'[:.]' '{ print $1 * 60 + $2 + $3 / 100 }'; }
before=$(cpu_seconds "$watchdog")
sleep 5
after=$(cpu_seconds "$watchdog")
check "idle watchdog CPU over 5 s: $before s -> $after s (under 0.05 s)" \
    awk "BEGIN { exit !($after - $before < 0.05) }"

kill -STOP "$harness"
took=$("$bin/peek" --built-in --until 1.0000 --within 2 || true)
check "kill -STOP restores within 2 s ($took ms)" is_millis "$took"
kill -CONT "$harness"
expect "kill -CONT brings the dimming back" 0.4000
check "it came back through the watchdog's signal (a fade)" grep -q 'restored from outside' "$log"

kill -9 "$watchdog"
sleep 0.2
expect "kill -9 on the watchdog leaves the dimming" 0.4000
relaunched=
for _ in 1 2 3 4 5 6; do
    relaunched=$(watchdog_of "$harness")
    [[ -n "$relaunched" && "$relaunched" != "$watchdog" ]] && break
    sleep 0.2
done
check "a new watchdog is running within about 1 s (was $watchdog, now ${relaunched:-none})" \
    test -n "$relaunched" -a "$relaunched" != "$watchdog"
kill -STOP "$harness"
took=$("$bin/peek" --built-in --until 1.0000 --within 2 || true)
check "the new watchdog restores kill -STOP within 2 s ($took ms)" is_millis "$took"
kill -CONT "$harness"
expect "and the dimming comes back" 0.4000
echo "quit" >&3
harness_exited
expect "after quit" 1.0000

for run_log in "$work"/log.*; do
    echo "--- harness log ($(basename "$run_log"))"
    cat "$run_log"
done
exit $((failures > 0))
