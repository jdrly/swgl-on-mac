# Architecture Decision Records

An ADR records a decision or a proposed direction. **Its existence does not prove that the
behaviour is implemented.** When the code and an ADR differ, the code and its checks describe
what runs; the ADR stays the target and the difference is recorded as a gap.

## Statuses

| Status | Meaning |
|---|---|
| `proposed` | Awaiting discussion; **not an implementation specification**. |
| `accepted` | The valid target contract. |
| `superseded by ADR-NNNN` | Historical context; follow its successor. |
| `deprecated` | Don't use this approach in new work. |

## When to write an ADR

Only when there were real alternatives with consequences that matter. Ask: “Will someone want
to know a year from now why this wasn't done differently?” Tool choices and style rules belong in
`CONTRIBUTING.md`, not in an ADR.

## Format

`NNNN-english-slug.md`, in English, started from [0000-template.md](0000-template.md). Never reuse
a number; keep superseded records and change their status. Write only what a source shows, and
put what isn't decided under *Open questions*.

## Records

This table is the status source of truth. Update both it and the ADR's frontmatter.

| # | Decision | Status |
|---|---|---|
| [0001](0001-official-launcher-and-client-unchanged.md) | SWGL on Mac runs SWG Legends' official launcher and client unchanged and never ships their files | `accepted` |
| [0002](0002-game-mode-bundle-at-run-time.md) | The Game Mode bundle is assembled at run time outside the app | `accepted` |
| [0003](0003-after-rosetta-arm64-wine-and-fex.md) | After Rosetta, SWGL on Mac moves to a native arm64 Wine with FEX | `proposed` |
