# The Void — Implementation Plan (for build execution)

This document assumes the product brief (`the-void-product-brief.md`) as the source of truth for design decisions. It translates those decisions into a concrete build plan: project structure, data schemas, module responsibilities, network contracts, and a phase-by-phase task list with acceptance criteria. It's written so a Claude session picking this up cold can start building without needing to re-derive design intent.

## 0. Confirmed Design Decisions (do not re-litigate these)

- Free-to-play, no monetization at launch.
- PvE only, no PvP.
- Round-based (not persistent world).
- 100 XP flat per level, no level cap.
- Spending XP on weapons delays leveling (same XP pool, no separate currency).
- Round win condition: quota-based, per-player kill target scaled to team size, plus a backstop timer.
- Team size target: 5–10 players per round.
- Death penalty: drop equipped weapon at death location as a world pickup; respawn with base weapon; no XP loss. **Pickup is player-locked — only the player who died can reclaim it. Other players cannot pick it up.**
- Weapon rollout: build 3 weapons first (Phase 2), expand to 6+ after playtesting (Phase 5).
- Robots: at least 3 tiers (Scout / Grunt / Heavy) by size, HP, damage, speed, XP reward.
- Zombies: a second enemy family alongside robots, sharing the same enemy data table and spawner. Base zombie is melee-only; weapon variant (punch/sword/head-thrower) is rolled once at spawn time and fixed for that zombie's lifetime. Head-thrower is a 1% spawn chance, ranged, telegraphed (~1s wind-up), and instant-kills any player caught in its explosion splash radius on landing — this bypasses normal damage rolls. Death from a head-thrower explosion uses the same death penalty as any other death (no special-case handling).
- Map: single dense forest, sized for 5–10 players, with terrain landmarks to aid navigation.
- Deployment: publishing to Roblox is done via a GitHub Actions workflow named `savetoroblox`, manually triggered, authenticated with a Roblox Open Cloud API key, supporting both a staging and a production place target. See Section 8.

If anything in this plan conflicts with the brief, the brief wins — flag the conflict rather than silently picking one.

## 1. Recommended Tooling & Project Structure

Build with **Rojo** so code lives in a normal file tree and can be version-controlled, rather than authoring everything inside Roblox Studio's built-in editor.

```
the-void/
├── default.project.json
├── src/
│   ├── ServerScriptService/
│   │   ├── EnemySpawner.lua
│   │   ├── CombatManager.lua
│   │   ├── XPManager.lua
│   │   ├── ShopManager.lua
│   │   ├── RoundManager.lua
│   │   ├── WeaponPickupManager.lua
│   │   └── DataManager.lua
│   ├── ReplicatedStorage/
│   │   ├── Remotes/
│   │   │   └── RemoteDefinitions.lua
│   │   ├── Data/
│   │   │   ├── WeaponTable.lua
│   │   │   └── EnemyTable.lua
│   │   └── Modules/
│   │       └── (shared utility modules, e.g. Signal, TableUtil)
│   ├── StarterPlayer/
│   │   └── StarterPlayerScripts/
│   │       ├── CombatController.client.lua
│   │       ├── ShopUIController.client.lua
│   │       └── HUDController.client.lua
│   └── StarterGui/
│       └── (UI screens: HUD, Shop, RoundEnd)
```

If Rojo isn't already set up in the target environment, that's the first task — don't build inside Studio's default script objects, since it doesn't diff or version well.

## 2. Data Schemas

### 2.1 Player Persistent Data (DataStore)

```lua
-- Stored per player, keyed by UserId
{
    level = 1,
    xp = 0,               -- current banked XP toward next level (0-99, resets on level-up)
    totalXp = 0,           -- lifetime XP earned, for stats/analytics, never decreases
    ownedWeapons = {"BaseSword"},  -- array of weapon ids the player has purchased
    equippedWeapon = "BaseSword",
    stats = {
        roundsPlayed = 0,
        enemiesKilled = 0,
        deaths = 0,
    },
    dataVersion = 1,       -- for future migration handling
}
```

