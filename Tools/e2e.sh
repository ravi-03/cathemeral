#!/usr/bin/env bash
# Checks dimming end to end on the real built-in display: the real engine, gamma controller and
# activation monitor, with every result read back by `peek`, a separate process that never
# writes gamma. It switches between Terminal and Finder, then checks the safety net (termination
# signals, kill -9, a hang caught by the watchdog, a dead watchdog) and paused displays (with
# `other-app` standing in for f.lux), so it takes over the screen for about a minute and a half.
# Not part of scripts/check.
#
# Exits non-zero if any reading is wrong. Every way out ends the harness (resuming it first if
# it was stopped) and `other-app`, and macOS resets a gamma writer's tables when it exits, so the
# screen is never left dim.
set -euo pipefail
cd "$(dirname "$0")"
if pgrep -x Cathemeral >/dev/null; then
    echo "Quit Cathemeral first: a second gamma writer spoils every reading, and its exit resets the harness's tables." >&2
    exit 1
fi
swift build -q
bin=.build/debug
work=$(mktemp -d)
# The watchdog is built into the app bundle by Xcode; here it is built straight from its sources.
swiftc -O ../App/GammaWatchdog/*.swift -o "$work/GammaWatchdog"
mkfifo "$work/in" "$work/other-in"

harness=
runs=0
# Starts a harness with its own log, and waits for it to listen. Commands go to fd 3.
start_harness() {
    runs=$((runs + 1))
    log="$work/log.$runs"
    # Not holding other-app's input open (fd 4), so closing it in this script ends other-app.
    "$bin/harness" "$work/GammaWatchdog" <"$work/in" >"$log" 2>&1 4>&- &
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

other=
# Starts `other-app`, another gamma writer, and waits for it to listen. Commands go to fd 4.
start_other_app() {
    # Not holding the harness's input open (fd 3), so closing it in this script ends the harness.
    "$bin/other-app" <"$work/other-in" >"$work/other.log" 2>&1 3>&- &
    other=$!
    exec 4>"$work/other-in"
    until grep -q READY "$work/other.log"; do
        kill -0 "$other" 2>/dev/null || { cat "$work/other.log" >&2; exit 1; }
        sleep 0.1
    done
}
# Ends `other-app` through end of input, or kills it after 2 s: its exit makes WindowServer reset
# every display either way.
other_app_quits() {
    exec 4>&-
    for _ in {1..20}; do
        kill -0 "$other" 2>/dev/null || break
        sleep 0.1
    done
    if kill -9 "$other" 2>/dev/null; then
        echo "FAIL  other-app didn't exit at end of input (killed)"
        failures=$((failures + 1))
    fi
    wait "$other" 2>/dev/null || true
    other=
}
cleanup() {
    exec 3>&- || true
    exec 4>&- || true
    if [[ -n "$other" ]]; then kill -9 "$other" 2>/dev/null || true; fi
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

# Asks the harness for the built-in display's status every 250 ms until it is <status>, for up to
# <seconds>. status_becomes <status> <seconds>
status_becomes() {
    local tries=$(($2 * 4))
    for ((try = 0; try < tries; try++)); do
        echo "status" >&3
        sleep 0.25
        [[ "$(grep '^status ' "$log" | tail -1)" == "status $1" ]] && return 0
    done
    return 1
}

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

echo "--- paused displays"
start_other_app # before anything dims, so the table it scales is the original curve
start_harness
dim "paused display"
echo "write 0.8" >&4
check "another app's table pauses the display within three checks (about 3 s)" status_becomes paused 4
expect "a paused display keeps the other app's colours" 0.8000
echo "resume" >&3
expect "resume dims on top of the other app's colours" 0.3200
check "and the display is dimming again" status_becomes dimming 1
echo "write 0.7" >&4
check "the other app writing again pauses it again" status_becomes paused 4
expect "and its colours stay" 0.7000
sleep 3
check "nothing resumes by itself" status_becomes paused 1
echo "resume" >&3
expect "resuming again dims on top of the new colours" 0.2800
other_app_quits
took=$("$bin/peek" --built-in --until 0.4000 --within 1.5 || true)
check "the other app quitting after a resume re-applies on the reset curve ($took ms)" is_millis "$took"
check "without pausing the display" status_becomes dimming 1
echo "quit" >&3
harness_exited
expect "after quit" 1.0000

start_other_app # first, so a failed start can't leave the harness's dimming behind
start_harness
dim "reset"
echo "touch" >&4 # writes our own table back, so nothing changes
sleep 2.2
check "a write that leaves our table counts for nothing" status_becomes dimming 1
other_app_quits
took=$("$bin/peek" --built-in --until 1.0000 --within 1 || true)
check "another gamma writer quitting resets the display ($took ms)" is_millis "$took"
took=$("$bin/peek" --built-in --until 0.4000 --within 1.5 || true)
check "and the reset is re-applied within about 1 s ($took ms)" is_millis "$took"
check "without pausing the display" status_becomes dimming 1
echo "quit" >&3
harness_exited
expect "after quit" 1.0000

# The harness logs are only worth reading when something failed.
if ((failures > 0)); then
    for run_log in "$work"/log.*; do
        echo "--- harness log ($(basename "$run_log"))"
        cat "$run_log"
    done
    if [[ -f "$work/other.log" ]]; then
        echo "--- other-app log"
        cat "$work/other.log"
    fi
fi
exit $((failures > 0))
