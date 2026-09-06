# The Void

A free-to-play, round-based PvE game for Roblox. Players spawn into a dense forest, hunt robot and zombie enemies, and earn XP they can bank toward leveling up or spend immediately on better weapons — a deliberate risk/reward tension between power now and progression later.

Built with [Rojo](https://rojo.space/) for a code-first, version-controlled Roblox workflow, and tested with a real automated suite that runs outside Roblox Studio entirely.

## Core Loop

1. Join a server (solo or with a friend party) and spawn at the forest edge.
2. Explore — robots and zombies aren't clustered at spawn, so finding them is the point.
3. Fight. Damage, XP, and purchases are all resolved server-side; nothing is trusted from the client.
4. Spend banked XP on a weapon now, or save it toward the next level — both are valid strategies, and Phase 5 tuning work specifically checks that neither one dominates.
5. Clear the round's kill quota (scaled to team size) before the backstop timer runs out.

See [`docs/the-void-product-brief.md`](docs/the-void-product-brief.md) for the full design rationale, including the zombie head-thrower — a rare (1% spawn), telegraphed, instant-kill ranged attack designed to be dangerous without feeling unfair.

## Architecture

Server modules own all game state and validate every client action; client controllers only render state and send *intent*, never resolved outcomes.

| Module | Side | Responsibility |
|---|---|---|
| `DataManager` | Server | Sole owner of DataStore access — player XP, level, and owned weapons. |
| `XPManager` | Server | XP awards and level-up math. |
| `ShopManager` | Server | Validates and processes weapon purchases; rejects them even if the client is compromised. |
| `CombatManager` | Server | Authoritative damage resolution, including the head-thrower's telegraph → splash-kill sequence. |
| `EnemySpawner` | Server | Spawns/respawns robots and zombies, rolls each zombie's weapon variant at spawn time. |
| `EnemyAI` | Server | Aggro/chase behavior via `PathfindingService` once a player enters an enemy's detection radius. |
| `RoundManager` | Server | Round lifecycle and per-player quota scaling. |
| `WeaponPickupManager` | Server | Drop-on-death and pickup-on-return weapon handling. |
| `RemoteDefinitions` | Shared | Single source of truth for every RemoteEvent/RemoteFunction, so client and server can't drift. |
| `CombatController`, `ShopUIController`, `HUDController` | Client | Input, shop UI, and HUD rendering — cosmetic only, never trusted for game state. |

Full responsibilities and the network contract are in [`docs/the-void-implementation-plan.md`](docs/the-void-implementation-plan.md) Sections 3–4.

## Testing

The full server-logic suite runs under [Lune](https://github.com/lune-org/lune), a standalone Luau runtime, using [frktest](https://github.com/itsfrank/frktest) — no Roblox Studio required:

```
mise exec -- lune run tests/_run.luau
```

`tests/mocks/RobloxEnv.luau` fakes just enough of `game`/`Players`/`Instance`/`Humanoid` for unmodified production modules to load and run. This covers every non-trivial server module — including statistically verifying zombie weapon-variant spawn odds over 10,000 samples, and confirming the head-thrower's instant-kill splash is server-authoritative rather than client-claimed.

What's deliberately *not* covered, and why, is documented rather than glossed over: client UI/input and `PathfindingService`-driven movement aren't exercisable outside a real Roblox client, so those are called out as accepted, manually-verified gaps in [`docs/the-void-implementation-plan.md`](docs/the-void-implementation-plan.md) Section 7.

## Getting Started

New to Roblox Studio or this project? [`docs/getting-started.md`](docs/getting-started.md) walks through account setup, installing Rojo, syncing the project, running the test suite, and publishing — written for zero prior Roblox Studio experience.

## Project Status

Currently in Phase 5 (playtesting & tuning) of the implementation plan — the core loop, shop, rounds, and forest map are built; remaining work is balance tuning, enemy visuals/AI polish, and Phase 6 launch prep (analytics, load testing, deployment). See [`docs/the-void-implementation-plan.md`](docs/the-void-implementation-plan.md) Section 5 for the full phase-by-phase breakdown and acceptance criteria.

## Contributing

Bug reports, suggestions, and pull requests are welcome — see [CONTRIBUTING.md](CONTRIBUTING.md) for branch conventions, running tests locally, and what to expect from review. Found a security issue (an exploit, a way to bypass server-side validation, a DataStore/dupe bug)? See [SECURITY.md](SECURITY.md) instead of opening a public issue.

## License

This repository is public for educational and portfolio purposes. All rights reserved. You may view, fork, and modify this repository for the purpose of submitting changes back via pull request. You do not have permission to redistribute, modify, or host this game (or its assets) on Roblox or any other platform for commercial or non-commercial use, outside of contributing to this repository.
