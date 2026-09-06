# Contributing to The Void

Thanks for taking an interest in this project. It's primarily a solo/portfolio effort, but bug reports, suggestions, and pull requests are welcome — this doc covers how the repo is set up so a contribution can land cleanly.

Before contributing code or opening a PR, please read the [License](README.md#license) section of the README: you're granted permission to fork and modify this repository for the purpose of contributing back via PR, but not to redistribute, host, or publish the game (or its assets) elsewhere.

## Ground rules

- **Server is authoritative, always.** Combat, XP, purchases, and persistence are resolved server-side; client code only renders state and sends intent. If a PR trusts anything the client claims about game state (damage dealt, XP earned, items owned), that's a blocker, not a nitpick.
- **No new external dependencies without discussion.** Adding a Wally package (or any other third-party dependency) is a design decision, not a drive-by change — open an issue or ask in the PR description before adding one, especially anything touching player data (see `wally.toml`'s existing `ProfileStore` dependency for the bar: actively maintained, widely used, handles DataStores).
- **Match existing structure.** Server logic lives in server modules under `src/`, the client/server contract lives in `RemoteDefinitions`, and both are described in [`docs/the-void-implementation-plan.md`](docs/the-void-implementation-plan.md) Sections 3–4. New functionality should fit this shape rather than introduce a parallel pattern.
- **Found a security issue** (an exploit, a way to bypass server-side validation, a DataStore/dupe bug)? Don't open a public issue or PR — see [SECURITY.md](SECURITY.md).

## Getting set up locally

Full first-time setup (accounts, Roblox Studio, Rojo, Wally) is in [`docs/getting-started.md`](docs/getting-started.md). Once that's done, day-to-day:

1. Pull latest `main`.
2. `mise exec -- wally install` if `wally.toml`/`wally.lock` changed since your last pull.
3. `rojo serve` in the repo root, connect the Rojo plugin in Studio.
4. Edit code in your editor (not Studio's script editor) — Studio is for map/terrain/parts and for playtesting.
5. Run the automated suite before opening a PR (see below).

## Running tests

The server-logic suite runs outside Studio via [Lune](https://github.com/lune-org/lune):

```
mise exec -- lune run tests/_run.luau
```

This is also what CI (`Health checks`, `.github/workflows/test.yml`) runs on every PR targeting `main` and on pushes to `main`. A PR won't be merged with a red check.

- If you add or change server module behavior, add or update a corresponding test — see [`docs/the-void-implementation-plan.md`](docs/the-void-implementation-plan.md) Section 7.1 for what the suite currently covers and its known, documented gaps (client UI/input and `PathfindingService`-driven movement aren't exercisable outside a real Roblox client).
- Client-side changes (UI controllers, input handling) can't be covered by the automated suite — verify these manually in Studio using **Play as Server+Clients** and say so in the PR description.

## Branching and commits

- Branch off `main`; there's no long-lived development branch.
- Keep commits focused — one logical change per commit is easier to review than a single commit bundling unrelated fixes.
- Write commit messages that explain *why*, not just *what* (the diff already shows what changed).

## Opening a pull request

- Target `main`.
- Describe what changed and why, and call out anything you couldn't verify with the automated suite (e.g. "tested manually in Studio with 2 clients").
- Keep PRs scoped to one concern — a bug fix doesn't need to also refactor nearby code. Small, reviewable PRs get merged faster than large ones.
- CI (`Health checks`) must pass before merge.
- Note that publishing to Roblox (`savetoroblox` workflow) is manually triggered and separate from merging — merging a PR doesn't publish anything to staging or production.

## What NOT to include in a PR

- Anything that hardcodes or logs a secret (API keys, tokens). See [SECURITY.md](SECURITY.md) if you believe one has been exposed.
- Client-trusted game logic (see "Server is authoritative" above).
- Unrelated formatting/whitespace churn — keep diffs focused on the actual change.
