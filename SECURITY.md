# Security Policy

## Scope

This covers security issues in **this repository's code** — the Rojo-managed server/client Luau modules, the CI workflows, and the publish pipeline. It does not cover Roblox platform-level vulnerabilities (report those to [Roblox directly](https://en.help.roblox.com/hc/en-us/articles/203312300)) or issues in third-party dependencies (report those upstream — e.g. [ProfileStore](https://github.com/MadStudioRoblox/ProfileStore), [frktest](https://github.com/itsfrank/frktest) — though we'd appreciate a heads-up here too if a dependency issue affects this project).

Examples of what's in scope for this repo specifically:
- A way to make client-claimed state (damage, XP, currency, owned weapons) get trusted server-side instead of validated.
- A DataStore bug that can duplicate, delete, or corrupt player data (level, XP, owned weapons).
- A way to publish to production without going through the intended `savetoroblox` workflow/authorization.
- Exposure of the `ROBLOX_API_KEY` or other secrets (in a workflow file, log output, or committed code).
- A way to bypass `RemoteEvent`/`RemoteFunction` validation to trigger server actions the client shouldn't be able to trigger directly.

## Reporting a Vulnerability

**Please do not open a public GitHub issue for security vulnerabilities.** Public issues are visible to everyone, including anyone who might exploit the report before it's fixed.

Instead, use GitHub's private reporting flow:

1. Go to the [Security tab](../../security) of this repository.
2. Click **Report a vulnerability** under "Advisories."
3. Describe the issue: what it is, how to reproduce it, and its potential impact (e.g. "any player can duplicate weapons by doing X" vs. "this could crash the server").

This opens a private advisory visible only to the maintainer until it's resolved.

## What to Expect

- Acknowledgment of your report as soon as reasonably possible.
- An assessment of severity and, if confirmed, a fix developed privately (so it can't be exploited before it ships).
- Credit in the eventual public advisory or release notes, if you'd like it — let us know your preference when reporting.

Since this is a single-maintainer, pre-launch/actively-developed project rather than a company with a formal SLA, response times may vary, but reports are taken seriously — especially anything touching server-authoritative validation or player data (`DataManager`, `CombatManager`, `ShopManager`, per [`docs/the-void-implementation-plan.md`](docs/the-void-implementation-plan.md) Sections 3–4).

## Supported Versions

There are no versioned releases of the game itself — `main` is the actively developed branch, and only the current state of `main` (and whatever is currently published to the staging/production Roblox places) is supported. Please report issues against the latest `main`.
