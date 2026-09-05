-- On player death, spawns a physical weapon pickup at death location, reverts
-- player to base weapon; handles pickup interaction. Pickup is player-locked —
-- only the player who died can reclaim it. See the-void-implementation-plan.md
-- Section 3.

local WeaponPickupManager = {}

return WeaponPickupManager
