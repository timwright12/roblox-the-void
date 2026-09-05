# Getting Started — From Zero to a Published Roblox Experience

This document is the on-ramp for building and publishing **The Void**. It assumes no prior Roblox development experience and walks from installing tools through getting a build live on Roblox. It does not repeat design decisions (see `the-void-product-brief.md`) or the module/schema plan (see `the-void-implementation-plan.md`) — it's purely the "how do I get a Roblox game running and published" mechanics.

## 1. Accounts You'll Need

- **A Roblox account** (roblox.com) — this is both your player account and your creator account. If you don't already have one, sign up there first.
- **Two-factor authentication (2FA) is worth enabling** on the account before you publish anything — Roblox increasingly requires it for creator features (like enabling monetization or API access later), and it's good practice regardless.

## 2. Install Roblox Studio

1. Go to roblox.com, log in, and click **Create** in the top nav (or go directly to the Creator Hub).
2. Studio installs from there, or directly via the "Start Creating" / download prompt on the Creator Hub.
3. Launch Studio and sign in with your Roblox account.
4. From the Studio landing page, start a **New Baseplate** (or any basic template) once — just to confirm Studio opens, renders a scene, and you can hit **Play** to test in-editor. This is your "hello world" check before touching real project files.

Studio itself is a full IDE + 3D editor + built-in script editor. For this project we will **not** primarily write code inside Studio's built-in script editor — see Section 3 on Rojo — but you'll still use Studio's UI heavily for building the map, placing parts, testing, and publishing.

## 3. Install Rojo (Required — This Project's Workflow Depends On It)

The implementation plan (`the-void-implementation-plan.md`, Section 1) specifies building with **Rojo** so code lives in a normal file tree under version control instead of inside Studio's opaque `.rbxl` file. This is the single most important tooling difference from "typical" beginner Roblox tutorials, which usually show you writing scripts directly inside Studio.

### 3.1 What Rojo actually does

