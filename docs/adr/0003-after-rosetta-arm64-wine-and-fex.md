---
status: proposed
date: 2026-10-21
deciders: Jan Drlý
---

# After Rosetta, SWGL on Mac moves to a native arm64 Wine with FEX

## Context

The game runs in an x86_64 Wine, so it depends on Rosetta. macOS 27 is the last release with full
Rosetta; from macOS 28 it remains only for a subset of older games that Apple has not defined, and
CodeWeavers expect Wine apps left on Rosetta not to work there (`notes/rosetta-sunset-plan.md` §1).
Tracked in #20, with milestones M1–M9 (#11–#19).

## Decision (proposed)

Rank 1 of the plan: a native arm64 Wine, with FEX translating x86 code through Wine's WoW64 layer
(i386, the 32-bit client) and ARM64EC (x86_64), and d9mt on arm64; the same design as CodeWeavers'
CrossOver Preview (`notes/rosetta-sunset-plan.md` §4.1, §8). Until a version for macOS 28 is
announced, players are told not to upgrade a Mac they play on (README, *Install*).

## Consequences

- d9mt's unix side (`winemetal.so`) and Wine's unix side become arm64; the app's signing and
  entitlements change (§5).
- The project would maintain more itself (§10).

## Alternatives considered

From `notes/rosetta-sunset-plan.md` §4:
- **Stay on Rosetta through the macOS 28 games subset** (rank 2): a hedge, not a plan; unknown
  until the macOS 28 beta.
- **A Linux arm64 VM with FEX, Wine and DXVK** (rank 3): the fallback if rank 1 is blocked; heavy
  for players, d9mt doesn't apply there.
- **Windows 11 on ARM in a VM with Prism** (rank 4): a player's own fallback, not something the
  project can ship.
- **Box64, Hangover, Microsoft's xtajit, QEMU user mode**: not viable on macOS (§4.5).

## Open questions

- **Not decided.** Decision dates: 2027-04-30 (a public arm64 Wine tree, or build on FEX-darwin
  and a community Wine, or accept “stay on macOS 27” at the macOS 28 launch), and WWDC27 + 2 weeks
  (§8).
- The biggest unknowns (§11): whether a notarized Developer ID app can carry the
  cross-architecture entitlement for any player's Mac; whether i386 through FEX works for a
  memory-hungry 32-bit game; when CodeWeavers' arm64 changes become public; FEX's speed on SWG's
  x87-heavy main thread compared with Rosetta and x87sidecar.
