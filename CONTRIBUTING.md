# Contributing

Thanks for helping with SWGL on Mac.

- **Bugs:** open a [bug report](https://github.com/jdrly/swgl-on-mac/issues/new/choose) with
  the Collect Logs zip (SWGL on Mac → Collect Logs…), or contact Pharaphobia on
  [Discord](https://discord.gg/AnV3fZWz2b). Never send them to the SWG Legends team: they don't
  support SWGL on Mac.
- **Pull requests** are welcome. For anything larger than a small fix, open an issue first so we
  can agree on the approach. The rest of this file is how work is specified, reviewed and
  merged.

By contributing you agree that your contribution is licensed under the [zlib license](LICENSE),
like the rest of the code; changes to `patches/winemac-*.patch` are changes to Wine and stay under
Wine's LGPL-2.1-or-later.

## Before you start

```bash
gh auth status   # GitHub authentication
```

Read [CONTEXT.md](CONTEXT.md). Without it you are likely to introduce synonyms that come back in
review.

## Sources of truth and reading order

1. **[CONTEXT.md](CONTEXT.md)**: the terms to use.
2. **[docs/adr/](docs/adr/index.md)**: accepted decisions. An ADR with status `accepted` is the
   target contract even when the code differs. Record the difference as a gap; **don't weaken an
   ADR to match the current code**. A `proposed` ADR is not a specification.
3. **[README.md](README.md)**: what the app does today, how it works, how it is built and
   released.
4. **[release-notes/README.md](release-notes/README.md)**: the release notes format.
   **[notes/](notes/)**: plans and research (the Rosetta sunset plan, Game Mode), not
   specifications.
5. **The code**: `src/common.sh` (paths and the shared shell code), `src/native/` (the welcome
   window and the menus), `src/collect-logs.sh`.

If two sources conflict, report the conflict instead of silently choosing one.

## Issues

- Every change that isn't trivial starts from an issue. Players report with the **bug report**
  or **idea** forms; planned work is written as a **task**, a precise specification.
- Titles use `Context: Actionable result`, for example
  `Mouse-look: Keep the camera speed after alt-tab`. The issue, the pull request and the squash
  commit carry the same title. A release PR starts with its version (`0.0.5: …`).
- The area is a label, never a title prefix (see
  [docs/agents/triage-labels.md](docs/agents/triage-labels.md)).
- *Affected areas* lists only paths you have verified in the repository.
- *Verification (UAT)* is a scenario a non-technical player can click through on their Mac: each
  step is an action and, after the arrow, the expected result.

## Branches

- Never push directly to `main`. Every change goes through a pull request into `main`.
- Name the branch `<type>/<issue>-<short-description>`, in English `lower-case-kebab-case`, for
  example `fix/25-macos26-metallibs`. Types: `feat`, `fix`, `perf`, `test`, `chore`, `docs`,
  `release` (a version bump). A change without an issue leaves out the number.
- One branch is one issue. If separate work turns up, open another issue.

## Commits

- Write commit messages in **English**, in the imperative (`add`, `fix`, `remove`; not `added`
  or `adding`).
- The subject follows the title form, `Context: what the commit does`, for example
  `Release notes: link the Discord invite in Support`. No emoji, no scope tags.
- Add a body when the why isn't obvious: the evidence, what was measured, what was not done.
  Several focused commits are fine; they are squashed on merge.

## Pull requests

- The PR title is **identical to the issue title**.
- Fill in the [template](.github/PULL_REQUEST_TEMPLATE.md), with `Closes #<issue>`.
- Keep the PR a **draft** until it meets the Definition of Done.
- Keep changes focused: don't mix a change with unrelated refactoring, which gets its own issue
  and PR. Update the README when behaviour changes.
- Merge with **squash**; the squash commit's subject is the PR title.

## Code review

- Read the issue and its UAT before the diff.
- Classify every finding by severity. `Blocker` and `High` prevent the merge; `Medium` and
  `Low` may merge with a follow-up issue.

  | Severity | Meaning |
  |---|---|
  | `Blocker` | The pull request must not merge until it is resolved. |
  | `High` | Materially wrong behaviour, or a hard project-rule violation. |
  | `Medium` | Significant duplication, overengineering or maintainability risk. |
  | `Low` | Local cleanup that can go with related work. |

- In this project a finding is a `Blocker` by default when it can **change or lose the player's
  game files or saved password**, **put account data into a log or the Collect Logs zip**, or
  **break the update path** (the feed, its signature, the app's relaunch). A player can't recover
  from those by installing the next version.
- A finding describes **one problem with one fix boundary**, not one affected file.
- Findings stay in the pull request as review threads; never commit a review ledger. Decisions
  that should outlive the review (accepted risks, deferred work) go into the PR description.

## Definition of Done

A change is done only when all of these hold:

- [ ] `shellcheck -S warning` (with the repository's `.shellcheckrc`) and `bash -n` with macOS's
      `/bin/bash` 3.2 on the scripts, `actionlint` on the workflows, and `./build.sh` pass
      locally. The Checks workflow runs the same and checks the app: the Info.plists, the files
      it must contain, its size, the minimum macOS of every binary, d9mt's Compat metallibs.
- [ ] A change to updates (Sparkle, the feed, `release.sh`) is tested with
      `scripts/test-update.sh`.
- [ ] A bug fix has a regression check that fails without the fix: a test script where one can
      reach it, otherwise a manual check written in the PR.
- [ ] No log or Collect Logs file gains the password, account name, e-mail address, user name or
      serial numbers; `legends.cfg` and `launchersettings.ini` are never collected
      (`src/collect-logs.sh`).
- [ ] SWG Legends' launcher and game files stay unchanged and are never shipped (ADR-0001).
- [ ] A new d9mt pin is a d9mt commit that met d9mt's Definition of Done (hash suite equal to
      base, nothing measurably slower), and changes `prebuilt/d9mt` and the README's *d9mt*
      section together.
- [ ] The README describes the new behaviour. Terms follow `CONTEXT.md`; a new term is added in
      the same PR.
- [ ] A changed decision has an ADR in the same PR, or links an existing `accepted` ADR.
- [ ] An independent review (by someone, or an agent, that didn't write the change) found no open
      `Blocker` or `High`.
- [ ] The issue's UAT scenario has been clicked through and ticked off in the issue.

_Open:_ a sandbox test for Collect Logs (`scripts/test-collect-logs.sh`) exists only on the
unmerged branch `fix/port-0.1.2`; there is no automated test of the welcome window or the wrapper
yet.

## Never do these things

- Push directly to `main`.
- Ship, change or redistribute SWG Legends' launcher or game files (ADR-0001).
- Include anything from your SWG Legends account (password, account name, `legends.cfg`,
  `launchersettings.ini`) in an issue or a PR.
- Commit signing material: the Developer ID, notarization credentials or Sparkle's EdDSA key.
- Tell players to contact the SWG Legends team about SWGL on Mac.
- Add a dependency without the maintainer's approval.
- Change `CONTEXT.md` or an ADR incidentally during unrelated work.