Rojo runs a local sync server that watches your project's file tree (the `src/` folder structure from the implementation plan) and pushes those files into an open Studio session in real time via a companion Studio plugin. You edit `.lua` files in a normal text editor/IDE, save, and Rojo syncs the change into Studio automatically. This means:
- Your code is real files, diffable and committable in git (as we're already doing).
- Studio becomes primarily the place you test/play the game and build the physical map (parts, terrain, models) — not where source-of-truth code lives.

### 3.2 Installing Rojo

Two pieces are required — the CLI tool and the Studio plugin:

1. **Rojo CLI**: Install via a toolchain manager so the version is pinned and reproducible. Roblox's ecosystem historically pointed to **Aftman**, but Aftman's upstream repo is archived/unmaintained — use **[mise](https://mise.jdx.dev)** instead (actively maintained, and Homebrew-installable: `brew install mise`). Once `mise` is installed and activated in your shell (`eval "$(mise activate zsh)"` in `~/.zshrc`, or the equivalent for your shell), install Rojo with:
   ```
   mise use -g "github:rojo-rbx/rojo@latest"
   ```
   This pulls the CLI binary directly from Rojo's GitHub releases (with attestation verification) rather than building from source — much faster than compiling. If you don't want a toolchain manager at all, `brew install rojo` or a manual download from the [Rojo GitHub releases page](https://github.com/rojo-rbx/rojo/releases) both work too, just without version pinning across machines.
2. **Rojo Studio Plugin**: Inside Studio, go to the **Plugins** tab → **Manage Plugins** (or the Toolbox) and search for "Rojo," or install it via the CLI with `rojo plugin install` (this drops the plugin into Studio's local plugins folder automatically — simplest option).
3. Verify install: run `rojo --version` in a terminal to confirm the CLI is on your PATH.

**Note on Apple Silicon vs. Intel Macs:** installing `mise` itself via Homebrew is quick on Apple Silicon (a prebuilt bottle exists), but on an unsupported/older platform combination Homebrew may fall back to compiling `mise` from Rust source, which can take 30+ minutes. This is a one-time cost — Rojo itself installs in seconds afterward since it's a direct binary download, not a source build.

### 3.3 Setting up this project with Rojo

The implementation plan already specifies the target file tree (`default.project.json` at the root, `src/ServerScriptService`, `src/ReplicatedStorage`, etc. — see implementation plan Section 1). To actually initialize that:

1. From the repo root, run `rojo init` if `default.project.json` doesn't exist yet — this scaffolds a default project file you'll then edit to match the structure in the implementation plan.
2. Create the folder structure under `src/` as specified in the implementation plan.
3. Open (or create) your game's `.rbxl` file in Studio.
4. In Studio, open the Rojo plugin panel and click **Connect** (default port `34872`).
5. In a terminal at the repo root, run `rojo serve` — this starts the sync server.
6. Once connected, anything under `src/` should appear in Studio's Explorer panel in the corresponding services (ServerScriptService, ReplicatedStorage, etc.), and stays live-synced as you edit files.

**Important workflow note going forward:** once Rojo is wired up, do not hand-author scripts inside Studio's Explorer/script editor for anything that should live in `src/` — changes made directly in Studio to a Rojo-synced tree can be overwritten or cause sync conflicts. Studio-side edits should be limited to things Rojo doesn't manage well by default: map geometry, terrain, part placement, lighting, and non-scripted instances. Confirm this boundary as the project grows; if it becomes unclear which side owns what, that's worth raising rather than guessing.

### 3.4 Installing Wally (Roblox Package Manager)

This project uses [Wally](https://github.com/UpliftGames/wally) to manage external Lua dependencies (currently just [ProfileStore](https://github.com/MadStudioRoblox/ProfileStore) for DataStore persistence — see the-void-implementation-plan.md Section 2.1). Install via `mise`, same pattern as Rojo:

```
mise use -g "github:UpliftGames/wally@latest"
```

Then, from the repo root, install the project's dependencies:

```
mise exec -- wally install
```

This reads `wally.toml` and downloads packages into `ServerPackages/` (and `Packages/` for anything shared client/server) — both directories are gitignored since they're reproducible from `wally.toml`/`wally.lock`, which **are** committed. Run `wally install` again any time `wally.toml` changes or after a fresh clone, before opening the project in Studio — `DataManager` and anything else depending on a Wally package will error on require until this has been run at least once.

## 4. Building and Testing Locally

- Use Studio's **Play** button (or **Play Here** / **Play as Server+Clients** for multiplayer-relevant testing) to run the game in-editor. For anything server-authoritative (which, per the implementation plan, is nearly everything — combat, XP, purchases), use **Play as Server+Clients** or **Start Server** with multiple **Start Player** clients so you're actually testing client/server boundaries, not just a single local client that trivially trusts itself.
- Studio's **Output** window shows server and client print/warn/error output — this is where you'll verify server-authoritative behavior (e.g., confirming XP is calculated server-side, per the testing checklist in the implementation plan).
- For quick iteration on scripts, keep `rojo serve` running in the background and just re-enter Play mode in Studio after each save — no need to restart Rojo itself between test runs.

## 5. Publishing to Roblox (Getting a Build Live)

"Live" on Roblox has a few distinct meanings depending on what you want — worth being precise about since they're different actions:

### 5.1 Publish the place (uploads your build to Roblox's servers)

1. In Studio, **File → Publish to Roblox** (or **Publish to Roblox As...** the first time, to name it and choose/create the associated game).
2. This uploads your current Studio session's content as a new version of the place. It does **not** require Rojo to be running — publishing takes whatever is currently loaded in Studio's Explorer, so make sure your Rojo-synced state is fully synced before publishing (i.e., don't publish mid-edit with the sync server stopped and stale content sitting in Studio).
3. First publish creates the "experience" (what Roblox now calls games) in your creator account; subsequent publishes update it.

### 5.2 Configure the experience (Creator Hub / in-Studio Game Settings)

Before or after first publish, go to **Home → Game Settings** in Studio (or the Creator Hub website) to set:
- **Name, description, and icon/thumbnail** — required for the experience to look legitimate to players.
- **Access permissions**: while building, keep this **Private** or restricted to yourself/testers. Only make it **Public** when you actually intend for anyone to find and join it.
- **Playability/age settings** and any content maturity questions Roblox's compliance flow asks.
- **Max players per server** — relevant here since the product brief specifies 5–10 player rounds; set server size accordingly (Studio's default is higher, e.g. 50).

### 5.3 DataStores need to be explicitly enabled

The implementation plan relies on `DataStoreService` for persistence (level, XP, owned weapons). DataStores **do not work by default in Studio's Play-mode testing** unless you enable API access:
- In Studio: **Home → Game Settings → Security → Enable Studio Access to API Services**.
- In live (published) servers, DataStores work automatically once the experience is published — no separate toggle needed there, but Studio testing needs the setting above or every `DataStoreService` call will error/no-op.
- Test DataStore save/load in actual Play sessions (per the implementation plan's testing checklist) before assuming persistence works — this is a common early gotcha.

### 5.4 Going from "published but private" to "actually live"

1. Confirm the experience works end-to-end privately first: invite a couple of friends as testers via the experience's access settings, or share the private link if using restricted access.
2. When ready for real players, set the experience's access to **Public** in Game Settings.
3. Roblox may run automated moderation/compliance checks on newly public experiences (especially around monetization, chat, and age-appropriate content) — since the product brief specifies no monetization and no PvP at launch, this should be a lighter review than a monetized experience, but budget a little time for it rather than assuming instant approval.
4. Once public, the experience is discoverable via your profile, direct link, and (eventually, with enough engagement) Roblox's discovery surfaces. Friend-join (Section 5.7 of the product brief) works automatically once public — no separate setup needed beyond the experience being joinable.

## 6. Ongoing Workflow Summary

Day-to-day, once everything above is set up once:

1. Pull latest from git.
2. `rojo serve` in the repo root.
3. Open the project's `.rbxl` in Studio, connect the Rojo plugin.
4. Edit code in your text editor/IDE (not in Studio), map/terrain/parts in Studio directly.
5. Test in Play mode (Server+Clients for anything server-authoritative).
6. Commit code changes to git as normal.
7. When ready to test a build with others or ship an update, **File → Publish to Roblox**.

## 7. Common Early Gotchas

- **DataStore calls silently fail in Studio** if API access isn't enabled (Section 5.3) — don't mistake this for a code bug.
- **Rojo sync conflicts**: if you edit something in Studio that's also managed by Rojo's `src/` tree, the next sync can overwrite your Studio-side change without warning. Keep the boundary clean (Section 3.3).
- **Testing server-authoritative logic with only one client** (default Play button) can hide bugs that only show up with a real client/server split — use **Play as Server+Clients** for anything touching combat/XP/purchases, per the implementation plan's "verify server-side, not just client display" guidance.
- **Publishing doesn't restart Rojo sync** — if Rojo isn't running or is out of sync when you publish, you'll publish stale content. Publish right after confirming your local Play-test reflects the intended state.
- **Access set to Public too early**: keep the experience Private/restricted until you're actually ready for outside players, since Public triggers discoverability and moderation review.
