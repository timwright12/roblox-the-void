-- Single source of truth for enemy stats, covering both robots and zombies.
-- Every entry has an enemyType field so spawner/combat code can branch on
-- category where needed. Zombies additionally carry a weaponVariants table:
-- EnemySpawner rolls a variant per the listed spawnChance weights (weights
-- sum to 1.0) at spawn time, and that variant is fixed for the zombie's
-- lifetime. Placeholder starting numbers, not final balance — see
-- the-void-implementation-plan.md Section 2.3 and Section 6.

return {
	Scout = { hp = 20, damage = 5, speed = 20, xpReward = 5, modelName = "ScoutRobot", enemyType = "robot" },
	Grunt = { hp = 60, damage = 12, speed = 12, xpReward = 12, modelName = "GruntRobot", enemyType = "robot" },
	Heavy = { hp = 150, damage = 25, speed = 6, xpReward = 30, modelName = "HeavyRobot", enemyType = "robot" },

	Zombie = {
		hp = 40,
		speed = 14,
		modelName = "ZombieBase",
		enemyType = "zombie",
		-- Base damage/xpReward are overridden per-variant below; keep these as sane fallbacks only.
		damage = 8,
		xpReward = 8,
		weaponVariants = {
			Punch = { spawnChance = 0.80, damage = 8, xpReward = 8, attackType = "melee" },
			Sword = { spawnChance = 0.19, damage = 16, xpReward = 14, attackType = "melee" },
			HeadThrow = {
				spawnChance = 0.01,
				xpReward = 25,
				attackType = "projectileInstantKillSplash",
				windUpSeconds = 1.0, -- telegraph duration before the head is thrown
				splashRadius = 8, -- studs; anyone inside on impact is instant-killed
				-- No damage field: this attack bypasses HP/damage rolls entirely on splash contact.
			},
		},
	},
}
