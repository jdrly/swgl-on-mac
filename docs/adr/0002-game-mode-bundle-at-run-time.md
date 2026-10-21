---
status: accepted
date: 2026-10-21
deciders: Jan Drlý
---

# The Game Mode bundle is assembled at run time outside the app

## Context

macOS turns Game Mode on only for a full-screen process whose executable is that of a bundle
declaring itself a game (`LSSupportsGameMode`), while every Wine process runs Wine's loader
(README, *Game Mode*). The first approach shipped such a bundle inside the app. It didn't survive
Developer ID signing: a link leaving a bundle fails strict verification, and the signed loader copy
with entitlements is killed (“Code Signature Invalid”) inside a bundle its signature wasn't made
for (`notes/game-mode-for-swtor.md`, *Update 2026-10-13*).

## Decision

- Right before the client starts, the wine shim (`enable_game_mode` in `src/common.sh`) assembles
  `~/Library/Application Support/SWGLonMac/GameMode/SWGLGame.app`: an unsigned copy of Wine's
  loader as `SwgClient_r.exe`, an `ntdll.so` link back to the app's Wine and an Info.plist with
  `LSSupportsGameMode`, refreshed when the app's Wine changes.
- It sets `WINEDLLPATH`, which makes Wine start the program from a link in
  `$TMPDIR/winetemp-<loader inode>-…/`, and points that link at the bundle (README, *Game Mode*).

## Consequences

- The game runs as `SWGLGame.app`; Game Mode is on by default and can be turned off in Settings
  (README).
- The bundle lives outside the signed app, in the user's Application Support folder.
- SWTOR on Mac uses the same layout for the same engine (`notes/game-mode-for-swtor.md`).

## Alternatives considered

- **The bundle inside the app**: rejected after Developer ID signing broke it (above).
- **Signing the loader copy for the bundle**: rejected; macOS rejects the app's signature inside a
  bundle it was not made for, so the copy is unsigned (README, *Game Mode*).
