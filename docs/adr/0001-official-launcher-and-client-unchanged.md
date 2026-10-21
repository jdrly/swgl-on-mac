---
status: accepted
date: 2026-10-21
deciders: Jan Drlý
---

# SWGL on Mac runs SWG Legends' official launcher and client unchanged and never ships their files

## Context

SWG Legends has no Mac version. Its team doesn't support mods or clients that don't come from
them, and declined on 2026-10-13 to endorse, adopt or integrate third-party clients or translation
layers: no source, no native build, no access to their 64-bit QA client, no cooperation (README
notice; `notes/rosetta-sunset-plan.md`, *Constraint*).

## Decision

- SWGL on Mac runs SWG Legends' official Windows launcher and 32-bit game client unchanged: the
  launcher on Zulu 8 with JavaFX, the client in the bundled Wine with d9mt (README).
- The app doesn't ship the launcher. The welcome window downloads it from SWG Legends' own URL
  on first run, and the launcher installs and updates the game itself, as on Windows (README,
  *First run*).
- SWGL on Mac never modifies or redistributes SWG Legends' files (`notes/rosetta-sunset-plan.md`).
- Players send support questions to Pharaphobia, never to the SWG Legends team (README notice).

## Consequences

- Every fix happens around the client (Wine, d9mt, the Mac driver, the Game Mode bundle), never in
  it; problems inside the game's own code, such as the hitches on its translated main thread,
  can't be fixed from outside (README, *Known limitations*; #4).
- First run needs SWG Legends' download URL to work.
- Life after Rosetta must keep running the unmodified 32-bit x86 client (ADR-0003).

## Alternatives considered

- **Ship the launcher in the app**: not done; the app downloads it from SWG Legends instead
  (README, *First run*). No further reasoning is recorded.
- **A native or changed client**: excluded by SWG Legends' position (no source, no cooperation).
