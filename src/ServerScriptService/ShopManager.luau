-- Validates and processes weapon purchase requests: checks XP balance, deducts
-- XP, adds to ownedWeapons, sets equippedWeapon. Rejects purchases server-side
-- even if client UI misbehaves. See the-void-implementation-plan.md Section 3.

local ShopManager = {}

return ShopManager
