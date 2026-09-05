# The Void — Product Brief & Implementation Plan

## 1. Overview

The Void is a free-to-play, round-based Roblox PvE game. Players spawn into a dense forest and hunt robot and zombie enemies of varying size and difficulty. Killing enemies earns experience points (XP). Every 100 XP grants a level. Players can spend banked XP on weapons instead of saving it toward a level, creating a risk/reward tradeoff between power now and progression later.

No monetization at launch. No PvP. Players can party up with friends and play matches together.

## 2. Goals

- Core loop that's understandable in under 30 seconds: explore, find robot, fight, earn XP, level or spend.
- Forest map creates a search-and-engage rhythm rather than constant combat (avoids feeling like a twin-stick shooter with no downtime).
- Meaningful choice: spend XP on weapons now vs. save for level-ups.
- Support standard Roblox social expectations: invite friends, join a friend's server, party into the same round.

## 3. Non-Goals (for v1)

- No PvP.
- No monetization (Robux, gamepasses, ads) — flagged as a fast-follow if the game performs well.
- No persistent open world — matches are round-based with a clear start and end.
- No trading, inventory economy, or cosmetic marketplace at launch.

## 4. Core Gameplay Loop

1. Player joins a server (solo or with a friend party).
2. Player joins/starts a round; round begins with all players spawned at forest edge points.
3. Players explore the forest to locate enemies (robots and zombies are not all visible from spawn — searching is the point).
4. Player engages an enemy in combat.
5. On kill, player earns XP based on enemy tier/type.
6. Player chooses each time they've banked XP: let it accumulate toward next level, or spend it in the shop (menu, always accessible) on a weapon.
7. Round ends on a timer or when a wave/objective is cleared (see open question below).
8. Players return to lobby; progression persists per player (see Section 9).

## 5. Systems Detail

### 5.1 Experience & Leveling
- 100 XP = 1 level.
- Leveling is automatic and immediate once the threshold is crossed.
- Spending XP on a weapon deducts from the player's current banked XP, directly delaying their next level-up (this is the entire tension of the system — no separate currency).
- **No level cap** — leveling continues indefinitely. XP-per-level stays flat at 100 for v1 simplicity (no scaling curve). Watch this in playtesting: flat 100 with no cap means a long-session player could reach very high levels; if "level" is shown anywhere as a status/flex number, an uncapped flat curve inflates fast. Not a launch blocker, just something to sanity-check once you see real play sessions.

### 5.2 Robots (Enemies)
- Multiple tiers by size/difficulty, e.g.:
  - **Scout** (small, low HP, low damage, fast) — low XP reward
  - **Grunt** (medium, moderate HP/damage) — medium XP reward
  - **Heavy** (large, high HP, slow, hits hard) — high XP reward
- Robots patrol or idle within the forest and are not all clustered near spawn, forcing exploration.
- **Assumption:** robots respawn on a timer per spawn point so the map doesn't get "cleared out" mid-round.

