# Working in public

Moonbounce is a public repository. Code, comments, docs, commit messages, issues and pull requests are all read by strangers and kept. Write for a reader who has never seen your conversation, the maintainer's notes, or the history behind the change.

## Writing

Public text is edited text: every sentence carries a fact, a decision or a reason the reader needs.

- **Lead with the point.** The first sentence says what the thing is or does. Detail follows.
- **Be concrete.** Name the type, the number, the file, the issue.
- **Say it once.** Each fact has one home (see [Where things go](#where-things-go)). Everywhere else, link to it.
- **Keep it short.** A README says what the project is, how to use it and where to go next. The roadmap outlines direction. Plans, tasks and specifications live in issues.
- **Use plain words.** "Uses", "measures", "is". Describe the subject, not the document ("This document is the plan" says nothing).
- **Claim what is true today.** Mark unfinished work as planned or in progress.

Before you post, reread as that stranger and delete every sentence they would skip.

## Framing

Moonbounce stands on its own: describe it by what it does and how it is built.

- **Justify decisions on Moonbounce's terms.** An instruction set, a platform tier or an API shape is chosen for Moonbounce's users and hardware. Cite another project only where a comparison depends on it, such as building both sides of a benchmark at the same level.

- **Other projects appear where they are used.** [Jolt Physics](https://github.com/jrouwe/JoltPhysics) is the benchmark baseline and the reference for feature scope. Name it in benchmarking and validation material and in the phase issues, neutrally and with a link.
- **Comparisons report measurements:** faster, even or slower, by how much, on which platform.
- **Credit upstream work.** Link it, and state the license of anything derived from it.

## Where things go

| Content | Home |
|---|---|
| What Moonbounce is; how to build, test and benchmark it | `README.md` |
| Where Moonbounce is heading, in a few paragraphs | `docs/roadmap.md` |
| Features, specifications, acceptance criteria | GitHub issues: one per phase, with tickets as sub-issues |
| The rules a result must meet: definition of done, platform tiers and CI gaps, measurement rules, the speed reference, scene targets and quality gates, and recorded results with one line per exception | `docs/validation.md` |
| How to run the Jolt comparison and add a benchmark to it, how the Jolt harness measures, and how the two sides stay comparable | `JoltComparison/README.md` |
| How BenchmarkRunner and the suites measure, and why | Comments in `Benchmarks/` |
| Third-party data: its source, license and checksum | `Assets/README.md` |
| Domain terms | `CONTEXT.md` |
| How agents work in this repository | `docs/agents/`; procedures an agent loads when it needs them, in `.claude/skills/` |
| Analysis of one result: profiles, causes, attempts | The issue that tracks it |
| Decisions and the reasons for them | `docs/adr/` |
| Toolchain bugs Moonbounce works around | `KNOWN_ISSUES.md` |
| Coding rules, commit and pull request format | `CONTRIBUTING.md` |
| Why a piece of code is the way it is | A comment beside the code; rules elsewhere cite it |

Each home in this table holds only what its row names. When content fits another row, move it there instead of adding it.

When you move or rename a section, update every reference to it. Search the repository and the open issues.

## Hygiene

- **Third-party code stays upstream.** The comparison script fetches Jolt's source into a git-ignored folder on each run. Third-party assets are committed only under a compatible license, with its notice beside them.
- **Commits and posts carry only project material.** Strip secrets, tokens, local paths, machine names and personal data from code, logs and benchmark output before they are committed or pasted.
- **Issues and pull requests are the permanent record.** Write them for the next contributor: what was decided and why.
- **Links in issues use absolute URLs to `main`** (`https://github.com/alexanderuv/moonbounce/blob/main/…`), because relative links don't resolve there.
