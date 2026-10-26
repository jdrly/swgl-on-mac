# SWGL on Mac domain context

The glossary of SWGL on Mac, the macOS app that runs SWG Legends' official launcher and game
client on Apple Silicon Macs. Use these terms in issues, pull requests, code, log lines, the app's
text and release notes.

This glossary defines **language, not implementation**. ADRs in [`docs/adr/`](docs/adr/index.md)
own the decisions, and the README describes the behaviour in detail. If a term you need is
missing, add it here in the same pull request and say so in the PR description. Every definition
names its source; what is not decided is marked _Open_.

## SWG Legends' side

**SWG Legends**
The community Star Wars Galaxies server SWGL on Mac plays on. Its team doesn't support SWGL on
Mac, and declined (2026-10-13) to endorse, adopt or integrate third-party clients (README notice;
`notes/rosetta-sunset-plan.md`).
_Avoid_: “SWG” alone when the server is meant.

**Launcher**
SWG Legends' official Java launcher. SWGL on Mac downloads it on first run from SWG Legends' own
URL (`LAUNCHER_ZIP_URL` in `src/common.sh`) and runs it unchanged and natively on Zulu 8 with
JavaFX (arm64); it installs and updates the game (README, *First run*, *Launcher and menus*).

**Game client**
SWG Legends' Direct3D 9 Windows client, `SwgClient_r.exe`, run unchanged in Wine. 64-bit since
2026-10-26 (SWGL on Mac 0.1.0); before that it was 32-bit, which x87sidecar sped up (#34)
(README; `notes/game-mode-for-swtor.md`).
_Avoid_: “the game” when the launcher could be meant; “64-bit test client” for it (that was its
QA-only predecessor, `c64\SwgClient_Latest-x64.exe`).

**D3DX**
Microsoft's D3D9 helper library, `d3dx9_31.dll`, which the 64-bit game client compiles its
shaders with. SWGL on Mac ships Microsoft's 64-bit copy and the game prefers it over Wine's
(README, *Microsoft's D3DX*).

**`custom.cfg`**
The game's user configuration in the game folder, for example `cameraSimpleCollision=1` (README).
Collect Logs includes it.

**`legends.cfg`, `launchersettings.ini`**
The game's and the launcher's files that hold the account password; never collected
(`src/collect-logs.sh`).

## SWGL on Mac's side

**Wine (the bundled Wine)**
The x86_64 Wine inside the app: athei/wine-build `cx-26.3.0-8` (CrossOver 26.3 sources, WoW64,
with x87sidecar), downloaded by `build.sh` at a pinned sha256, with Apple's D3DMetal removed
(README; `build.sh`). Unlike SWTOR on Mac, it is bundled in the app.
_Avoid_: “engine” in this repository's user-facing text, “bottle”.

**Prefix**
The Wine prefix in `~/Library/Application Support/SWGLonMac/Prefix` (`src/common.sh`).

**Game folder**
`~/Library/Application Support/SWGLonMac/Game`: the launcher, the game files, mods and
`custom.cfg` (README, *Using it*; `src/common.sh`).

**d9mt**
The Direct3D 9 to Metal driver the game draws with, [jdrly/d9mt](https://github.com/jdrly/d9mt),
bundled at a pinned commit (`prebuilt/d9mt/VERSION`; README, *d9mt*).

**wined3d**
Wine's own Direct3D 9 on OpenGL: the renderer fallback in the Maintenance menu (README, *Using
it*; `D3D9` in `src/common.sh`).

**Welcome window**
The first-run window (`src/native/Setup.swift`) that downloads the launcher, installs Rosetta if
it is missing, and prepares the prefix (README, *Install*, *First run*).

**Maintenance menu**
The menu shown when the app is opened with Option held: logs, Collect Logs, Debug Mode, the
wined3d fallback, Wine configuration and a Wine reset that keeps the game files (README, *Using
it*).

**Game Mode bundle**
`~/Library/Application Support/SWGLonMac/GameMode/SWGLGame.app`, assembled at run time by
`enable_game_mode` in `src/common.sh`, so macOS gives the game Game Mode (ADR-0002).

**Saved password**
The launcher's saved password, handed to the game so the login screen is filled in: the macOS
launcher can't encrypt it, so right before the client starts the wine shim encrypts it with
Windows DPAPI into `legends.cfg` (`swgl-dpapi.exe`; README, *Saved password*).

**Mouse-look**
While the game turns the camera, the Mac driver sends the mouse's raw moves (from `GCMouse`,
through an input thread) and ignores the game's re-centring; patches
`patches/winemac-swg.patch` and `patches/winemac-input.patch` (README, *Mouse*). **Mouse-Look
Speed** scales it (0.25× to 4×; 1× is as on Windows).

**Debug Mode**
The setting that makes the game logs much more detailed for the next start, at some cost in
performance; turned on only when asked (README).
_Avoid_: “Debug Logging” (SWTOR on Mac's name for its setting).

**Collect Logs**
*SWGL on Mac → Collect Logs…*: a zip for bug reports, `SWGL-on-Mac-logs-<date>.zip`, with the
password, account name, e-mail address, user name and serial numbers left out or replaced (README,
*Reporting problems*; `src/collect-logs.sh`).

**Hitch**
A short stall when entering a new area: the game loads content on its main thread, which runs
translated by Rosetta; not fixable from outside the game (README, *Known limitations*; #4).

## Releases and the future

**Release**
A signed, notarized version on GitHub Releases, offered as an update through the feed; the
Release workflow builds the draft and `scripts/release.sh --feed` on the maintainer's Mac adds the
signed feed (README, *Building*).

**Feed**
`appcast.xml` of the latest GitHub release, signed with Sparkle's EdDSA key, with delta updates
(README, *Updates*).

**Release notes**
`release-notes/<version>.md`, used unchanged in the GitHub release, the update window and on
swonmac.com, in the format of [release-notes/README.md](release-notes/README.md).

**Rosetta sunset**
From macOS 28, Rosetta remains only for a subset of older games, so the x86_64 Wine may stop
working there; tracked in #20 (`notes/rosetta-sunset-plan.md`; ADR-0003).

**FEX**
The x86 emulator a native arm64 Wine loads as `xtajit.dll` (i386, WoW64) and `xtajit64.dll`
(x86_64, ARM64EC): the recommended route after Rosetta (`notes/rosetta-sunset-plan.md` §4.1).

**x87sidecar**
The bundled Wine's acceleration of x87 floating-point code, which patches Rosetta's own runtime
(`notes/rosetta-sunset-plan.md`).

## Open

- The launcher's version is not recorded in Collect Logs.
