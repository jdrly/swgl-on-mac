# Triage labels

The skills speak in terms of five canonical triage roles. This file maps those roles to the
label strings of this repository's issue tracker, and lists the type and area labels next to
them.

## Triage state (exactly one on an open issue)

| Label in mattpocock/skills | Label in our tracker | Meaning                                          |
| -------------------------- | -------------------- | ------------------------------------------------ |
| `needs-triage`             | `needs-triage`       | The maintainer needs to evaluate this issue      |
| `needs-info`               | `needs-info`         | Waiting on the reporter for more information     |
| `ready-for-agent`          | `ready-for-agent`    | Fully specified, ready for an AFK agent          |
| `ready-for-human`          | `ready-for-human`    | Needs a human: a decision, hardware or the game  |
| `wontfix`                  | `wontfix`            | Will not be actioned                             |

When a skill mentions a role (for example "apply the AFK-ready triage label"), use the label
string from this table. An issue is `ready-for-agent` only when its verification can be done
without a person at the Mac; anything that needs the game played, a real GPU run or a
maintainer's decision is `ready-for-human`.

## Type (exactly one)

| Label            | Meaning                                                   |
| ---------------- | --------------------------------------------------------- |
| `bug`            | Something doesn't work as the README describes            |
| `enhancement`    | New or better behaviour                                   |
| `performance`    | Frame rate, stutter, pacing                               |
| `investigation`  | Research or measurement; the findings go into the issue   |
| `documentation`  | Only the docs change                                      |

## Area (one or more)

| Label            | Meaning                                                                   |
| ---------------- | ------------------------------------------------------------------------- |
| `d9mt`           | Needs a change in jdrly/d9mt (via PR)                                     |
| `infrastructure` | Build, release, signing, updates                                          |
| `rosetta`        | Life after Rosetta (macOS 28+)                                            |
| `area:app`       | The welcome window, the menus, Settings (`src/native/`)                   |
| `area:wine`      | The bundled Wine, the prefix, the Mac driver patches, Game Mode (`src/common.sh`, `patches/`) |
| `area:launcher`  | Running the launcher, the saved password, first run                       |
| `area:logs`      | Collect Logs, Debug Mode (`src/collect-logs.sh`)                          |
