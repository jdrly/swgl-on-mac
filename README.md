# SWGL on Mac

A native macOS app for playing [SWG Legends](https://swglegends.com) on Apple Silicon Macs.

> **Unofficial.** SWGL on Mac is a community project and is not affiliated with or endorsed
> by the SWG Legends team. It runs their official launcher and game client unchanged.

The official Java launcher runs natively (Zulu 8 + JavaFX, arm64). The 32-bit DirectX 9 game
client runs in a bundled Wine (CrossOver 26.3 based, WoW64, with x87 acceleration) on
[d9mt](https://github.com/jdrly/d9mt), a Direct3D 9 to Metal driver.

## Install

**Requirements:** a Mac with Apple Silicon, macOS 26 or later (developed on macOS 27), an
internet connection, and about 10 GB of free space for the game.

1. Download `SWGL-on-Mac-<version>.dmg` from
   [Releases](https://github.com/jdrly/swgl-on-mac/releases), open it and drag
   **SWGL on Mac** into Applications.
2. Open SWGL on Mac. On first start a welcome window downloads the official SWG Legends
   launcher from swglegends.com and prepares everything (about a minute). If Rosetta is not
   installed yet, macOS offers to install it when the game first starts.
3. Log in to the launcher. It installs the game and keeps it up to date, as on Windows.

The app is signed and notarized by Apple.

## Using it

- **SWGL on Mac menu:** *About SWGL on Mac*, *Open SWGL in Finder*, which opens the game
  folder (where mods and `custom.cfg` go), and *Collect Logs…* (see
  [Reporting problems](#reporting-problems)).
- **Features menu:** *Retina Mode* (full-resolution rendering, on by default), *Show Metal HUD*
  (frame rate overlay), *Game Mode* (macOS Game Mode in full screen, on by default), *Debug
  Mode* (much more detailed game logs, at some cost in performance; off by default). Changes
  apply the next time the game starts.
- **Maintenance menu:** hold Option while opening the app for logs, Collect Logs and Debug
  Mode (also when the launcher does not start), the renderer fallback (wined3d), Wine
  configuration and a Wine reset that keeps the game files.
- The launcher's saved password is handed to the game, so the login screen is filled in.
- Game files, the Wine prefix and settings live in `~/Library/Application Support/SWGLonMac`,
  logs in `~/Library/Logs/SWGLonMac`.

## Reporting problems

1. Choose **SWGL on Mac → Collect Logs…** (in the launcher's menu bar). It saves
   `SWGL-on-Mac-logs-<date>.zip` to your Desktop and shows it in Finder.
2. Send that zip with a short description of what happened and when.

The zip holds the app's logs, settings, system details (Mac model, macOS, displays) and
recent crash reports. Your account password, account name, e-mail address, user name and
serial numbers are left out or replaced. Turn on **Features → Debug Mode** only when asked:
it makes the logs much more detailed for the next game start, but costs some performance and
disk space, so turn it off again afterwards.

## Known limitations (0.0.1, early beta)

- **Short hitches when entering new areas.** The game loads new content on its main thread,
  and on a Mac that code runs translated (Rosetta). Profiling shows the time is the game's own
  work, not the graphics driver; this is being investigated.
- **The chase camera pulls in at every wall.** That is the game's camera collision. The
  in-game option *Simple Camera Collision*, or `cameraSimpleCollision=1` under
  `[ClientGame/FreeChaseCamera]` in `custom.cfg`, makes it calmer.
- The 64-bit test client that the launcher can download for QA testers is not supported.
- Apple Silicon only.

## How it works

### First run

The app does not ship SWG Legends' launcher. On first start a welcome window
(`src/native/Setup.swift`, SwiftUI) downloads it from SWG Legends' own URL
(`LAUNCHER_ZIP_URL` in `src/common.sh`), unpacks it into the game folder (without its Windows
Java runtime) and prepares the Wine prefix. Once the launcher is there, the window never shows
again, and the launcher updates itself. macOS only waits a moment for a launched app to check
in, so when setup took longer the app relaunches itself once (`src/main.sh`); otherwise the
launcher would run as an anonymous `java` process without the app's menus.

### Launcher and menus

The official launcher runs unchanged. Its Java process owns the menu bar while the launcher is
in front, so `src/java/Launcher.java` starts it in that JVM and loads
`src/native/swglmenus.m`, which adds the native menus. The Features toggles write the same
`settings.conf` as the maintenance menu.

### Game Mode

macOS enables Game Mode only for a full-screen process whose executable is the executable of
a bundle declaring itself a game, while every Wine process runs Wine's loader. Right before the
client starts, the wine shim (`enable_game_mode` in `src/common.sh`) assembles
`~/Library/Application Support/SWGLonMac/GameMode/SWGLGame.app`: an unsigned copy of Wine's
loader as `SwgClient_r.exe`, an `ntdll.so` link back to the app's Wine, and an Info.plist with
`LSSupportsGameMode`. It then sets `WINEDLLPATH`, which makes Wine start the program from a
link in `$TMPDIR/winetemp-<loader inode>-…/`, and points that link at the bundle, so the game
runs as `SWGLGame.app`. The bundle lives outside the app because a signed app cannot contain a
link that leaves a bundle, and the loader copy is unsigned because macOS rejects the app's
signature inside a bundle it was not made for.

### Saved password

The game reads its saved password from `legends.cfg` (`loginClientEncHashedPassword`) with
Windows DPAPI. On macOS the official launcher cannot encrypt it (it writes plain base64, and
reads the setting back from a different key, so the next save writes it empty). Right before
the client starts, the wine shim encrypts the password with DPAPI inside the app's Wine
(`swgl-dpapi.exe`, built by `scripts/build-wintools.sh` from `src/win`). The password comes
from the launcher's Settings or, if that is empty, from its "Remember me" login when the
account names match.

### Mouse

SWG re-centres or re-asserts the cursor with `SetCursorPos` every frame and reads DirectInput.
Wine's stock Mac driver warps the real cursor each time and drops the queued mouse moves, so
camera turning stutters and the cursor jitters (macOS even magnifies it as if shaken). The
patched driver (`patches/winemac-swg.patch`):

- delivers raw device deltas while the game hides the cursor (mouse-look), with the macOS
  cursor frozen;
- subtracts the displacement of its own cursor warps from the next device delta (macOS folds
  it into that event), so entering combat mode with the pointer in a corner does not spin the
  camera;
- treats a `SetCursorPos` to a position the cursor just had as a no-op, as on Windows, and
  keeps the server cursor where it is so DirectInput does not count the move twice.

Mouse acceleration is off in the prefix (`MouseSpeed=0`): SWG applies Windows acceleration per
input event, which Wine batches differently. Smooth camera also needs d9mt's display-paced
presentation (`d3d9.presentInterval = 1` in `src/d9mt.conf`).

### d9mt

d9mt (D3D9 → Metal) is maintained by Jan Drlý at https://github.com/jdrly/d9mt, a fork of
neo773's d9mt, which was archived upstream. `scripts/build-d9mt.sh` builds it at a pinned
commit with that repo's own build recipe and strips the binaries; the app ships d9mt's
licenses and third-party notices in `Resources/licenses/d9mt`. Two fixes SWG needed:

- `6a7473c`: varyings are declared with their real type instead of a hardcoded `float4`. The
  scalar D3D9 fog varying of SM1.x/2.0 shaders made Apple's GPU compiler crash (macOS 27), so
  every SWG pixel shader failed and the screen stayed black.
- `02e7a66`: the occlusion-query buffer uses VirtualAlloc'd memory, which a 32-bit process can
  address.

## Building

- `scripts/build-d9mt.sh` builds d9mt into `prebuilt/d9mt` (Homebrew bash, mingw-w64, cmake,
  ninja and Xcode; LLVM 15 is built once, or reused via `D9MT_LLVM`).
- `scripts/build-wintools.sh` builds the small Windows helpers into `prebuilt/wintools`.
- `scripts/build-winemac.sh` builds Wine's Mac driver from the exact source of the bundled Wine
  with `patches/winemac-swg.patch` into `prebuilt/winemac`.
- `build.sh` assembles `dist/SWGL on Mac.app` from pinned, checksummed downloads plus those
  pieces (`--install` also copies it to /Applications). It needs a JDK 9+ (`javac` and
  `jni.h`; Homebrew `openjdk` is found automatically, or set `JAVAC`) and Xcode's Swift.
- `scripts/release.sh` signs the app with a Developer ID (hardened runtime, entitlements in
  `src/entitlements`), builds the DMG, notarizes and staples it (`IDENTITY` and
  `NOTARY_PROFILE` override the defaults; `--sign-only` stops after signing).

`prebuilt/` holds the outputs of the three scripts, so `build.sh` works from a fresh clone.

## Credits and licenses

- SWG Legends, its launcher and game files belong to the SWG Legends team; Star Wars Galaxies
  and related marks belong to their owners.
- [Wine](https://www.winehq.org) (LGPL-2.1+), built by
  [athei/wine-build](https://github.com/athei/wine-build) from CodeWeavers' CrossOver sources;
  this repository's changes to it are in `patches/`. The bundled Wine includes Apple's
  `libd3dshared.dylib` from the Game Porting Toolkit, under Apple's license (shipped beside it);
  Apple's D3DMetal is removed, since SWG does not use it.
- [d9mt](https://github.com/jdrly/d9mt) (zlib, bridge LGPL-2.1+), with DXVK and DXMT code.
- [Azul Zulu](https://www.azul.com/downloads/) 8 with JavaFX (GPLv2 with Classpath Exception).
- [llvm-mingw](https://github.com/mstorsjo/llvm-mingw) for the Windows helpers.

## License

The code in this repository is under the [zlib license](LICENSE), except
`patches/winemac-swg.patch`, which modifies Wine and is under Wine's LGPL-2.1+. The files in
`prebuilt/` and everything the build downloads keep their own licenses (see above; d9mt's are
in `prebuilt/d9mt`).
