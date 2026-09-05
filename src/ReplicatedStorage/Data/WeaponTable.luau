-- Single source of truth for weapon stats, referenced by both shop UI and
-- combat damage calculation. Placeholder starting numbers, not final balance —
-- see the-void-implementation-plan.md Section 2.2 and Section 6.

return {
	BaseSword = { name = "Base Sword", cost = 0, damage = 10, fireRate = 1.0, range = 5, tier = 0 },
	IronSword = { name = "Iron Sword", cost = 50, damage = 18, fireRate = 1.0, range = 5, tier = 1 },
	Crossbow = { name = "Crossbow", cost = 80, damage = 25, fireRate = 0.7, range = 30, tier = 1 },
	SteelSword = { name = "Steel Sword", cost = 65, damage = 22, fireRate = 1.1, range = 5, tier = 1 },
	WarHammer = { name = "War Hammer", cost = 150, damage = 45, fireRate = 0.5, range = 6, tier = 2 },
	Longbow = { name = "Longbow", cost = 180, damage = 35, fireRate = 0.9, range = 45, tier = 2 },
}
