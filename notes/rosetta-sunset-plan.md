# Rosetta sunset plan

Written 2026-10-13 on macOS 27.0.1 (26A434), Xcode 27.0. Planning only: nothing was built,
installed or run for it, and no binaries were downloaded. Local evidence comes from this repo, the
installed macOS 27 SDK and the app's own build in `dist/`.

**Conventions.** Plain statements are facts, each with a source and the date it was published or
checked. Text marked **Speculation:** or **Inference:** is not verified. Sources are listed in
[§12](#12-sources) and cited as [S1], [S2], ….

**Constraint.** SWG Legends declined (2026-10-13) to endorse, adopt or integrate third-party
clients or translation layers. So: no source, no native build, no access to their 64-bit QA client,
no cooperation. We keep running their unmodified Windows binaries and never modify or redistribute
their files. Nothing below assumes otherwise.

## 1. Summary

- **Deadline.** macOS 27 is the last release with full Rosetta. From macOS 28 (expected September
  2027, betas from WWDC in June 2027), Rosetta remains only for "older, unmaintained gaming titles
  that rely on Intel-based frameworks" [S1][S2]. Apple has not defined that subset. CodeWeavers,
  whose Mac business depends on this question, tell their PortJump customers that a Wine app left
  on Rosetta "will not be compatible with macOS 28" [S6]. **Plan as if our x86_64 Wine
  stops working on macOS 28.**
- **The replacement exists, and it is the same one CodeWeavers chose:** native arm64 Wine, with
  FEX emulating x86 code through Wine's WoW64 layer (i386) and ARM64EC (x86_64). Apple added the
  OS pieces for this in macOS 26.4 to 26.6: x18 custom ABI, 4K-page processes, per-thread TSO, a
  movable PAGEZERO and `os_cross_arch_is_supported()`. They are behind a restricted entitlement
  [S7], and all of them are present in the macOS 27 SDK on this Mac (checked 2026-10-13).
  CrossOver Preview has shipped this on macOS since 2026-07-31 [S4]. None of it is in upstream
  Wine or upstream FEX yet [S11][S13].
- **x87sidecar has no future after Rosetta.** It patches Rosetta's own runtime. Its job (fast x87)
  moves to FEX, whose fast x87 mode uses 64-bit doubles. That should be good enough for SWG
  because d9mt already puts the x87 unit in 24-bit precision unless the game opts out (§7).
- **d9mt ports well.** Its Metal bridge and shader compiler live in the Unix-side `winemetal.so`,
  which becomes native arm64. Its bridge descends from DXMT, which already ships exactly the layout
  we need (aarch64 `winemetal.so`, i386 and ARM64EC PE DLLs) inside CrossOver Preview [S15]. For
  the 32-bit client, `d3d9.dll` stays i386 and runs under FEX. For a 64-bit client it can be built
  ARM64EC and run native.
- **Biggest unknowns:**
  - whether a notarized Developer ID app can carry the cross-architecture entitlement for end users;
  - when CodeWeavers' Wine and FEX changes become public: Wine "MRs soon" since August [S7], and
    CrossOver 27 sources "early 2027" [S4];
  - FEX's i386 + x87 performance on SWG compared with Rosetta + x87sidecar (no AOT, so possibly
    worse zone-load hitches, #4);
  - what the macOS 28 games subset actually covers.

## 2. What depends on Rosetta today (measured in this repo, 2026-10-13)

| Piece | Architecture today | Under Rosetta? |
|---|---|---|
| App launcher, SwiftUI Setup, `libswglmenus.dylib` | arm64 | no |
| Zulu 8 JRE + JavaFX, running the official launcher | arm64 | no |
| `wine`, `wineserver`, the loader, `ntdll.so`, `win32u.so`, `compatdb.so`, our patched `winemac.so` | x86_64 Mach-O (athei/wine-build `cx-26.3.0-8`) | **yes** |
| d9mt `winemetal.so`: Metal bridge plus the AIR/LLVM shader compiler (`strings`: ~11k LLVM symbols, 10 MB) | x86_64 Mach-O | **yes** |
| d9mt `d3d9.dll` + `winemetal32.dll` (32-bit client) | i386 PE | **yes** (WoW64) |
| d9mt `d3d9-x64.dll` + `winemetal64.dll` (64-bit client, prepared in #6) | x86_64 PE | **yes** |
| Wine's PE DLLs, `swgl-dpapi.exe` | i386 + x86_64 PE | **yes** |
| `SwgClient_r.exe` and its DLLs | i386 PE | **yes** |
| `SwgClient_Latest-x64.exe` (QA only, no access) | x86_64 PE | **yes** |
| `x87sidecar` (athei, MIT, forked from Lifeisawful's rosettax87) | arm64, but it patches `translate_insn` in `libRosettaRuntime` and runs as an IPC JIT for the game process | it is a Rosetta plug-in |

Other places the app assumes Rosetta:
- `X87`/`ROSETTA_X87_PATH` in `src/common.sh`;
- the Rosetta line in `swgl_system_info`;
- the README's install step ("macOS offers to install Rosetta");
- `WINE_DISABLE_NX_COMPAT` semantics in athei's ntdll ("under Rosetta");
- the Game Mode bundle (`enable_game_mode`), which runs an **unsigned** copy of the x86_64 loader.
  The last one collides with the entitlement model in §5.

Build side: `scripts/build-winemac.sh` and d9mt's `build-bridge.sh`/`build-d9mtair.sh` cross-compile
x86_64 Mach-O and link an x86_64 LLVM 15. That needs no Rosetta to compile, but every smoke test
of the result does. athei/wine-build needs Rosetta or an Intel Mac to build Wine at all [S16].

## 3. Facts and timeline

| Date | Event | Source |
|---|---|---|
| 2020-11 | Rosetta 2 ships with the M1 | [S3] |
| 2025-06 (WWDC25) | Apple: Rosetta available "through macOS 27" as a general-purpose tool; afterwards "a subset of Rosetta functionality aimed at supporting older unmaintained gaming titles, that rely on Intel-based frameworks" | [S3] |
| 2025-11 | CrossOver Preview for **Linux** ARM64 ships, with FEX for i386 and x86_64 | [S4] |
| 2025-11-13 | FEX upstream: "There are no plans for MacOS support in FEX at this time" (issue #5046, closed) | [S11] |
| 2026-03-08 | DXMT gains an ARM64EC build (commit 7ef5d9ca4) | [S15] |
| 2026-06-10 | macOS 27 beta; MacRumors: last release with full Rosetta | [S3] |
| 2026-06-11 | CodeWeavers: CrossOver 27 Apple-silicon-only; ARM64 builds for Mac and Linux; "32-bit bottles will no longer run, full stop" (32-bit **apps** keep running in 64-bit WoW64 bottles, which is the mode we use) | [S5] |
| 2026-06-19 | CodeWeavers (PortJump): "If you choose not to upgrade to an Apple Silicon-native version of our PortJump framework, your application will not be compatible with macOS 28." | [S6] |
| 2026-07-31 | CrossOver Preview ships native ARM64 Wine on macOS with "a custom version of FEX compatible with macOS". Requirements and state: macOS 26.5+ (older systems fall back to Intel Wine + Rosetta); "not expected to be useful for anything beyond testing"; no D3DMetal; ARM64 DXMT included | [S4] |
| 2026-08-07 | Brendan Shanks (CodeWeavers), wine-devel: "all the pieces are now present in macOS to natively run ARM64 Wine"; details in §5; "I'll be sending MRs upstream soon" | [S7] |
| 2026-08-26 | DXMT adds ARM64X (`-marm64x`, commit 3b7807622) | [S15] |
| 2026-09-01 | Apple Developer News: "macOS 27: Final release to support Rosetta. Intel-only apps will no longer run on Mac computers with Apple silicon after this update. … Rosetta functionality for older, unmaintained gaming titles that rely on Intel-based frameworks will continue to be supported." | [S1] |
| 2026-09-09 | A second Apple news item says macOS 26 was the last with Rosetta. It contradicts [S1] and the support article, and is probably a conflation with the end of Intel Macs; Apple has not corrected it | [S8] |
| 2026-09 (release) | macOS 27 does not keep Rosetta across the upgrade; it must be reinstalled (macOS offers this on first x86 launch) | [S3][S9] |
| 2026-09-21 | Apple support HT102527: "Starting with macOS 28, the next major macOS release, Rosetta functionality will be available only for certain older unmaintained games that rely on Intel-based frameworks." | [S2] |
| 2026-10-07 | `dbc-hbin/FEX-darwin` appears: a community FEX port that builds `xtajit.dll` (WoW64 i386) and `xtajit64.dll` (ARM64EC) for arm64 Wine on macOS; needs Wine-side hooks not in any public Wine | [S12] |
| 2026-10-13 | Upstream Wine (11.19, 2026-10-02) has only preparatory macOS-arm64 MRs merged (!11267, !11402, !11668, !11736); x18, 4K spawn, TSO and PAGEZERO are not submitted. DXMT latest release is still v0.80 (2026-04-23), before its ARM64 work | [S13][S15] |
| early 2027 (planned) | CrossOver 27 with ARM64 (CodeWeavers: limitations resolved "in time for CrossOver 27 early next year"). Its LGPL Wine sources should follow, as for every CrossOver release | [S4] |
| ~June 2027 (expected) | WWDC27, first macOS 28 beta | inference from Apple's yearly cycle |
| ~September 2027 (expected) | macOS 28 release; general Rosetta gone | [S1][S2] |

### What the post-27 "games subset" probably is

- **Fact:** the only criterion Apple has given is "older, unmaintained gaming titles that rely on
  Intel-based frameworks" [S1][S2]. No list, no API and no opt-in has been published.
- **Inference:** "Intel-based frameworks" reads like native x86_64 macOS game binaries linking
  Apple's x86_64 system frameworks (old Steam ports, Unity/Unreal Mac builds). The likely
  mechanism is keeping the x86_64 slices of a set of system frameworks plus the translator. A
  third-party x86_64 Wine is technically one such program, but nothing says it would qualify.
- **Fact:** CodeWeavers tells PortJump customers that apps left on the Rosetta-based framework
  "will not be compatible with macOS 28" [S6]. Their whole Mac business depends on this question,
  and they are moving to ARM64 rather than relying on the subset.
- **Speculation:** the subset might be an allow-list (by bundle ID or signature) or might exclude
  processes that need x86_64 `dyld` for arbitrary libraries. Either would end our x86_64 Wine. And
  even if Wine kept running, x87sidecar's hooks into `libRosettaRuntime` (it checks code patterns
  and refuses unknown runtimes) could stop matching a cut-down runtime.
- **Rosetta for Linux VMs:** see §4.6.

## 4. Options, ranked

Scores: feasibility (can it run SWG at all), effort (for us), and risk.

### 4.1 Rank 1: native arm64 Wine + FEX (WoW64 for i386, ARM64EC for x86_64) + d9mt on arm64

**What it is.** Wine's Unix side (`ntdll.so`, `win32u.so`, `winemac.so`, `wineserver`) and d9mt's
`winemetal.so` become arm64 Mach-O. Wine's 64-bit PE side is `aarch64-windows` with ARM64EC. x86
code is translated by FEX's two Windows modules:
- `libwow64fex.dll`, loaded as `xtajit.dll` from `HKLM\Software\Microsoft\Wow64\x86`, for i386
  processes like `SwgClient_r.exe`;
- `libarm64ecfex.dll`, loaded as `xtajit64.dll` from `HKLM\Software\Microsoft\Wow64\amd64`, for
  x86_64 code in ARM64EC processes.

This is the CrossOver Preview design [S4][S7], Proton ARM64's design on Linux [S14], and Madeira's
on iOS [S17].

**macOS requirements.** All from [S7]; each was checked in the macOS 27.0 SDK on this Mac on
2026-10-13:
- `os_set_custom_x18_abi_enabled()` (`os/arch/arm64.h`, macOS 26.4). Interim alternative: link the
  loader with `-Wl,-platform_version,macos,11.0,11.0`.
- `posix_spawnattr_set_4k_page_size_np()` (`spawn.h`, annotated 26.0; [S7] says 26.5).
- `thread_set_x86_64_compat()` (`mach/mach_traps.h`), per-thread TSO. Not inherited by new
  threads, so FEX has to set it on every thread it runs guest code on.
- `-Wl,-x86_64_layout_emulation` (Xcode 26.4) to resize and remap the 4 GB PAGEZERO. CodeWeavers
  use about 0x170000000, which frees the below-4 GB range that i386 guests need.
- `os_cross_arch_is_supported(OS_CROSS_ARCH_X86_64)` (macOS 26.6), which reports whether the
  kernel offers these features.
- Entitlement: `com.apple.developer.cross-architecture-support` (paid account) or
  `…-unmanaged` (free account). It needs an App ID, a provisioning profile embedded in a `.app`
  that contains the Wine loader, and per [S7] "your Mac's provisioning UDID" registered. Apple has
  no public documentation for either entitlement (searched 2026-10-13).
- Hardened runtime: FEX's JIT needs `MAP_JIT` with per-thread `pthread_jit_write_protect_np`
  toggling and `com.apple.security.cs.allow-jit`, which our `src/entitlements/wine.plist` already
  grants [S18]. FEX-darwin patches FEX for Darwin's JIT write scopes and 16 KB alignment [S12].

**Maturity, 2026-10-13.**
- CrossOver Preview: works but "very unpolished"; its Wine and FEX sources are not published (the
  CodeWeavers source page offers only 26.3.0) [S4][S19].
- FEX-darwin: 6 days old, 0 stars, needs Wine hooks [S12].
- Madeira (iOS, GPL-3.0 changes): runs i386 games through WoW64 with a 4 GB "guest window" per
  32-bit process, because iOS cannot remap PAGEZERO [S17].
- Upstream Wine and upstream FEX: nothing yet [S11][S13].

**i386.**
- **Fact:** supported by design (Wine 9.0+ WoW64 with an emulator DLL), and in production on Linux
  ARM64 (CrossOver, Proton ARM64, Hangover) [S4][S14][S20].
- **Not shown publicly:** a 32-bit game running on the macOS preview. Neither CodeWeavers nor
  anyone else has reported one.

**x87.** FEX has two modes [S11]:
- default `X87ReducedPrecision=false`: full 80-bit, SoftFloat-3e calls out of the JIT. Accurate
  but slow.
- `X87ReducedPrecision=true`: host 64-bit doubles, the same approach as x87sidecar, which also
  does binary64 arithmetic [S16b]. Fast; FEX warns it "may result in rendering bugs".

See §7 for why the fast mode should suit SWG.

**Licensing.**
- Wine LGPL-2.1+; FEX MIT; FEX-darwin MIT; DXMT zlib.
- CrossOver's Wine changes are LGPL, but CodeWeavers publishes them only with releases.
- A FEX fork inside CrossOver is MIT, so CodeWeavers has no obligation to publish it.
  **Speculation:** they probably will, as they did with their past FEX integration work on Linux.

**Effort.** Large, but the same kind of work this repo already does: build Wine from pinned
sources, carry `winemac-swg.patch`, build d9mt, sign and notarize. New work: FEX and its Wine
hooks, the entitlement and provisioning profile, and arm64 builds of everything.

**Risks.**
- The entitlement may not be grantable for Developer ID distribution to arbitrary users. The
  UDID wording in [S7] sounds like a development profile.
- CodeWeavers' sources may slip past early 2027.
- FEX performance on SWG may be lower than Rosetta + x87sidecar: no AOT, so first-time code paths
  JIT during zone loads, which matters because the hitches in #4 are translated game code.
- Apple could withdraw the cross-arch kernel features with Rosetta. **Speculation:** unlikely,
  since Apple added them in 26.4 to 26.6 specifically "for compatibility layers".

### 4.2 Rank 2 (hedge, not a plan): stay on Rosetta via the macOS 28 games subset

- **Feasibility:** unknown until the macOS 28 beta (June 2027).
- **Effort:** none until then, then a test.
- **Risk:** high. CodeWeavers' own guidance [S6] says not to count on it, and x87sidecar may break
  even if Rosetta stays.
- **Use:** the current app keeps working on macOS 27 for as long as users stay there. The app
  should say so (milestone M1). On the first macOS 28 beta, test whether the current release
  still runs (M7).

### 4.3 Rank 3 (fallback): Linux arm64 VM with FEX + Wine + DXVK

(Detail in §4.6.) A whole Linux distribution, a VM, and GPU forwarding over virtio-gpu Venus to
MoltenVK. d9mt does not apply there; graphics would be DXVK's D3D9 on Vulkan. Feasible in
principle because Linux guests get 4K pages and FEX is mature on Linux. Heavy for users, with
unknown GPU coverage and input latency. Keep it as the fallback if §4.1 is blocked by the
entitlement.

### 4.4 Rank 4 (user-side only): Windows 11 on ARM in Parallels or UTM, with Prism

(Detail in §4.6.) Microsoft's Prism emulates i386 and x86_64 inside Windows. It is a user's own
fallback, not something we can ship: Windows licence, Parallels licence, and SWG's own Windows
launcher inside the VM. We would document it as "if the Mac app stops working".

### 4.5 Not viable on macOS (checked 2026-10-13)

| Option | Why not |
|---|---|
| **Box64 / Box32 / wowbox64** | No macOS host support or port. `wowbox64` (Box64's WoW64 DLL) hardcodes 4K pages. x87 arithmetic is always 64-bit double. Box32 is Linux 32-bit ELF only. MIT. Porting it would duplicate FEX-darwin's work with less momentum [S20]. |
| **Hangover** | Linux ARM64 only (Debian, Ubuntu, Termux). It bundles FEX + Box64 as Wine emulator DLLs; issue #97 "Apple Silicon support" was closed. LGPL [S20]. |
| **Microsoft xtajit / Prism** | Proprietary, ships only inside Windows, no licence to use it elsewhere [S21]. Wine and FEX copy its interface (`xtajit.dll`, `xtajit64.dll`) but not its code. |
| **QEMU user mode** | Only linux-user and bsd-user; no Darwin host (darwin-user was removed long ago). It emulates Unix processes, not Windows PE. x87 is accurate softfloat but slow TCG [S22]. In a VM it is only a slower FEX. |
| **Our own x87sidecar-style hook into a reduced Rosetta** | Depends on the subset existing and on undocumented runtime internals. Possible on macOS 28 only if Wine itself qualifies (§4.2). |

### 4.6 VM routes in detail

**Linux arm64 VM (Virtualization.framework, libkrun/krunkit, UTM)**

- **Translation in the guest.**
  - Apple's Linux-VM x86_64 translation is now part of macOS 27 itself. Apple: "macOS 27 directly
    integrates support for Intel binary translation, without needing to install Rosetta", and the
    availability check "always returns `.installed`". There is no statement about macOS 28 or later
    [S10]. In 2025 an Apple engineer called it "not the same use case" as the macOS translation
    environment [S29].
  - It registers only as the handler for **x86_64** ELF [S10].
  - **Speculation:** x86_64 Wine (WoW64) inside the guest could then run `SwgClient_r.exe` the way
    it does on macOS today, but whether Rosetta for Linux handles WoW64's 32-bit code segments is
    undocumented.
  - The alternative is FEX inside the guest. It is mature on Linux, and the guest gets 4K pages
    (4K guests run on Apple silicon today; the macOS 26 SDK added a 4 KB IPA granule to
    Hypervisor.framework) [S23].
  - Guest TSO through Hypervisor.framework is unverified; otherwise FEX falls back to software
    ordering [S23].
- **Graphics is the blocker.**
  - Virtualization.framework documents no 3D acceleration for Linux guests [S10].
  - krunkit/libkrun has Venus (Vulkan) forwarded to MoltenVK, but no display output on macOS hosts
    ("requires a significant amount of work", 2025-01; "we have plans", 2026-01). Venus also broke
    in 4K-page guests until a Mesa fix (krunkit #114, closed 2026-08-24) [S23].
  - DXVK master needs Vulkan 1.3 and the `geometryShader` feature, even for D3D9; upstream MoltenVK
    lacks geometry shaders [S27][S28].
  - UTM 5 beta patched MoltenVK for geometry shaders. "DXVK on Ubuntu 24.04 + FEX works. I see a
    lot of visual issues but games are booting" (osy, 2026-02-21). Its 5.0.6 notes (2026-09-24)
    still list Linux desktop Vulkan rendering failures [S24].
  - muvm, Asahi's gaming microVM, is Linux-host only and uses DRM native context, not Venus [S25].
- **d9mt does not apply** in a guest (no Metal). The chain would be Wine d3d9 (DXVK) → Vulkan →
  Venus → virglrenderer → MoltenVK → Metal: four translation layers.
- **Verdict:** a research fallback. Feasibility depends on UTM's or libkrun's GPU work; user setup
  is heavy (a Linux image, gigabytes, a VM); input and fullscreen pass through a VM window; and
  latency is unmeasured [S24]. Effort is large and mostly outside our control.

**Windows 11 on ARM VM**

- Prism emulates i386 (WoW64) and x86_64 (ARM64EC) [S21].
- Parallels documents "DirectX graphics up to version 11.1"; D3D9 has been supported via Metal
  since Parallels 15 (2019). No current Apple-silicon D3D9 test was found [S26].
- Microsoft authorizes Windows 11 Pro/Enterprise on Arm in Parallels (one licence per instance)
  [S26]. VMware Fusion 13.5+ (free) has Metal DX11 [S26]. UTM's Triton DX11 driver is experimental
  and D3D11 only [S24].
- **Verdict:** something a user can do on their own, with no code from us. It is a fallback to
  document, not an app we can ship. It runs SWG's own Windows launcher, which is fine under our
  constraints since nothing is modified.

## 5. Signing, entitlement and packaging consequences (Rank 1 route)

- **The entitlement.** The arm64 Wine loader has to be signed with
  `com.apple.developer.cross-architecture-support` and ship inside a `.app` that embeds a
  provisioning profile [S7]. We already sign and notarize with Developer ID (team 3JT82CY6ZK).
  - **Unknown:** whether Apple issues this entitlement in a *Developer ID* provisioning profile,
    which covers any Mac, or only in development profiles tied to registered UDIDs. The wine-devel
    post mentions registering "your Mac's provisioning UDID" [S7], which would not work for a
    public release.
  - **Inference:** CrossOver Preview is distributed to the public, so CodeWeavers must have a
    distribution route. Inspecting their signed app answers this (M3).
- **The Game Mode bundle must be redesigned.**
  - Today `enable_game_mode` copies the x86_64 loader into
    `~/Library/Application Support/SWGLonMac/GameMode/SWGLGame.app` at run time, *unsigned*.
  - A loader that needs a restricted entitlement and an embedded profile cannot be an unsigned
    copy. The game bundle would have to be a signed, profile-carrying `.app` shipped inside the app
    (`Contents/Helpers/SWGLGame.app`), and macOS must still accept it with
    `LSSupportsGameMode`.
  - The `winetemp-…` link trick (CrossOver hack 22144) must still exist in the arm64 Wine we
    build. Both points need a prototype (M5).
- **`src/entitlements/wine.plist`** stays as it is (allow-jit, unsigned executable memory, library
  validation off) plus the new entitlement. x87sidecar and `ROSETTA_X87_PATH` go away on the arm64
  path.
- **Minimum macOS.**
  - The arm64 path needs 26.5 or later: x18, 4K spawn, TSO [S7]. `os_cross_arch_is_supported()`
    needs 26.6.
  - The README says macOS 26 or later. Either keep shipping the x86_64 Wine for 26.0–26.4 (as
    CrossOver's universal build does [S4]) or raise the minimum. **Recommendation:** ship both
    while macOS 27 lasts and pick the engine at run time. That roughly doubles the Wine part of the
    app, which is already most of its size.

## 6. Graphics path under each option

d9mt today: an i386 or x86_64 PE `d3d9.dll` (a DXVK-derived D3D9 front end) records Metal work
and calls `winemetal.dll`, which makes Wine unix calls into `winemetal.so` on the macOS side. That
library drives Metal and compiles D3D9 shaders to AIR with LLVM. The bridge is DXMT's `winemetal`
(upstream commit 964f1308, 2026-06-22) with additive d9mt entries, and it already exports a WoW64
thunk table (`__wine_unix_call_wow64_funcs`; `work/d9mt-swg/bridge`, checked 2026-10-13).

| Option | `d3d9.dll` (32-bit client) | `d3d9.dll` (64-bit client) | Unix side | Work for us |
|---|---|---|---|---|
| Today (Rosetta) | i386, under Rosetta | x86_64, under Rosetta | x86_64 `winemetal.so` under Rosetta | — |
| **Rank 1: arm64 Wine + FEX** | **i386, emulated by FEX.** Wine has no i386 hybrid (CHPE) code, so an i386 process cannot have native code in its PE DLLs [S14 precedent: Proton puts i386 DXVK in syswow64]. Unix calls go through WoW64 thunks into native code | **ARM64EC or ARM64X, native.** The x86_64 game calls it through ARM64EC entry thunks. The DXVK code already guards x87 setup with `!defined(__arm64ec__)` (`d3d9_device.cpp`) | **aarch64 `winemetal.so`, native**, including the LLVM shader compiler. That speeds up shader compiles compared with today | Rebuild the bridge and LLVM for arm64; build the PE side with llvm-mingw's arm64ec target. DXMT already ships this exact layout in CrossOver Preview (aarch64 `winemetal.so`, i386 and aarch64 PE) [S15] |
| Rank 2: Rosetta subset | unchanged | unchanged | unchanged | none, if it works at all |
| Rank 3: Linux VM | d9mt unusable (no Metal). DXVK d3d9 → Vulkan → Venus → MoltenVK → Metal | same | n/a | Different stack. Depends on GPU work in UTM or libkrun [S23][S24][S27] |
| Rank 4: Windows VM | Parallels' or VMware's own D3D driver | same | n/a | none (user-side) |

Consequences for d9mt on the Rank 1 route:
- On the 32-bit path, every CPU instruction d9mt spends in `d3d9.dll` (state tracking, constant
  uploads, command recording) runs emulated, as it does now under Rosetta. Work that moves behind
  the unix call boundary becomes native. d9mt already batches render commands into `wmtcmd` chains
  that the unix side replays, so the boundary is in a good place.
  - **Inference:** pushing more of the per-draw work into the unix side pays off more under FEX
    than it does under Rosetta.
- **4K pages and the low 4 GB.** d9mt's occlusion-query buffer uses VirtualAlloc'd memory so that
  a 32-bit process can address it (`02e7a66`), and the unix side wraps such memory with
  `newBufferWithBytesNoCopy`.
  - **Unknown:** Metal's alignment rule for no-copy buffers in a process spawned with 4K pages. On
    16K-page macOS, Metal requires page-aligned memory. Test this in M4.
- `winemac-swg.patch` has no architecture-specific code (grep, 2026-10-13). It should rebase onto
  an arm64 Wine tree with only API drift.

## 7. 32-bit client vs a future 64-bit client

**32-bit `SwgClient_r.exe` (the client that matters; WoW64)**
- **What is emulated.** The game, all of Wine's i386 DLLs (kernel32, user32, gdi32, dinput, dsound,
  the 32-bit ntdll) and d9mt's i386 PE side, all through FEX's `libwow64fex.dll` loaded as
  `xtajit.dll`. Native: `wow64*.dll`, the 64-bit (aarch64) ntdll, and every Unix `.so`.
- **Address space.** A 32-bit process needs the below-4 GB range. arm64 macOS enforces a 4 GB
  PAGEZERO, and there are two ways around it:
  - CodeWeavers resize PAGEZERO (`-x86_64_layout_emulation`) [S7];
  - Madeira and FEX-darwin give each 32-bit process a 4 GB "guest window" elsewhere and offset every
    pointer [S12][S17].

  neutron, another arm64 Wine + FEX project, gave up on 32-bit games ("Their exe has to load below
  4 GB and arm64 macOS does not allow anything there") [S30]. **This is the riskiest technical
  point.** SWG already runs close to its 4 GB limit (d9mt's `DIAG MEM`), so a guest window that
  loses address space would hurt.
- **x87.**
  - SWG is a 2003-era client and its float math is x87. Today x87sidecar JITs x87 to binary64
    (53-bit) arithmetic and keeps registers in 80-bit [S16b].
  - FEX's fast mode (`X87ReducedPrecision`) also uses binary64, and FEX "ignore[s] the rounding
    precision" [S11]. FEX's default mode is accurate 80-bit softfloat but "performance can
    nosedive" for x87-heavy games [S23 via FEX blog].
  - d9mt's `SetupFPU()` sets the x87 control word to 24-bit precision unless the game passes
    `D3DCREATE_FPU_PRESERVE` (`work/d9mt-swg/driver/d3d9/d3d9_device.cpp:86`, as on Windows). We do
    not yet know whether SWG passes it (M2).
  - **Inference:** with 24-bit precision control, real x87 rounds every result to single precision.
    Binary64 arithmetic is more precise than the hardware, not less, so the fast mode should be
    visually indistinguishable. That is the same trade-off x87sidecar makes today. Verify on screen
    (M3/M8).
- **Performance.**
  - Rosetta translates ahead of time (AOT) and caches; FEX JITs, with an optional code cache that
    Proton enabled in 2026 [S14].
  - The zone and room hitches in #4 are already ~86% translated game code on the main thread.
  - **Speculation:** first-time code paths cost more under FEX, so hitches could get worse until
    its cache is warm. The WoW64 thunking that exists today stays.

**64-bit client (`SwgClient_Latest-x64.exe`; QA only; we have no access and will not ask again)**
- **ARM64EC.** Only the game's own x86_64 code is emulated (`libarm64ecfex.dll` as
  `xtajit64.dll`). Wine's DLLs are native ARM64EC, and so is d9mt's `d3d9.dll` if built ARM64EC.
- **No x87.** x86_64 float math is SSE, which FEX translates directly. There is no WoW64 thunking
  and no below-4 GB problem.
- **Inference:** clearly the better client on arm64, likely better than today's Rosetta + x87sidecar
  path.
- We cannot test it. We can prepare by running x86_64 D3D9 stand-ins (`work/x64-test`: readback and
  shader tests) under ARM64EC with an ARM64EC d9mt. Issue #6 stays as it is.

## 8. Recommended staged plan

Each milestone below is written so it can be filed as its own issue on jdrly/swgl-on-mac (or on
jdrly/d9mt where marked; d9mt changes go through PRs there). Nothing here involves SWG Legends.

### Stage 0: now, on macOS 27 with Rosetta (Oct to Dec 2026)

**M1: Post-Rosetta preflight and user messaging** (small, ship in the next release)
- Before starting Wine, check that x86 translation works (`arch -x86_64 /usr/bin/true`). If it
  fails, distinguish "Rosetta not installed" (macOS 27 does not keep it across the upgrade [S9])
  from "this macOS no longer supports Rosetta" (major version ≥ 28), and show a clear alert
  instead of a silent failure.
- Add to `swgl_system_info` and Collect Logs: macOS major version, Rosetta state,
  `os_cross_arch_is_supported(OS_CROSS_ARCH_X86_64)` (a few lines of Swift or C in the native
  launcher), and `x87sidecar --probe`'s verdict.
- README: say that macOS 28 support depends on a future arm64 build and that users should not
  upgrade until the app announces it.
- Done when: the app explains every Rosetta failure mode in one alert, and logs show the cross-arch
  state.

**M2: Spike: baseline measurements under Rosetta**
Needed so every later arm64 result has a reference.
- Fixed test routes (a city, a building interior with an elevator, a zone change) with
  `D9MT_PROFILE=1`: FPS, 1% lows, hitch count and length. Run with `X87=on` and `X87=off`; the
  stock-Rosetta x87 cost is a proxy for FEX's accurate mode.
- x87sidecar's sampling and block profilers: what share of the main thread is x87 code.
- Record whether SWG passes `D3DCREATE_FPU_PRESERVE` (log `BehaviorFlags` at `CreateDevice`; d9mt
  prints `behavior=0x…` at info level).
- Peak address-space use (`DIAG MEM`).
- Done when: a results table sits in this note or the issue.

**M3: Spike: SwgClient_r.exe on CrossOver Preview ARM64 (Wine arm64 + FEX WoW64)**
This is the "does the i386 route work on macOS at all" test.
- Download only with Jan's explicit OK: the CrossOver Preview (trial), noting file name, source and
  size.
- Use a fresh 64-bit arm64 bottle and an APFS clone of the game folder, never redistributed and
  never modified. Jan logs in himself.
- Run with wined3d (CrossOver has no D3D9 Metal path). Compare against the same Preview's Intel
  build under Rosetta on the M2 routes.
- Check: does the client start; does i386 under FEX hold up in the low 4 GB; x87 visual
  correctness; CPU cost; hitches.
- Read CrossOver's signing: `codesign -d --entitlements -` on its arm64 Wine loader and
  `security cms -D` on its `embedded.provisionprofile`. Is it a Developer ID profile without
  device UDIDs? That answers the biggest unknown in §5.
- Done when: a written go/no-go for i386-via-FEX on macOS, plus the entitlement answer.

**M5 (research part): Entitlement application**
- In the developer account, check whether the "Cross-Process/Cross-Architecture" capability can be
  enabled for an App ID on team 3JT82CY6ZK, and for which profile types.
- If unclear, ask Apple DTS (a code-level support request) whether
  `com.apple.developer.cross-architecture-support` is available for Developer ID distribution.
- Done when: we know whether a public, notarized build can carry the entitlement.

### Stage 1: port what we own (Nov 2026 to Mar 2027, partly parallel)

**M4: d9mt on arm64** (jdrly/d9mt PR)
- Build `winemetal.so` and the airlib LLVM compile core for **aarch64** (LLVM 15 for arm64; d9mt's
  AIR compiler prototype already builds as an arm64 host tool). Keep the WoW64 thunk table.
- Build `d3d9.dll` and `winemetal.dll` as **ARM64EC** or ARM64X with llvm-mingw for 64-bit
  clients. The i386 builds are unchanged.
- Test against CrossOver Preview's arm64 Wine first (DXMT proves the unixlib ABI works there), with
  d9mt's i386 and x64 readback and shader tests. Then run `SwgClient_r.exe` on d9mt arm64 vs
  wined3d (M3).
- Check `newBufferWithBytesNoCopy` alignment in a 4K-page process, and that the 32-bit occlusion
  buffer stays below 4 GB.
- Done when: the d9mt test suite passes under arm64 Wine for i386 and ARM64EC, and SWG renders.

**M5 (prototype part): Signed arm64 loader bundle and Game Mode**
- A minimal arm64 "loader" `.app` with the entitlement and an embedded profile that spawns itself
  with `posix_spawnattr_set_4k_page_size_np` and enables `thread_set_x86_64_compat`. It must pass
  `release.sh` (Developer ID, hardened runtime, notarization) and run on a second Mac that is not
  registered anywhere.
- Redesign `enable_game_mode` around a signed `SWGLGame.app` inside the app bundle.
- Done when: a notarized test app gets Game Mode and the cross-arch features on a clean Mac.

### Stage 2: our own arm64 engine (from the first public source, about Q1 to Q2 2027)

**M6: Build arm64 Wine + FEX ourselves**
- Trigger: CodeWeavers publishes CrossOver 27 sources (LGPL Wine with the macOS arm64 work), *or*
  Shanks' MRs land upstream, *or* athei/wine-build publishes an arm64 build. Ask athei early; the
  maintainer of x87sidecar loses that project to the same deadline.
- Pin and checksum the sources as `build.sh` does today. Unix side aarch64; PE side
  aarch64 + arm64ec + i386.
- FEX: CodeWeavers' fork if published, otherwise `dbc-hbin/FEX-darwin` pinned to a commit and
  built from source, plus the Wine hooks it needs. Set the WoW64 and ARM64EC registry keys in the
  prefix.
- Rebase `winemac-swg.patch`. Rebuild `swgl-dpapi.exe` (stays i386 PE; fine under FEX).
- `build.sh`: ship x86_64 Wine (Rosetta, macOS < 26.5/26.6) and arm64 Wine side by side, chosen at
  run time by `os_cross_arch_is_supported` plus the OS version. Or raise the minimum macOS.
- Done when: `build.sh` produces a notarized app that plays SWG on macOS 27 with Rosetta
  *uninstalled* (verified in a macOS VM or on a test volume).

**M8: x87 fidelity and FEX performance for SWG**
- Run the M2 routes under FEX in accurate and reduced-precision x87 modes. Check for visible
  artifacts (terrain seams, animation jitter, UI layout, physics). Measure hitches with and without
  FEX's code cache.
- If reduced precision is clean, make it the default for `SwgClient_*.exe`. If performance falls
  short of the M2 baseline, look at contributing x87 fusion ideas from x87sidecar (MIT) to FEX's
  binary64 x87 path, upstream or in our pinned fork.
- Done when: a measured default configuration exists, and the gap to Rosetta is documented.

### Stage 3: macOS 28 beta (WWDC27, ~June 2027)

**M7: macOS 28 beta test matrix and ship decision**
- Never upgrade the main machine. Use a separate APFS volume or a macOS 28 VM.
- Test: (a) the current Rosetta release, to see whether the games subset covers it and whether
  x87sidecar's probe passes; (b) the arm64 build from M6; (c) the beta SDK, to see whether
  `os/arch/arm64.h` and the cross-arch APIs still exist and are unchanged.
- Read the release notes for Rosetta and cross-architecture changes.
- Decide within two weeks of beta 1 which engine ships for macOS 28. Release before macOS 28 GA
  (~September 2027).

### Fallback (only if M3 or M5 fail)

**M9: Fallback documentation and VM watch**
- If the entitlement cannot be distributed, or i386 cannot work under arm64 macOS: document
  "stay on macOS 27", and a Windows-on-ARM-VM route users can set up themselves (Parallels or
  VMware with SWG's own Windows launcher).
- Track UTM and libkrun GPU work for a Linux-VM route.
- Do not build a VM product unless both earlier routes are closed.

### Decision dates
- **2027-04-30:** if no public arm64 Wine tree with the macOS work exists by then (CodeWeavers
  source, upstream, or athei), build M6 on FEX-darwin plus a community Wine (Madeira's
  `willfaust/wine` is iOS-specific; neutron is 64-bit-only by design and was created on
  2026-10-09), or
  accept "stay on macOS 27" for the macOS 28 launch.
- **WWDC27 + 2 weeks:** M7 decision.

## 9. What to track (watch list and triggers)

Check monthly; record each check as a dated comment on the tracking issue.

| Id | Watch | Where | Trigger and action |
|---|---|---|---|
| W1 | CrossOver 27 release and its source tarball | codeweavers.com/crossover/source, the CodeWeavers blog | Source published → start M6 on it |
| W2 | Shanks' arm64-macOS MRs (x18, 4K spawn, TSO, PAGEZERO); !11638 | gitlab.winehq.org MRs by bshanks; Wine release notes | Merged → consider upstream Wine for M6 |
| W3 | FEX macOS support: CodeWeavers' fork, `dbc-hbin/FEX-darwin`, upstream FEX | GitHub | First buildable fork with matching Wine hooks → M6 candidate |
| W4 | DXMT release with ARM64EC/ARM64X and aarch64 `winemetal.so` | `gh release list -R 3Shain/dxmt` | Reference for M4; rebase the bridge |
| W5 | athei/wine-build and x87sidecar plans for arm64 | GitHub | arm64 build appears → reuse it instead of our own Wine build |
| W6 | Apple documentation of the cross-architecture entitlement, or its definition of the games subset | developer.apple.com news, entitlement reference | Changes M5 / §4.2 |
| W7 | macOS 27.x point releases removing or changing Rosetta | release notes; the M1 preflight in the field | User-facing message |
| W8 | macOS 28 beta 1 (WWDC27) | beta SDK headers, release notes | M7 |
| W9 | Linux-VM GPU path (UTM 5 Venus/DXVK, libkrun display) and Prism or Parallels D3D9 | UTM, libkrun releases | Only matters if M9 is triggered |
| W10 | SWG Legends making the 64-bit client public | their launcher manifest (`64bitclient`), announcements | Prioritise the ARM64EC path in M4/M6 |

## 10. What we would maintain ourselves

- **The arm64 Wine build pipeline.** Today athei/wine-build gives us a ready x86_64 tree. Unless
  athei or a successor ships arm64, building and pinning arm64 Wine (from CrossOver sources or
  upstream) becomes ours, including its compatdb or an equivalent per-process D3D9 selection.
- **FEX for macOS.** A pinned fork (CodeWeavers', FEX-darwin, or ours), its Wine hooks, its
  per-app configuration (x87 mode, TSO, code cache), and rebases when Wine moves.
- **d9mt on three architectures** (i386, ARM64EC/ARM64X PE, aarch64 Unix side), as PRs on
  jdrly/d9mt. This includes an arm64 LLVM build for the shader compiler.
- **`winemac-swg.patch`** rebased onto the arm64 Wine tree.
- **Signing.** The entitlement, provisioning profiles (renewal and expiry), a signed loader bundle,
  the Game Mode bundle, and notarization of all of it in `scripts/release.sh`.
- **Dual-engine logic** while macOS 26.x/27 users remain: run-time choice between x86_64 Wine +
  Rosetta + x87sidecar and arm64 Wine + FEX.
- **Test assets:** the M2 routes and baselines, and the d9mt test executables for both
  architectures.

## 11. Biggest unknowns (ranked by impact)

1. **Can a notarized Developer ID app carry `com.apple.developer.cross-architecture-support` for
   arbitrary users' Macs?** If not, Rank 1 is limited to development-provisioned machines or a
   free-account self-signing flow per user, which is unacceptable for a public app. (M3, M5)
2. **Does i386 via FEX work under arm64 macOS for a 4 GB-hungry 32-bit game?** Two competing
   low-memory designs exist (PAGEZERO resize vs guest window), and one project gave up on 32-bit
   [S30]. (M3)
3. **When will CodeWeavers' macOS arm64 Wine and FEX changes be public?** Upstream MRs were
   promised "soon" in August [S7]; CrossOver 27 is planned for early 2027 [S4]. One report says
   ARM64 is targeted for CrossOver 28 [S31], which conflicts with CodeWeavers' own blog [S4].
4. **FEX performance for SWG's x87-heavy main thread vs Rosetta + x87sidecar**, especially zone-load
   hitches without AOT. (M2, M8)
5. **What the macOS 28 Rosetta games subset covers**, and whether Apple keeps the cross-arch kernel
   features on macOS 28 (they were added in 26.4 to 26.6 "for compatibility layers"). (M7)
6. **Metal no-copy buffers in 4K-page processes**, and d9mt's 32-bit memory assumptions. (M4)

## 12. Sources

Dates are publication dates unless marked "checked".

- [S1] Apple Developer News, "Upcoming changes to Rosetta support for Intel-based macOS apps",
  2026-09-01. https://developer.apple.com/news/?id=w5ngl9k2
- [S2] Apple Support, "Using Intel-based apps on a Mac with Apple silicon" (HT102527), published
  2026-09-21. https://support.apple.com/en-us/102527
- [S3] Apple, "About the Rosetta translation environment" (checked 2026-10-13), which carries the
  WWDC25 wording quoted in §3.
  https://developer.apple.com/documentation/apple-silicon/about-the-rosetta-translation-environment
  Also MacRumors, "macOS 27 Golden Gate Is the Last to Support Intel Apps via Rosetta 2",
  2026-06-10. https://www.macrumors.com/2026/06/10/macos-golden-gate-last-to-support-intel-apps/
- [S4] CodeWeavers (Meredith Johnson), "CrossOver Preview: The right to bear ARM64 on Mac",
  2026-07-31. Read via the web.archive.org snapshot of 2026-08-27; the live site is behind a bot
  check.
  https://www.codeweavers.com/blog/mjohnson/2026/7/31/crossover-preview-the-right-to-bear-arm64-on-mac
- [S5] CodeWeavers (Meredith Johnson), "What's in and what's out for CrossOver 27", 2026-06-11 (via
  archive snapshot).
  https://www.codeweavers.com/blog/mjohnson/2026/6/11/whats-in-and-whats-out-for-crossover-27
- [S6] CodeWeavers (Owen Rudge), "PortJump Update: Upcoming changes to macOS support for Intel based
  applications", 2026-06-19 (via archive snapshot).
  https://www.codeweavers.com/blog/orudge/2026/6/19/portjump-update-upcoming-changes-to-macos-support-for-intel-based-applications
- [S7] Brendan Shanks, "Wine on ARM64 macOS", wine-devel, 2026-08-07.
  https://list.winehq.org/hyperkitty/list/wine-devel@list.winehq.org/thread/CKG5CEN2BE5VRXZ7O7NX4YUSBH3247WH/
  The APIs it names were checked in the macOS 27.0 SDK (Xcode 27.0, 27A266a) on 2026-10-13:
  `os/arch/arm64.h`, `spawn.h`, `mach/mach_traps.h`.
- [S8] The Mac Observer, "Rosetta Ends With macOS 27, Except When Apple Says 26 or 28", 2026-09-12.
  https://www.macobserver.com/news/rosetta-ends-macos-27-apple-pages-disagree/
- [S9] Apple Developer Forums, "Rosetta not included in macOS 27?", June 2026.
  https://developer.apple.com/forums/thread/834075
- [S10] Apple, "Running Intel binaries in Linux VMs" (checked 2026-10-13).
  https://developer.apple.com/documentation/virtualization/running-intel-binaries-in-linux-vms
- [S11] FEX-Emu: issue #5046 "Mac Support" (closed 2025-11-13),
  https://github.com/FEX-Emu/FEX/issues/5046; `Config.json.in` (`X87ReducedPrecision`) and
  `X87F64.cpp` at HEAD (checked 2026-10-12/13); release FEX-2610 (2026-10-07).
- [S12] dbc-hbin/FEX-darwin README, repo created 2026-10-07 (checked 2026-10-13).
  https://github.com/dbc-hbin/FEX-darwin
- [S13] Wine GitLab merge requests !11267, !11402, !11668, !11736 (merged 2026-07 to 08), !12257
  (closed), !11638 (open), checked 2026-10-13. https://gitlab.winehq.org/wine/wine/-/merge_requests
  Also Wine loader sources (`dlls/ntdll/loader.c`, `dlls/wow64/syscall.c`) for the `xtajit` and
  `xtajit64` registry keys.
- [S14] Valve Proton, `proton_11.0` branch: `Makefile.in` (DXVK built for i386, x86_64 and arm64ec)
  and the `proton` script (ARM64EC DXVK in system32, i386 in syswow64), checked 2026-10-13.
  https://github.com/ValveSoftware/Proton/tree/proton_11.0
  Also GamingOnLinux on FEX's code cache in Proton Experimental ARM, 2026-09.
- [S15] 3Shain/dxmt: release v0.80 (2026-04-23); commits 7ef5d9ca4 (ARM64EC, 2026-03-08) and
  3b7807622 (ARM64X, 2026-08-26); issue #201 (2026-08-02), which lists the CrossOver Preview DXMT
  layout. https://github.com/3Shain/dxmt
- [S16] athei/wine-build README (checked 2026-10-13). https://github.com/athei/wine-build
  [S16b] athei/x87sidecar README (checked 2026-10-13). https://github.com/athei/x87sidecar
- [S17] willfaust/Madeira `docs/WOW64.md` and README (checked 2026-10-13); willfaust/FEX PR #2
  (merged 2026-09-28). https://github.com/willfaust/Madeira
- [S18] Apple Developer Forums, DTS on JIT under the hardened runtime, April 2026.
  https://developer.apple.com/forums/thread/821584
- [S19] macgameport/cities-skylines-2-macos issue #16 and `docs/plans/arm64-migration.md`
  (2026-10-10/11). A peer project's plan; secondary, used for leads only.
  https://github.com/macgameport/cities-skylines-2-macos/issues/16
- [S20] Box64 v0.4.4 (2026-08-02), `wine/wow64/wowbox64.c`, https://github.com/ptitSeb/box64.
  Hangover 11.16 (2026-08-30), https://github.com/AndreRH/hangover.
- [S21] Microsoft Learn, "How x86 emulation works on Arm", 2025-11-06.
  https://learn.microsoft.com/en-us/windows/arm/apps-on-arm-x86-emulation
- [S22] QEMU user-mode documentation (checked 2026-10-13).
  https://www.qemu.org/docs/master/user/main.html
- [S23] libkrun/krunkit issues #23 (2025-01 / 2026-01), #102 (2026-04), #114 (2026-08), under
  https://github.com/libkrun/krunkit/issues. Podman 6.0 (2026-06-24). FEX blog "FEX-2408"
  (2024-08-12) on x87 performance.
- [S24] UTM releases v5.0.0 to v5.0.6 (2026-01-11 to 2026-09-24) and issue #7575,
  https://github.com/utmapp/UTM. "Introducing Triton DirectX 11 driver for QEMU", 2026-07-24,
  https://blog.getutm.app/2026/introducing-triton-directx-11-driver-for-qemu/
- [S25] AsahiLinux/muvm README (checked 2026-10-13), https://github.com/AsahiLinux/muvm. Alyssa
  Rosenzweig, "AAA gaming on Asahi Linux", 2024-10-10,
  https://alyssarosenzweig.ca/blog/aaa-gaming-on-m1.html
- [S26] Parallels KB 122485 (reviewed 2026-08-25), https://kb.parallels.com/en/122485. Parallels,
  "Microsoft authorized solution" page (checked 2026-10-13),
  https://www.parallels.com/products/desktop/microsoft-authorized-solution-windows-11-arm/
  VMware Fusion team blog on DX11 (13.5).
- [S27] DXVK master, `src/dxvk/dxvk_instance.h` and `dxvk_device_info.cpp` (checked 2026-10-13).
  https://github.com/doitsujin/dxvk
- [S28] MoltenVK issues #1524 (geometry shaders) and #1588 (transform feedback); release 1.4.2
  (2026-07-24). https://github.com/KhronosGroup/MoltenVK
- [S29] Apple Developer Forums thread 787530 (June 2025) on Rosetta for Linux VMs.
  https://developer.apple.com/forums/thread/787530
- [S30] lixsldotnet/neutron README, repo created 2026-10-09 (checked 2026-10-13).
  https://github.com/lixsldotnet/neutron
- [S31] iThinkDifferent, "CrossOver Preview Lands Native ARM64 Support Ahead of Rosetta 2's End",
  2026-08-02 (claims CrossOver 28; conflicts with [S4]). https://www.ithinkdiff.com/?p=343215
