# SWGL on Mac agent guidance

Work one prepared issue at a time, within its scope and acceptance criteria, and take the next
one only after this one meets the Definition of Done in [`CONTRIBUTING.md`](CONTRIBUTING.md).

The documentation is the source of truth and should answer scope and design questions:
[`CONTEXT.md`](CONTEXT.md), the decisions in [`docs/adr/index.md`](docs/adr/index.md) and the
[README](README.md) (behaviour, how it works, building, releasing). `notes/` holds plans and
research, not specifications. Look the answer up there before asking or choosing an approach of
your own.

- SWG Legends' launcher and game files are never changed, shipped or committed (ADR-0001), and
  nothing from a player's account goes into the repository, an issue or a pull request.
- The scripts run under macOS's `/bin/bash` 3.2: no bash 4 features.
- Never start the game or a Wine window on the maintainer's screen while they may be playing.
- Work on a branch and open a pull request into `main`. Never push to `main`, tag, or create
  releases, issues or labels without the maintainer's approval: this repository is public.

## Agent skills

### Issue tracker

GitHub issues in `jdrly/swgl-on-mac`. See [`docs/agents/issue-tracker.md`](docs/agents/issue-tracker.md).

### Triage labels

Vocabulary: `needs-triage`, `needs-info`, `ready-for-agent`, `ready-for-human`, `wontfix`, plus
type and area labels. See [`docs/agents/triage-labels.md`](docs/agents/triage-labels.md).

### Domain docs

Single context: root `CONTEXT.md` plus `docs/adr/`. See [`docs/agents/domain.md`](docs/agents/domain.md).
