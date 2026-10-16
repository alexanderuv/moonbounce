## Commits and pull requests

Commit messages and PR titles follow Conventional Commits, and PR descriptions follow the pull request template. See `CONTRIBUTING.md`. This replaces the `[Phase N]` prefix in older history; any generic commit-format instruction gives way to it in this repo.

## Code review

Every pull request gets an independent review before it merges. The reviewer is a separate session or agent that took no part in the change. It starts from the diff and the issue it closes, not from the author's reasoning or verdict. The author can't be judge, jury and executioner: it never reviews or approves its own change. It fixes what the reviewer finds, the reviewer checks the fixes, and the loop repeats until the reviewer has no findings left.

## Public writing

This repository is public. Read `docs/agents/open-source.md` before you write or move public text (README, docs, issues, pull requests, comments). It sets the writing standard, how to mention other projects, and where each kind of content lives.

## Agent skills

### Issue tracker

Issues live in GitHub Issues for `alexanderuv/moonbounce`, managed with the `gh` CLI. See `docs/agents/issue-tracker.md`.

### Triage labels

The five default triage labels: `needs-triage`, `needs-info`, `ready-for-agent`, `ready-for-human` and `wontfix`. See `docs/agents/triage-labels.md`.

### Domain docs

Single-context: one `CONTEXT.md` and `docs/adr/` at the repo root. See `docs/agents/domain.md`.
