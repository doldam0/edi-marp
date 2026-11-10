# Contributing

Conventions for keeping the history of **edi · marp** readable and the
branches tidy.

## Commit messages

This repository follows [Conventional Commits](https://www.conventionalcommits.org/).

```
<type>(<scope>): <subject>

<body>

<footer>
```

- **type** — one of:
  | type | use for |
  | --- | --- |
  | `feat` | a new user-facing capability |
  | `fix` | a bug fix |
  | `perf` | a change that improves performance without changing behavior |
  | `refactor` | a code change that neither fixes a bug nor adds a feature |
  | `docs` | documentation only |
  | `style` | formatting / whitespace, no behavior change |
  | `test` | adding or fixing tests |
  | `build` | build system, dependencies, packaging (xcodegen, Vite, npm) |
  | `ci` | CI configuration |
  | `chore` | tooling, config, housekeeping |
  | `revert` | reverts a previous commit |
- **scope** (optional) — the area touched. Common scopes:
  `editor`, `preview`, `export`, `workspace`, `settings`, `engine`, `ui`, `core`.
- **subject** — imperative mood, lower case, no trailing period, ≤ 72 chars
  ("add", not "added" / "adds").
- **body** (optional) — wrap at 72 columns; explain *what* and *why*, not how.
- **footer** (optional) — `BREAKING CHANGE: …` for incompatible changes,
  issue references, and `Co-Authored-By:` trailers.

Append `!` after the type/scope for a breaking change, e.g. `feat(export)!:`.

Examples:

```
feat(editor): toggle bold/italic on ⌘B and ⌘I
fix(export): keep backgrounds in PDF/print, find nested themes
perf(editor): highlight only the edited slide
```

A commit template (`.gitmessage`) and hooks in `.githooks/` support this:
`commit-msg` checks the subject line and `pre-commit` blocks direct commits
to `main` and `dev`. Enable them once per clone:

```bash
git config commit.template .gitmessage
git config core.hooksPath .githooks
```

## Branches

Two long-lived branches, plus short-lived work branches:

| branch | role | updated by |
| --- | --- | --- |
| `main` | released code only; every commit on it is a tagged release | release and hotfix merges |
| `dev` | integration; the next release in progress, always builds | work-branch merges |

```
feat/… ─┐                      hotfix/… ─┐ (from main)
        ▼                                ▼
dev ────●──●──●───── release ──▶ main ───●── tag ──▶ merged back into dev
```

**Work branches** are cut from `dev` and named `<type>/<short-kebab-summary>`
with the same types as commits:

```
feat/system-font-panel
fix/gutter-bleed
refactor/deck-session
docs/contributing
```

- Rebase on `dev` before merging and merge with a fast-forward or squash, so
  `dev` stays linear.
- Delete the branch after it merges.
- Never commit directly to `main` or `dev`; the `pre-commit` hook in
  `.githooks/` refuses it (merges still go through).

**Releases** go from `dev` to `main`:

```bash
git switch main
git merge --no-ff dev -m "chore(release): v0.2.0"
git tag -a v0.2.0 -m "v0.2.0"
```

**Hotfixes** for a released bug are cut from `main` as `hotfix/<summary>`,
merged into `main` with `--no-ff` and tagged as a patch release, then merged
into `dev` so the fix isn't lost.

## Versions

Tag releases on `main` with [SemVer](https://semver.org/): `vMAJOR.MINOR.PATCH`
(e.g. `v0.2.0`). Before `v1.0.0` the format and API may change between minor
versions.
