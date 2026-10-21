## What changes

<!-- Two to five sentences: what this PR does and why, not a list of files. -->

Closes #

- **ADR:** none <!-- or docs/adr/NNNN-… -->

## How to verify

<!-- Steps for the reviewer: the Mac, the starting state, what to click, which log line shows it. -->

## Definition of Done

- [ ] `shellcheck -S warning` and `/bin/bash -n` (macOS's bash 3.2) on the scripts, `actionlint` on the workflows, and `./build.sh` pass locally; the Checks workflow's app checks pass.
- [ ] A change to updates is tested with `scripts/test-update.sh`.
- [ ] A bug fix has a regression check that fails without the fix (a test script where one can reach it; otherwise the manual check is described above).
- [ ] No log or Collect Logs file gains the password, account name, e-mail address, user name or serial numbers; `legends.cfg` and `launchersettings.ini` are never collected.
- [ ] SWG Legends' launcher and game files stay unchanged and are never shipped.
- [ ] A new d9mt pin is a d9mt commit that met d9mt's Definition of Done, and updates `prebuilt/d9mt` and the README's *d9mt* section together.
- [ ] The README describes the new behaviour; terms follow `CONTEXT.md`, and a new term is added in this PR.
- [ ] A changed decision has an ADR in this PR, or links an existing `accepted` ADR.
- [ ] An independent review found no open `Blocker` or `High`.
- [ ] The issue's UAT scenario has been clicked through and ticked off in the issue.

## Risks and what I didn't do

<!-- Known limits, deferred work, effects on existing installs and the game folder. An empty field is an answer too: write "none". -->
