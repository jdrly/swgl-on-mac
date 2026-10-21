# Triage labels

The skills speak in terms of five canonical triage roles. This file maps those roles to the
label strings of this repository's issue tracker, and lists the type and area labels next to
them.

> **Proposed vocabulary.** The labels marked _new_ do not exist on GitHub yet; the maintainer
> creates them. Until then GitHub ignores them in the issue forms.

## Triage state (exactly one on an open issue)

| Label in mattpocock/skills | Label in our tracker | Meaning                                          | Exists |
| -------------------------- | -------------------- | ------------------------------------------------ | ------ |
| `needs-triage`             | `needs-triage`       | The maintainer needs to evaluate this issue      | _new_  |
| `needs-info`               | `needs-info`         | Waiting on the reporter for more information     | _new_  |
| `ready-for-agent`          | `ready-for-agent`    | Fully specified, ready for an AFK agent          | _new_  |
| `ready-for-human`          | `ready-for-human`    | Needs a human: a decision, hardware or the game  | _new_  |
| `wontfix`                  | `wontfix`            | Will not be actioned                             | yes    |

When a skill mentions a role (for example "apply the AFK-ready triage label"), use the label
string from this table. An issue is `ready-for-agent` only when its verification can be done
without a person at the Mac; anything that needs the game played, a real GPU run or a
maintainer's decision is `ready-for-human`.

## Type (exactly one)

| Label            | Meaning                                                   | Exists |
| ---------------- | --------------------------------------------------------- | ------ |
| `bug`            | Something doesn't work as the README describes            | yes    |
| `enhancement`    | New or better behaviour                                   | yes    |
| `performance`    | Frame rate, stutter, pacing                               | yes    |
| `investigation`  | Research or measurement; the findings go into the issue   | yes    |
| `documentation`  | Only the docs change                                      | yes    |

## Area (one or more)

| Label            | Meaning                                                                   | Exists |
| ---------------- | ------------------------------------------------------------------------- | ------ |
| `d9mt`           | Needs a change in jdrly/d9mt (via PR)                                     | yes    |
| `infrastructure` | Build, release, signing, updates                                          | yes    |
| `rosetta`        | Life after Rosetta (macOS 28+)                                            | yes    |
| `area:app`       | The welcome window, the menus, Settings (`src/native/`)                   | _new_  |
| `area:wine`      | The bundled Wine, the prefix, the Mac driver patches, Game Mode (`src/common.sh`, `patches/`) | _new_  |
| `area:launcher`  | Running the launcher, the saved password, first run                       | _new_  |
| `area:logs`      | Collect Logs, Debug Mode (`src/collect-logs.sh`)                          | _new_  |
