-- Authoritative damage resolution for player-vs-enemy hits, for both robots and
-- zombies. Client sends attack intent, server validates range/cooldown and
-- applies damage. Also owns the zombie head-thrower projectile: telegraph
-- timer, thrown head projectile, and splash-radius instant-kill resolution.
-- See the-void-implementation-plan.md Section 3.

local CombatManager = {}

return CombatManager