Notes for the implementer:
- `xp` is the spendable/level-progress pool. `totalXp` is a separate lifetime counter — never let the two get confused, since `xp` decreases on weapon purchase but `totalXp` must not.
- Save on: player leaving, every ~2 minutes during play, and on round end. Wrap all DataStore calls with retry logic (exponential backoff, max 3-5 attempts) and never let a failed save silently swallow player progress — log it.
- **Implementation decision (Phase 2):** `DataManager` uses [ProfileStore](https://github.com/MadStudioRoblox/ProfileStore) (`lm-loleris/profilestore`, vendored via Wally) rather than hand-rolling the retry/backoff logic described above. Current Roblox community consensus (and Roblox's own guidance) is to use a maintained abstraction for this rather than hand-roll it — ProfileStore additionally handles session locking (preventing the classic multi-server data-loss/dupe race that a hand-rolled retry wrapper would not address unless built separately). This was an explicit approval from the design owner to add an external dependency. `DataManager`'s responsibility (single owner of persistent player data, full record including `xp`/`totalXp`/`level`/`ownedWeapons`/`equippedWeapon`/`stats`) is unchanged — only the internal mechanism differs from the original plan wording.

### 2.2 Weapon Table (ReplicatedStorage/Data/WeaponTable.lua)

```lua
return {
    BaseSword = { name = "Base Sword", cost = 0, damage = 10, fireRate = 1.0, range = 5, tier = 0 },
    IronSword = { name = "Iron Sword", cost = 50, damage = 18, fireRate = 1.0, range = 5, tier = 1 },
    Crossbow  = { name = "Crossbow",   cost = 80, damage = 25, fireRate = 0.7, range = 30, tier = 1 },
    -- Expand to 6+ in Phase 5. Keep this table as the single source of truth
    -- referenced by both shop UI and combat damage calculation.
}
```

### 2.3 Enemy Table (ReplicatedStorage/Data/EnemyTable.lua)

Covers both robots and zombies. Every entry has an `enemyType` field (`"robot"` or `"zombie"`) so spawner/combat code can branch on category where needed. Zombies additionally carry a `weaponVariants` table: on spawn, `EnemySpawner` rolls a variant per the listed `spawnChance` weights (weights sum to 1.0) and that variant is fixed for the zombie's lifetime.

```lua
return {
    Scout = { hp = 20, damage = 5,  speed = 20, xpReward = 5,  modelName = "ScoutRobot", enemyType = "robot" },
    Grunt = { hp = 60, damage = 12, speed = 12, xpReward = 12, modelName = "GruntRobot", enemyType = "robot" },
    Heavy = { hp = 150, damage = 25, speed = 6, xpReward = 30, modelName = "HeavyRobot", enemyType = "robot" },

    Zombie = {
        hp = 40, speed = 14, modelName = "ZombieBase", enemyType = "zombie",
        -- Base damage/xpReward are overridden per-variant below; keep these as sane fallbacks only.
        damage = 8, xpReward = 8,
        weaponVariants = {
            Punch     = { spawnChance = 0.80, damage = 8,  xpReward = 8,  attackType = "melee" },
            Sword     = { spawnChance = 0.19, damage = 16, xpReward = 14, attackType = "melee" },
            HeadThrow = {
                spawnChance = 0.01,
                xpReward = 25,
                attackType = "projectileInstantKillSplash",
                windUpSeconds = 1.0,       -- telegraph duration before the head is thrown
                splashRadius = 8,          -- studs; anyone inside on impact is instant-killed
                -- No `damage` field: this attack bypasses HP/damage rolls entirely on splash contact.
            },
        },
    },
}
```

## 3. Module Responsibilities

| Module | Location | Responsibility |
|---|---|---|
| `DataManager` | Server | Load/save player data via DataStore, expose get/set API to other server modules. Single owner of DataStore access — nothing else touches DataStore directly. |
| `XPManager` | Server | Award XP on enemy kill, handle level-up math, fire client-facing updates. Owns the `xp`/`totalXp`/`level` fields. |
| `ShopManager` | Server | Validate and process weapon purchase requests: check XP balance, deduct XP, add to `ownedWeapons`, set `equippedWeapon`. Rejects purchases server-side even if client UI misbehaves. |
| `CombatManager` | Server | Authoritative damage resolution for player-vs-enemy hits, for both robots and zombies. Client sends attack *intent*, server validates range/cooldown and applies damage. Also owns the zombie head-thrower projectile: server rolls/tracks the variant at spawn (via `EnemySpawner`), runs the telegraph timer, spawns the head projectile, and on impact resolves the splash radius as an instant kill (bypassing normal damage rolls) for any player caught inside it. |
| `EnemySpawner` | Server | Spawns robots and zombies by tier/type at spawn points, rolls a zombie's weapon variant (punch/sword/head-thrower) once at spawn time per `EnemyTable` odds, respawns on timer, tracks live enemy count for quota purposes. |
| `EnemyAI` | Server | Aggro/chase behavior once a player enters an enemy's detection radius — see Section 9. Owns each enemy's chase state (idle/chasing/returning) and pathfinding; `CombatManager` still owns whether an attack in range actually lands. |
| `RoundManager` | Server | Round lifecycle: lobby → start → track quota progress → end (win or timeout) → return to lobby. Calculates per-player quota scaled to team size at round start. Quota counts kills of any enemy type (robot or zombie). |
| `WeaponPickupManager` | Server | On player death, spawns a physical weapon pickup at death location, reverts player to base weapon; handles pickup interaction. |
| `RemoteDefinitions` | Shared | Single place declaring every RemoteEvent/RemoteFunction so client and server reference the same names — avoids typo mismatches. |
| `CombatController` | Client | Reads player input, sends attack intent to server, plays local hit feedback/animation (cosmetic only — never trusted for damage). |
| `ShopUIController` | Client | Renders shop menu from `WeaponTable`, sends purchase requests, reflects server-confirmed state (don't optimistically show a purchase as successful before server confirms). |
| `HUDController` | Client | Displays XP/level/quota progress/round timer from server-pushed state. |

## 4. Network Contract (RemoteEvents / RemoteFunctions)

Define all of these in `RemoteDefinitions.lua` so both sides reference the same objects.

| Name | Type | Direction | Payload | Purpose |
|---|---|---|---|---|
| `AttackIntent` | RemoteEvent | Client → Server | `{ targetEnemyId }` | Player attempts to hit an enemy (robot or zombie); server validates range/cooldown/damage. |
| `EnemyKilled` | RemoteEvent | Server → Client | `{ enemyId, enemyType, xpAwarded, newXp, newLevel }` | Notify client of a kill for UI/feedback. |
| `ZombieHeadThrowTelegraph` | RemoteEvent | Server → Client | `{ zombieId, windUpSeconds }` | Fired when a head-thrower zombie begins its wind-up, so clients can play the detach animation/warning cue during the telegraph window. |
| `PurchaseWeapon` | RemoteFunction | Client → Server | `{ weaponId }` → returns `{ success, reason?, newXp?, ownedWeapons? }` | Shop purchase request; server is sole authority on success/failure. |
| `EquipWeapon` | RemoteEvent | Client → Server | `{ weaponId }` | Switch equipped weapon among owned weapons (no XP cost). |
| `RoundStateUpdate` | RemoteEvent | Server → Client | `{ state, quotaTarget, quotaProgress, timeRemaining, reason?, summaryByPlayer? }` | Push round lobby/active/ended state and progress to all clients in the round. `reason` (`"QuotaMet"` \| `"Timeout"`) and `summaryByPlayer` (keyed by `tostring(UserId)`, each `{ kills, xpEarned }` for that round) are only present when `state == "Ended"` — added in Phase 3 to carry the end-of-round summary without a separate remote. |
| `PlayerDied` | RemoteEvent | Server → Client | `{ droppedWeaponId, respawnWeaponId, causeOfDeath }` | Inform client of death consequences for UI messaging. `causeOfDeath` includes the head-thrower splash case so the client can show appropriate feedback, but the death penalty itself does not vary by cause. |
| `RequestPlayerState` | RemoteFunction | Client → Server | none → returns full player data snapshot | Used on join/UI open to sync client state without guessing. |

## 5. Phase-by-Phase Task List with Acceptance Criteria

### Phase 1 — Core Loop Prototype
Tasks:
- Set up Rojo project structure as in Section 1.
- Greybox forest map: open area with basic tree placeholders, no art pass yet.
- Implement `EnemySpawner` with a single robot type (use Grunt stats) spawning at 2-3 fixed points.
- Implement `CombatManager`: server-validated melee attack, damage, robot death.
- Implement `XPManager`: award XP on kill, flat 100/level math, level-up event.
- Minimal HUD showing current XP and level (no styling needed).

Acceptance criteria:
- A player can walk up to a robot, attack it, kill it, and see XP/level update, with all damage/XP calculated server-side (verify by checking server output, not just client display).
- Killing a robot causes it to respawn after a fixed delay.

### Phase 2 — Progression & Shop
Tasks:
- Add Scout and Heavy robot tiers using `EnemyTable` stats.
- Add base zombie enemy type using `EnemyTable` stats: melee-only for this phase (punch/sword variants), rolled at spawn per the `weaponVariants.spawnChance` weights. **Defer the head-thrower variant to a follow-up task in this same phase** once punch/sword zombies are confirmed working end-to-end (spawn → combat → death → XP), since the head-thrower needs new projectile/splash-kill logic in `CombatManager` that the other variants don't.
- Implement the head-thrower zombie variant: wind-up telegraph (fire `ZombieHeadThrowTelegraph`), thrown head projectile, splash-radius impact resolution as an instant kill bypassing normal damage, normal death penalty on kill (no special-casing in `WeaponPickupManager`/death flow).
- Build `ShopManager` and shop UI with 3 starter weapons from `WeaponTable`.
- Wire `PurchaseWeapon` RemoteFunction: server validates XP balance, deducts, updates `ownedWeapons`/`equippedWeapon`.
- Make equipped weapon actually change `CombatManager` damage/fire rate/range values used in combat.
- Build `WeaponPickupManager`: on death, drop equipped weapon as a pickup, revert to base weapon on respawn. Pickup is player-locked (only the player who died can interact with/reclaim it — no other player can pick it up).
- Integrate `DataManager` with real DataStore calls (not just in-memory); verify data survives a server restart / rejoin.

Acceptance criteria:
- Purchasing a weapon with insufficient XP is rejected server-side even if attempted directly via a spoofed remote call.
- Player who dies drops their weapon, can walk back and pick it up, and it reappears in `ownedWeapons`/becomes equippable again (decide and implement: does the pickup have a despawn timer? Recommend yes, ~60-90 seconds, so death sites don't accumulate forever — flag this to the design owner if not already decided).
- Rejoining after leaving restores level, XP, and owned weapons correctly.
- Spawning a large sample of zombies (e.g. 1000 in a test script) produces variant odds statistically close to 80/19/1 — verifies the spawn-time roll, not just that all three variants exist.
- A player caught in a head-thrower's splash radius dies instantly regardless of current HP/weapon, confirmed server-side; a player who moves out of range during the ~1s wind-up survives.
- Head-thrower death applies the same drop-weapon/respawn-base/no-XP-loss penalty as any other death.

### Phase 3 — Rounds & Social
Tasks:
- Build `RoundManager`: lobby state, round start, quota calculation `(quotaPerPlayer * playerCount)`, round end on quota-met or timer expiry. **Implemented** — `quotaPerPlayer = 10`, backstop timer = 10 minutes (starting placeholders, confirmed with design owner; real tuning is Phase 5).
- Push `RoundStateUpdate` to clients for HUD display of quota progress and time remaining. **Implemented** — pushed every second while active, plus immediately on any state transition. A player joining mid-round receives current state via this same periodic push (no separate "current state" remote needed — worst case is a ~1s delay before their HUD reflects live round state).
- Verify friend-join behavior: confirm Roblox's native "Join" via friends list places joining players into the same server, and if mid-round, into the same round state (not a stale lobby). **Not verifiable from a code session** — this requires a published place and at least two real Roblox accounts testing live. No code in this project alters or interferes with Roblox's default friend-join behavior (no reserved servers/teleport logic exists), so this should work by default, but it must still be manually confirmed per the acceptance criteria below before considering Phase 3 done.
- End-of-round summary UI (kills, XP earned this round, quota result). **Implemented** — `RoundStateUpdate`'s payload gained optional `reason`/`summaryByPlayer` fields present only when `state == "Ended"` (see Section 4) rather than a new remote.

Acceptance criteria:
- A round with 5 players and a round with 10 players both feel appropriately challenging — i.e., the per-player quota scaling actually produces comparable difficulty (this needs at least manual dual-test, ideally with bots or multiple test accounts). **Not verifiable from a code session — requires live playtesting.**
- A friend joining via Roblox's friend-join lands in the same active round, not a separate server instance. **Not verifiable from a code session — requires a published place and two real accounts.**

### Phase 4 — Forest Map Polish
Tasks:
- Full art pass on forest environment: dense tree/foliage placement, terrain variation, 2-3 landmarks for navigation.
- Tune robot and zombie spawn point placement against the finished map geometry (sightline breaks, search pacing).
- Confirm map performance (part count, collision complexity) holds up with 10 concurrent players plus robots and zombies.

Acceptance criteria:
- Manual playtest: a solo player cannot see all enemies from spawn; finding robots and zombies requires actual exploration.
- Frame rate / server step time stays acceptable at target player + enemy count (define a concrete threshold if the target platform is known, e.g., mobile — flag if this needs a specific FPS target from the design owner).

### Phase 5 — Playtesting & Tuning
Tasks:
- Expand `WeaponTable` from 3 to 6+ weapons; balance pass on damage/fireRate/range/cost.
- Tune quota-per-player value based on Phase 3/4 playtesting data.
- Tune robot difficulty (HP/damage) and respawn timers based on observed kill rates.
- Tune zombie punch/sword damage and respawn timers based on observed kill rates.
- Playtest the head-thrower variant specifically for fairness: confirm the ~1s telegraph is readable in the finished game (animation + audio cue) and gives players a genuine chance to react. Adjust `windUpSeconds`, `splashRadius`, or the 1% spawn odds if it's landing as "unavoidable" rather than "dangerous" (see risk in product brief Section 8).
- Actively look for degenerate strategies: is always-saving-XP-for-levels or always-buying-weapons strictly dominant? Adjust weapon costs/power if so.

Acceptance criteria:
- No single strategy (pure-save vs. pure-spend) is favored in playtesting feedback.
- Round completion rate (quota met before timeout) sits in a target healthy range — recommend defining this target explicitly before tuning (e.g., 70-85% of rounds complete successfully) rather than tuning blind.
- Playtesters report the head-thrower as a tense/dangerous encounter, not a random unavoidable death — capture this feedback explicitly, don't infer it from other metrics.

### Phase 6 — Launch Prep
Tasks:
- Server load test: simulate 10 players + full robot and zombie spawn load, watch for script performance issues.
- DataStore failure handling: simulate DataStore outage, confirm player data isn't silently lost (retry queue, or at minimum clear error logging).
- Add lightweight analytics events: round start/end, completion vs timeout, average session length, per-weapon purchase frequency (useful data for future weapon balance and potential monetization decisions, even though monetization is out of scope for v1).
- Set up the `savetoroblox` GitHub Actions workflow per Section 8: create the Roblox Open Cloud API key with `universe-places` write access, register `ROBLOX_API_KEY` (secret) and `ROBLOX_UNIVERSE_ID`/`ROBLOX_STAGING_PLACE_ID`/`ROBLOX_PRODUCTION_PLACE_ID` (variables), and add `.github/workflows/savetoroblox.yml`.
- Dry-run `savetoroblox` against the staging place target first; confirm the returned `versionNumber` matches what's visible in Studio before ever running it against production.
- Final QA pass across all phases' acceptance criteria before publishing.

Acceptance criteria:
- All previous phase acceptance criteria still pass after integration.
- No unhandled errors in server output during a full simulated round with max players.
- `savetoroblox` successfully publishes to the staging place via manual dispatch, confirmed by version number and by opening the staging place in Studio afterward.

## 6. Items Left to Implementer Discretion (not blocking, but call these out when reached)

- ~~Exact weapon pickup despawn timer (Phase 2)~~ — **Resolved: 60 seconds**, confirmed with design owner during Phase 2 implementation.
- Concrete FPS/performance target for the finished map (Phase 4) — depends on target device mix (PC/mobile/console), not yet specified.
- Target round-completion rate for quota tuning (Phase 5) — recommend defining a number rather than tuning by feel.
- Robot HP/damage and weapon damage values in Sections 2.2/2.3 are placeholder starting numbers, not final balance — real tuning happens in Phase 5 against actual playtest data.
- Zombie base HP/speed and punch/sword damage values in Section 2.3 are placeholder starting numbers — same Phase 5 tuning treatment as robots.
- Exact head-thrower `windUpSeconds` and `splashRadius` values in Section 2.3 are starting points for playtesting, not final balance — expect these to change based on Phase 5 fairness feedback specifically (see product brief Section 8 risk).

## 7. Testing Checklist (run before considering any phase "done")

Items marked **(automated)** are covered by the Lune/frktest suite (Section 7.1) and can be verified by running it — no manual repro needed. Everything else still requires live testing in Studio or a published place.

- [x] All damage/XP/purchase logic verified server-authoritative (attempt to call remotes with invalid/spoofed data and confirm server rejects). **(automated — ShopManager.spec.luau, CombatManager.spec.luau call the validation functions directly, which is exactly the "spoofed call" scenario)**
- [ ] DataStore save/load verified across a server restart, not just in the same session. **Not automatable** — the test suite uses a fake ProfileStore (DataManager.spec.luau) to verify DataManager's own load/save/session-lifecycle logic, but that can't substitute for confirming the real DataStore survives an actual server restart.
- [ ] Round quota scaling manually verified at both ends of the 5-10 player range. Requires live playtesting (see Section 5 Phase 3 acceptance criteria).
- [ ] Friend-join tested with at least two real accounts, not assumed from documentation.
- [x] No client-trusted values used for anything that affects XP, level, or ownership. **(automated, by construction — every test calls server-side functions directly with attacker-controlled-shaped input and confirms rejection, rather than trusting client state)**
- [x] Zombie weapon-variant spawn odds verified statistically (not just "all three variants appeared once"). **(automated — EnemySpawner.spec.luau, 10,000-sample distribution check)**
- [x] Head-thrower instant-kill splash verified server-authoritative: a client cannot claim survival if server-side splash logic says otherwise, and vice versa. **(automated — CombatManager.spec.luau covers telegraph → splash-kill, player-left-radius-survives, and zombie-died-mid-windup-cancels-explosion)**
- [x] Head-thrower death confirmed to apply the same death penalty path as every other death cause (no divergent code path skipped in testing). **(automated — CombatManager's instantKillPlayer uses the same TakeDamage(math.huge) → Humanoid.Died path as normal combat damage, and WeaponPickupManager.spec.luau tests HandlePlayerDeath directly, not conditioned on cause)**
- [ ] Analytics events (round start/end, completion vs timeout, session length, weapon purchases) confirmed actually arriving in the Creator Dashboard's Analytics tab. **Not automatable, and not verifiable in Studio at all** — Roblox's AnalyticsService only sends events from the server of a *published* place (confirmed via Roblox's own docs); Studio only logs a local "event fired" acknowledgment with no way to confirm delivery. Requires publishing to the staging place (Section 8.2) and checking the dashboard 24+ hours later (events aggregate daily per Roblox's docs).

### 7.1 Running the automated test suite

Tests run under [Lune](https://github.com/lune-org/lune) (a standalone Luau runtime — chosen over TestEZ/Studio specifically so tests run without opening Studio) using [frktest](https://github.com/itsfrank/frktest) as the assertion/runner library. Neither runs inside the actual Roblox game — see `tests/mocks/RobloxEnv.luau` for the fake `game`/`Players`/`Instance`/`Humanoid` environment that lets unmodified production modules load and run outside Roblox.

```
mise exec -- lune run tests/_run.luau
```

(or just `lune run tests/_run.luau` once `mise activate` is set up per `getting-started.md` Section 3.2).

Coverage: `XPManager`, `ShopManager`, `RoundManager`, `EnemySpawner`, `CombatManager`, `WeaponPickupManager`, `DataManager` — all seven non-trivial server modules. Client controllers and `RemoteDefinitions` are not covered (client-side UI logic and remote-instance creation aren't meaningfully unit-testable without a real Roblox client).

**Known limitations of this approach** (accepted trade-offs, not bugs):
- `CombatManager.Init`/`RoundManager.Init` each start an infinite `task.spawn` polling loop, which has no natural exit under Lune (a real Roblox server just runs forever, so this was never a problem in production). Tests never call `.Init()` — they set the same fields `Init()` would set directly, and call the underlying logic functions (`HandleAttackIntent`, `_tickOneEnemyAttack`, `RecordKill`, etc.) directly instead.
- `@lune/roblox`'s `Instance.new` does not simulate `Humanoid`-specific behavior (`TakeDamage`, `.Died` firing) — `tests/mocks/FakeHumanoid.luau` implements exactly that surface as a hand-built fake, not a real Roblox Humanoid.
- Globally reassigning Luau's `require` function breaks relative-path resolution for *other* unrelated `require()` calls happening anywhere else in the process (confirmed by direct experiment) — so the fake-module-unwrapping trick used to satisfy `require(ReplicatedStorage.Data.EnemyTable)`-style calls is scoped narrowly to the exact duration of loading one production module (`RobloxEnv.requireModule`), not left on globally.
- A handful of tests use real `task.wait()` sleeps (e.g. waiting out a weapon cooldown or a zombie's wind-up) rather than a fake/advanceable clock, since `CombatManager`/`RoundManager`/`EnemySpawner` read wall-clock time directly (`os.clock()`) rather than through an injectable clock dependency. This makes those specific tests slightly slower and, in principle, sensitive to extreme system load — accepted as disproportionate to fix (would mean adding a clock abstraction to production code) given the suite has been stress-tested (dozens of consecutive clean runs) with no observed flakiness from this cause.
- `EnemySpawner` keeps its live-enemy state as module-level upvalues, and Lune (like Roblox) caches a required module — so every spec file in the same test process shares the same `EnemySpawner` instance. `EnemySpawner._resetForTests()` (test-only; a real server never calls it) clears that state and is called once at the top of every spec file that requires `EnemySpawner`, so one file's spawned enemies can't leak into another's assertions.

## 8. Release / Deployment Plan

Publishing to Roblox is handled by a GitHub Actions workflow named **`savetoroblox`** (`.github/workflows/savetoroblox.yml`). This section specifies how it authenticates, what it publishes, and how it's triggered. See `getting-started.md` Section 5 for the manual/first-time publish path via Studio — this section covers the automated path once the project is Rojo-managed.

### 8.1 Authentication: Roblox Open Cloud API key

Publishing is done via Roblox's official **Open Cloud** Place Publishing API, not a `.ROBLOSECURITY` cookie — cookie-based publishing is an older, unofficial pattern that carries a full account session (broader access than needed) and is more fragile against Roblox-side changes.

1. In the **Creator Dashboard**, create an API key scoped to this experience only (not account-wide).
2. Under **Access Permissions**, add **`universe-places`** and enable the **Write** operation for this specific universe. Do not grant broader scopes than publishing requires.
3. Store the key as a GitHub Actions **repository secret** named `ROBLOX_API_KEY`. Never commit it, never print it in workflow logs.
4. Rotate the key if it's ever exposed (e.g. accidentally logged, or a workflow file change makes you unsure whether it leaked).

### 8.2 Publish targets: staging vs. production

Per the getting-started doc's guidance to keep the experience private until ready, `savetoroblox` supports publishing to **two different places**, selected explicitly at run time — a testing/staging place and the real production place. This avoids the failure mode where the only way to test a build is to push it to the place real players can join.

Repository configuration needed:
- `ROBLOX_UNIVERSE_ID` — GitHub Actions **variable** (not secret; universe ID isn't sensitive), shared across both targets since staging and production places should live in the same universe (multi-place universe) unless there's a specific reason to separate them.
- `ROBLOX_STAGING_PLACE_ID` — variable, the private/testing place.
- `ROBLOX_PRODUCTION_PLACE_ID` — variable, the public place real players join.
- `ROBLOX_API_KEY` — secret (Section 8.1), used for both targets. If tighter separation is wanted later (e.g. a key that can only touch staging), split into `ROBLOX_STAGING_API_KEY` / `ROBLOX_PRODUCTION_API_KEY` — not needed at this project's current scale.

### 8.3 Trigger: manual dispatch only

`savetoroblox` runs on **`workflow_dispatch`** only — there is no automatic publish on push or merge to `main`. This is a deliberate choice while the game is pre-launch and iterating quickly: a bad merge should never be able to reach players (or even the staging place) without someone deciding to run the workflow. Revisit this once the core loop (Phases 1-3) is stable — an auto-publish-to-staging-on-merge (never production) could be a reasonable fast-follow, but is out of scope for now per YAGNI.

The workflow takes one required input:
- `target`: choice of `staging` or `production`, selecting which place ID (Section 8.2) to publish to.

### 8.4 Workflow steps

No third-party GitHub Action is used for the actual publish step — the only community action found for this (`Krultu/rbx-publish`) is unmaintained (last updated 2022, no adoption) and its own README references a different, nonexistent action name, which is a bad sign for trusting it as a supply-chain dependency. Instead, `savetoroblox` calls Roblox's documented Open Cloud endpoint directly via `curl`, which is fully auditable in the workflow file itself and has no external dependency to go stale.

1. **Checkout** the repository (`actions/checkout`).
2. **Install Rojo** via `mise` (matching this project's local tooling, see `getting-started.md` Section 3) so the built place file is produced the same way locally and in CI.
3. **Build the place file**: `rojo build default.project.json -o place.rbxl`.
4. **Resolve the target place ID** from the `target` input (`staging` → `ROBLOX_STAGING_PLACE_ID`, `production` → `ROBLOX_PRODUCTION_PLACE_ID`).
5. **Publish via Open Cloud**:
   ```bash
   curl --fail --silent --show-error --location \
     --request POST \
     "https://apis.roblox.com/universes/v1/${UNIVERSE_ID}/places/${PLACE_ID}/versions?versionType=Published" \
     --header "x-api-key: ${ROBLOX_API_KEY}" \
     --header "Content-Type: application/octet-stream" \
     --data-binary @place.rbxl
   ```
   `--fail` ensures a non-2xx response fails the workflow rather than silently succeeding. A successful response body is `{ "versionNumber": <n> }`.
6. **Surface the result**: log the returned `versionNumber` in the workflow summary so it's easy to confirm what actually got published and when.

### 8.5 Safety notes specific to this workflow

- **Production publishes are a deliberate, visible action.** Because the trigger is manual with an explicit `target` choice, publishing to production always requires a human to pick "production" from the dropdown — there's no path where a routine merge accidentally goes live.
- **The API key should never be echoed to logs.** GitHub Actions automatically masks registered secrets in logs, but avoid `curl --verbose` in the final workflow (it can leak headers) — use `--fail --silent --show-error` instead, which reports failures without dumping full request/response detail.
- **Rebuild, don't reuse, the place file per run.** Always run `rojo build` fresh in the workflow rather than publishing a place file built on someone's local machine, so what's published is guaranteed to match the commit that triggered the run.

## 9. Enemy Chase AI

Added after Phase 4 (real terrain + real enemy models existed by then, making stationary enemies feel inert rather than dangerous — every enemy could be damaged risk-free from outside its melee range with any ranged weapon). Originally deferred past Phase 2 (see `CombatManager.luau`'s Phase 2 header comment) specifically because it needed real map geometry to path against, which Phase 4 now provides.

### 9.1 Trigger: aggro radius

Each enemy tracks one of three states: `Idle` (at/returning to its spawn point), `Chasing` (pathing toward a player), or attacking (handled by `CombatManager`'s existing melee-range tick, unchanged). `EnemyAI` runs its own independent tick loop (same `task.spawn`/`task.wait` pattern as `CombatManager.TickEnemyAttacks`, but a separate loop — the two modules stay decoupled per Section 9.3, so `EnemyAI` doesn't reach into `CombatManager`'s private loop, and vice versa) at the same `ENEMY_ATTACK_CHECK_INTERVAL_SECONDS` cadence. On each tick, an `Idle` enemy checks distance to the nearest player:

- Enters `Chasing` if a player is within `AGGRO_RADIUS_STUDS = 25` studs (comfortably beyond `ENEMY_MELEE_RANGE = 6`, so the enemy visibly closes distance before it can attack, and within typical ranged-weapon range — Crossbow 30, Longbow 45 — so a player who never melees still gets engaged).
- A `Chasing` enemy that loses its target (player moved beyond `AGGRO_RADIUS_STUDS * 1.5` — a larger release radius than the trigger radius, so an enemy doesn't flicker between states at the boundary) returns to `Idle` and paths back to its original spawn point, rather than wandering permanently away from its spawn cluster. Returning to spawn (not simply stopping in place) matters for the Phase 4 acceptance criterion that finding enemies requires exploration — an enemy that chased a player across the map and stayed there would empty out that spawn cluster.

### 9.2 Movement: PathfindingService

While `Chasing`, `EnemyAI` computes a path via `PathfindingService:CreatePath` (default `AgentParameters`, no custom `AgentRadius`/`Costs` yet — a placeholder starting point, not tuned) to the target player's current `HumanoidRootPart.Position`, and walks the enemy's `Humanoid` along the returned waypoints via `MoveTo`. Because the player keeps moving, the path is recomputed on a shorter interval than the aggro check itself (every 1 second) rather than once — a stale path would walk the enemy to where the player *was*. `Path.Blocked` also triggers an immediate recompute rather than waiting for the next interval, so an enemy doesn't stand still against a moved obstacle for up to a full second.

### 9.3 Interaction with existing combat

`EnemyAI` only ever calls `Humanoid:MoveTo()` — it never resolves damage. Once an enemy is within `ENEMY_MELEE_RANGE`, `CombatManager`'s existing tick (unchanged by this addition) already attacks regardless of `EnemyAI`'s state, so a chasing enemy that catches up to a player starts attacking exactly as a stationary one already does when a player walks up to it. `HandleAttackIntent` (the player's own attack) is likewise unaffected — a player can still attack a chasing or returning enemy at any point, same as an idle one.

### 9.4 Known limitation: untestable pathfinding

`PathfindingService` and `Humanoid:MoveTo` don't exist in Lune's fake Roblox environment (same category as `AnalyticsService` — see Section 7's testing checklist). `EnemyAI`'s state machine (Idle → Chasing → Idle transitions, aggro/release radius thresholds) is unit-tested the same way `CombatManager`'s range checks are; the actual pathfinding/movement calls are a thin, unit-untested wrapper verified only by manual Studio playtesting (does the enemy visibly walk toward you, does it navigate around a tree rather than getting stuck).
