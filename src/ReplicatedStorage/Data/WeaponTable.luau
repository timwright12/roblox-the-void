-- Single source of truth for weapon stats, referenced by both shop UI and
-- combat damage calculation. Placeholder starting numbers, not final balance —
-- see the-void-implementation-plan.md Section 2.2 and Section 6.

return {
	BaseSword = { name = "Base Sword", cost = 0, damage = 10, fireRate = 1.0, range = 5, tier = 0 },
	IronSword = { name = "Iron Sword", cost = 50, damage = 18, fireRate = 1.0, range = 5, tier = 1 },
	Crossbow = { name = "Crossbow", cost = 80, damage = 25, fireRate = 0.7, range = 30, tier = 1 },
	-- Expand to 6+ in Phase 5. Keep this table as the single source of truth
	-- referenced by both shop UI and combat damage calculation.
}