### 5.3 Zombies (Enemies)
- A second enemy family alongside robots, mixed into the same forest spawn pool. Robots and zombies are both "the villains" of the game — the brief now treats them as two families under one enemy roster, not a robots-only game with zombies bolted on.
- Baseline zombie is a single tier, melee-only, roughly between Scout and Grunt in threat/XP — a common, ever-present enemy rather than a rare high-value target.
- **Weapon variant is rolled per-zombie at spawn time** (fixed for that zombie's lifetime, not re-rolled per attack):
  - **80% — Punch** (base melee attack, lowest damage of the three variants).
  - **~19% — Sword** (melee, higher damage than punch).
  - **1% — Head-thrower**: the zombie can detach its own head and throw it as a ranged weapon. The throw has a short (~1 second) visible wind-up/telegraph — the detach animation plays before the head is thrown, giving an attentive player a chance to react/retreat. On landing, the head explodes in a small area-of-effect radius; any player caught in that radius is **instantly killed** (this bypasses normal HP/damage rolls entirely — it is a guaranteed kill on splash contact, not a damage-based interaction). This is a rare, high-tension threat specifically because it is a one-shot kill, unlike every other enemy attack in the game.
- Death from a head-thrower explosion uses the **same death penalty as any other death** (Section 5.6: drop equipped weapon, respawn with base weapon, no XP loss) — there is no separate/harsher penalty for this enemy type.
- Sword and head-thrower variants grant more XP on kill than the punch variant, reflecting their higher danger.
- Same respawn-on-timer assumption as robots — zombies persist in the spawn pool throughout the round.

### 5.4 Weapon Shop
- Menu accessible any time (not gated to a physical shop location, so it doesn't break the forest-exploration pacing).
- Weapons cost XP; higher-tier weapons cost more XP.
- Owned weapons persist for the player going forward (not just for the round) — otherwise the "spend XP" choice has no lasting payoff.
- **6+ weapons at launch**, each a stat upgrade (damage/fire rate/range), not cosmetic-only, since damage output affects how fast players can farm XP — this is the actual strategic loop.
- Flagging this directly: 6+ weapons at launch is real scope for a v1. Each one needs its own stats, balancing pass, model/animation, and a price point in the XP curve. My honest recommendation is to prototype and playtest with 3 weapons in Phase 2, lock the balancing approach, then scale up to the full 6+ in Phase 5 once you know the shop/combat loop actually works. Building all 6+ up front before you've validated the core loop risks wasted rework if early playtesting changes the combat feel.

### 5.5 Map — Dense Forest
- Single map at launch, dense tree/foliage coverage to break sightlines and force search behavior.
- Landmarks or terrain variation (hills, clearings, ruins) to aid navigation and avoid the forest feeling like uniform noise.
- Map size sized for 5–10 concurrent players per round; exact size to be tuned in playtesting.

### 5.6 Rounds & Matchmaking
- Round-based: players join a lobby, a round starts, round ends, players return to lobby.
- **Win condition: quota-based.** A round ends successfully when the team clears a set number of enemy kills (robots and zombies both count); there's also a backstop timer so a round can't run forever if the team is struggling.
- **Quota must scale with team size** — a fixed quota (say "kill 30 enemies") is trivial for a 10-player team and grueling for a 5-player team. Quota should be calculated per round based on how many players are actually in it (e.g., a per-player kill target rather than a flat number). This needs to go into `RoundManager` from the start, not bolted on later.
- Team size target: 5–10 players per round. Below 5, consider whether the map feels too empty; that's a playtesting question, not a hard rule.

### 5.7 Social / Standard Roblox Expectations
- Friends can join the same server via standard Roblox "Join" from friends list / profile.
- Party-style play: friends who join the same server land in the same round/lobby together.
- Standard Roblox UX: server browser via game page, leave/rejoin, respawn on death.
- **Death penalty: drop currently equipped weapon.** On death, the player's equipped weapon becomes a world pickup at the death location; the player respawns with their default/base weapon. They (or anyone) can walk over and pick the dropped weapon back up. This requires a `WeaponPickup` mechanic (spawn a physical pickup, ownership-agnostic or player-locked — decide which; player-locked is simpler and avoids weapon-stealing complaints) and needs to be built alongside the weapon system in Phase 2, not treated as a Phase 3 add-on.
- No XP loss on death — the penalty is entirely the weapon drop, keeping death punishing but not run-ending.
- Persistent player data (level, XP, owned weapons) saved via Roblox DataStores so progress carries across sessions.

## 6. Technical Implementation Plan

### 6.1 Architecture
- **Server-authoritative combat and XP.** All damage, kills, and XP awards calculated on the server; client only sends input/intent. This is non-negotiable for basic anti-exploit hygiene in Roblox.
- **RemoteEvents/RemoteFunctions** for: attack input, shop purchase requests, UI data requests (current XP/level/owned weapons).
- **DataStoreService** for persistent player progression (level, XP, weapons owned). Use a retry-wrapped save module; save on player leaving and at periodic intervals to reduce data loss risk.
- **ServerScriptService** modules: `EnemySpawner`, `CombatManager`, `XPManager`, `ShopManager`, `RoundManager`.
- **ReplicatedStorage** for shared modules (weapon stat tables, enemy stat tables covering both robots and zombies, RemoteEvent definitions).

### 6.2 Suggested Build Phases

**Phase 1 — Core Loop Prototype**
- Basic forest greybox map.
- One enemy type (robot), server-side spawn/damage/death.
- XP award on kill, level-up math, simple UI showing XP/level.
- Goal: prove the search-and-kill loop feels good before investing in art/content.

**Phase 2 — Progression & Shop**
- Multiple robot tiers with distinct stats and XP values.
- Introduce zombies: base melee zombie plus the spawn-time weapon-variant roll (punch/sword/head-thrower) — see Section 5.3.
- Shop UI + weapon purchase flow, XP deduction logic.
- Start with 3 weapons to validate combat feel and balance approach (see note in 5.4) — expand to full 6+ roster in Phase 5.
- Weapon stat differences actually affecting combat (damage/fire rate/range).
- `WeaponPickup` mechanic for the death-drop penalty (world pickup, player-locked ownership recommended).
- DataStore integration for persistence across sessions.

**Phase 3 — Rounds & Social**
- Round start/end flow, lobby, per-round timer as backstop.
- Quota calculation in `RoundManager` scaled to actual team size (5–10 players) — build this scaling in from the start, not as a later patch.
- Friend-join/party support testing (verify Roblox's native friend-join lands players in the same server/round).
- Respawn-on-death handling, including weapon drop and revert to base weapon.

**Phase 4 — Forest Map Polish**
- Full dense-forest environment art pass, landmarks, spawn point tuning.
- Enemy placement/patrol tuning (robots and zombies) for the "search" pacing to feel intentional, not empty.

**Phase 5 — Playtesting & Tuning**
- Expand from 3 to 6+ weapons once core combat/shop loop is validated.
- Tune XP values, weapon costs, robot/zombie difficulty curves, weapon-variant spawn odds (punch/sword/head-thrower), and per-player quota targets across the 5–10 player range.
- Specifically playtest the head-thrower's 1% instant-kill splash for fairness — confirm the wind-up telegraph gives players a real chance to react before tuning odds further.
- Watch for degenerate strategies (e.g., always-save vs. always-spend dominating).

**Phase 6 — Launch Prep**
- Server load testing (concurrent players, robot + zombie count scaling).
- DataStore failure handling / data-loss edge cases.
- Basic analytics hooks (round completion rate, average session length) even without monetization, so you have data to decide on Phase 2 features like monetization or PvP later.

## 7. Decisions Log

| Question | Decision |
|---|---|
| Round win condition | Quota-based (kills scaled per-player, plus a backstop timer) |
| Level cap | None — indefinite leveling |
| Team size | 5–10 players per round |
| Death penalty | Drop equipped weapon at death location; respawn with base weapon; no XP loss (applies uniformly, including head-thrower instant-kill deaths) |
| Weapon variety at launch | 6+ weapons, staged as 3 in Phase 2 → full roster in Phase 5 |
| Enemy roster | Robots (Scout/Grunt/Heavy) and zombies, both in the same spawn pool |
| Zombie weapon variants | Rolled at spawn: 80% punch, ~19% sword, 1% head-thrower (instant-kill AoE splash, telegraphed) |

All open questions from the previous draft are resolved. Nothing left blocking Phase 1 start.

## 8. Risks / Things to Watch

- **Search fatigue:** if the forest is too sparse or too large relative to enemy density, "searching" becomes "wandering," which kills pacing. Needs early playtesting.
- **Spend-vs-save balance:** if buying weapons is strictly better than saving for levels (or vice versa), the core tension collapses. Tune carefully in Phase 5.
- **No monetization at launch** means no revenue signal early — fine for a v1 test, but worth deciding upfront what success metrics you're watching instead (retention, session length, round completion).
- **Quota scaling math needs to be right from day one.** If per-player quota isn't tuned correctly, rounds will feel either trivially easy or impossible depending on how many players joined — this is a Phase 1/3 correctness issue, not a later polish item.
- **6+ weapons is real scope.** Recommend not treating this as "build all 6 now" — the staged 3-then-6+ approach in the phase plan exists specifically to avoid rework if combat balance shifts after early playtesting.
- **Weapon drop on death needs a clear ownership rule** (player-locked pickup vs. free-for-all) decided before Phase 2, since it affects both the mechanic and how griefing/looting complaints get handled.
- **Head-thrower instant-kill fairness is the highest-risk new mechanic in this game.** A 1% spawn chance sounds rare, but at 5–10 players per round across many zombie spawns per round, players will encounter it regularly over a session. If the ~1s telegraph doesn't read clearly in the finished game (readable animation, audio cue), this will feel cheap rather than tense. Playtest this specifically and be willing to extend the telegraph window or lower the splash radius if it's landing as "unavoidable" rather than "dangerous."
