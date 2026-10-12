# Game Mode without a standalone bundle: note for the SWTOR project

> **Update 2026-10-13 (signing):** shipping the bundle inside the app did not survive Developer ID
> signing. A link leaving a bundle fails strict verification, and the signed loader copy with
> entitlements is killed ("Code Signature Invalid") inside a bundle its signature was not made
> for. The wrapper now assembles `SWGLGame.app` at run time in
> `~/Library/Application Support/SWGLonMac/GameMode/`, with an unsigned copy of the loader,
> refreshed when the app's Wine changes. That is the same layout as SWTOR's, just automatic. The
> rest of this note (engine differences, WINEDLLPATH, the `wine` link name) still applies.

How SWGL on Mac enables macOS Game Mode, compared with `tools/swtor-gamemode.sh`. There are
no d9mt changes; it is all packaging and the wine wrapper.

## Same idea

gamepolicyd only grants Game Mode to a full-screen process whose executable is the
`CFBundleExecutable` of a bundle with `LSSupportsGameMode`. CrossOver's ntdll (hack 22144)
starts processes from a link in
`$(getconf DARWIN_USER_TEMP_DIR)winetemp-<loader ino>-<size>-<mtime s>-<mtime ns>/` and reuses
whatever already exists there. Point that link at a clone of the loader inside a game bundle.

## What SWGL does differently

- **The bundle ships inside the app.** `build.sh` creates
  `SWGL on Mac.app/Contents/Resources/SWGLGame.app` on every build: an APFS clone of the loader
  as `Contents/MacOS/SwgClient_r.exe`, plus an Info.plist with `LSSupportsGameMode`,
  `GCSupportsGameMode` and the role-playing-games category. It is ad-hoc signed before the outer
  app. There is no install step and no env opt-in, and because it is rebuilt with the app it
  cannot drift from the engine. It can be switched off with the `GAME_MODE` setting.
- **The wrapper makes the link on every game start** (`enable_game_mode` in `src/common.sh`),
  the same as `wine-wrapper.sh` does for SWTOR.

## Engine differences (cx-26.3 athei build vs CX 24.0.7)

1. **No `wine-preloader`.** The loader is `lib/wine/x86_64-unix/wine`, and ntdll only uses the
   link path when `WINEDLLPATH` is set (`preloader_exec`, `!HAVE_WINE_PRELOADER` branch). The
   wrapper exports `WINEDLLPATH="$WINE_HOME/lib/wine"` (a no-op for DLL lookup) for the game
   launch only.
2. **The first process of a `wine` command gets the link named `wine`.** Its image path is
   `argv[0]` of the loader, so the name is not `<exe>.exe`. Only children spawned via
   CreateProcess get `<exe>.exe` links. SWG is started directly as `wine SwgClient_r.exe`, so the
   wrapper links `winetemp-…/wine`. SWTOR's game is a child of its launcher, so its `swtor.exe`
   name still applies.
3. **The loader resolves symlinks to find `ntdll.so`** (`realpath` in `loader/main.c`
   `try_dlopen`). The bundle therefore needs `Contents/MacOS/ntdll.so -> …/x86_64-unix/ntdll.so`
   beside the clone. ntdll then `realpath`s itself back into the real Wine tree, so DLLs,
   compatdb and x87sidecar paths are unchanged.
4. **No embedded `__info_plist` in this loader**, so AppKit may read the bundle's Info.plist.
   For that reason the bundle has **no `LSUIElement`** (the game must keep its Dock icon and ⌘-Tab),
   and its `CFBundleName` is the app's name.

## Verified

A 32-bit stand-in .exe started the way the game is (x87sidecar re-exec included) runs from
`SWGLGame.app/Contents/MacOS/SwgClient_r.exe` (`lsof -d txt`), loads the real `ntdll.so` and
exits cleanly. The in-game Game Mode check (gamepolicyd "Found game" / the menu bar 🎮) is
pending the user's first full-screen session.

## Porting to SWTOR (suggestion only)

Have the SWTOR app build generate `SWTOR.app` (as `swtor-gamemode.sh install` does) inside its
own bundle or engine directory, and make the wrapper link unconditionally whenever that copy
matches the engine's preloader. That removes the install step and `SWTOR_GAMEMODE_APP`. Keep
`LSUIElement` there: CX24's preloader carries an embedded plist, so AppKit ignores the bundle's.
