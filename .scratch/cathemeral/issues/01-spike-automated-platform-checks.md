# 01: Spike: automated platform checks

**What to build:** A throwaway prototype that answers the open questions the build depends on, using checks an agent can run and verify by itself. It dims a display through the gamma table and reads the table back to confirm each result, so no one has to watch the screen. Keep the code on a `prototype/spike` branch as a primary source. Record every answer in this ticket under `## Comments`, and update the PRD's "Open questions for the spike" if any answer changes the design. If the agent's shell can't reach WindowServer, leave a one-command script for the user to run in Terminal and record its output.

See the PRD (Implementation Decisions → Open questions for the spike) and ADR 0001.

**Blocked by:** None (can start immediately)

**Status:** ready-for-agent

- [ ] Answered: can a separate helper process reset gamma set by another process by restoring ColorSync settings? (Yes/no, with the read-back evidence.)
- [ ] Answered: does macOS restore gamma by itself when the process that set it is killed with SIGKILL? (Checked from a fresh process.)
- [ ] Measured: a pipe-heartbeat watchdog restores gamma within 2 s of the app being frozen with SIGSTOP.
- [ ] Measured: time for one on-screen window list call (median and p95 over at least 100 calls), with the number of windows open noted.
- [ ] Measured: software latency from the activation notification to the first gamma write (median and p95 over at least 30 app switches).
- [ ] A probe script exists that prints each display's current gamma state, for the manual checks in ticket 02.
- [ ] Every test restores the original gamma at the end, and the screen is left as it was found.
- [ ] If an answer breaks an assumption (such as the watchdog being unable to restore), the consequence for the safety-net design is written in the ticket.
