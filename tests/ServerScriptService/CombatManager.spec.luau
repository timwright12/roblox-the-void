-- Tests for CombatManager: player-attacks-enemy (range/cooldown/damage/kill),
-- and enemy-attacks-player (melee, and the head-thrower telegraph -> splash
-- instant-kill sequence). See the-void-implementation-plan.md Section 5
-- Phase 2 acceptance criteria.
--
-- CombatManager.Init() is deliberately never called — it starts an infinite
-- task.spawn polling loop (enemy attack ticking) with no natural exit under
-- Lune, unlike a real Roblox server which just runs forever anyway. Instead,
-- the same fields Init() would set (_enemySpawner, _xpManager, _dataManager,
-- _roundManager) are set directly, and CombatManager.HandleAttackIntent /
-- ._tickOneEnemyAttack are called directly rather than through the remote or
-- the polling loop.

local RobloxEnv = require("../mocks/RobloxEnv")
local env = RobloxEnv.setup()

local frktest = require("@frktest/frktest")
local test = frktest.test
local check = frktest.assert.check

local EnemySpawner = RobloxEnv.requireModule("../../src/ServerScriptService/EnemySpawner")
local XPManager = RobloxEnv.requireModule("../../src/ServerScriptService/XPManager")
local CombatManager = RobloxEnv.requireModule("../../src/ServerScriptService/CombatManager")

local FakePlayer = require("../mocks/FakePlayer")
local FakeModel = require("../mocks/FakeModel")
local FakePart = require("../mocks/FakePart")
local FakeHumanoid = require("../mocks/FakeHumanoid")
local TestHelpers = require("../mocks/TestHelpers")

-- EnemySpawner is a cached module shared with every other spec file in this
-- test process — reset its live-enemy state so this file's tests aren't
-- affected by whatever ran before it. See EnemySpawner._resetForTests's doc
-- comment.
EnemySpawner._resetForTests()

-- Resets the fake Players service before adding the new player, so leftover
-- players (and their positions) from a previous test case in this file never
-- leak into findNearestPlayerInRange's "nearest" search.
local function newPlayerAt(userId: number, position)
	env.players:Reset()
	local player = FakePlayer.new(userId)
	local _character, rootPart = player:SpawnCharacter(FakeModel, FakePart, FakeHumanoid)
	rootPart.Position = position
	env.players:AddPlayer(player)
	return player
end

local function wireCombatManager(dataByPlayer)
	local killedPlayers = {}
	local xpAwardedTo = {}

	local dataManager = TestHelpers.newFakeDataManager(dataByPlayer)
	XPManager.Init(dataManager)

	local roundManager = {
		RecordKill = function(player, xp)
			table.insert(killedPlayers, player)
			xpAwardedTo[player] = xp
		end,
	}

	CombatManager._enemySpawner = EnemySpawner
	CombatManager._xpManager = XPManager
	CombatManager._dataManager = dataManager
	CombatManager._roundManager = roundManager

	return killedPlayers, xpAwardedTo
end

return function()
	test.suite("CombatManager.HandleAttackIntent — player attacks", function()
		test.case("rejects an attack when the enemy is out of range", function()
			wireCombatManager({})
			local player = newPlayerAt(1, Vector3.new(0, 0, 0))
			local enemyId = EnemySpawner.SpawnEnemy("Grunt", CFrame.new(1000, 0, 0))

			local ok, reason = CombatManager.HandleAttackIntent(player, enemyId)

			check.is_false(ok)
			check.equal(reason, "OutOfRange")
		end)

		test.case("rejects an attack against a nonexistent enemy id", function()
			wireCombatManager({})
			local player = newPlayerAt(1, Vector3.new(0, 0, 0))

			local ok, reason = CombatManager.HandleAttackIntent(player, 999999)

			check.is_false(ok)
			check.equal(reason, "EnemyNotFound")
		end)

		test.case("rejects a second attack within the weapon's cooldown window", function()
			local data = { equippedWeapon = "BaseSword", level = 1, xp = 0, totalXp = 0 }
			local player = newPlayerAt(1, Vector3.new(0, 0, 0))
			wireCombatManager({ [player] = data })

			local enemyId = EnemySpawner.SpawnEnemy("Grunt", CFrame.new(0, 0, 0))

			local ok1 = CombatManager.HandleAttackIntent(player, enemyId)
			local ok2, reason2 = CombatManager.HandleAttackIntent(player, enemyId)

			check.is_true(ok1)
			check.is_false(ok2)
			check.equal(reason2, "OnCooldown")
		end)

		test.case("RemovePlayer clears the attack cooldown so a rejoining player isn't stuck on it", function()
			local data = { equippedWeapon = "BaseSword", level = 1, xp = 0, totalXp = 0 }
			local player = newPlayerAt(1, Vector3.new(0, 0, 0))
			wireCombatManager({ [player] = data })

			local enemyId = EnemySpawner.SpawnEnemy("Grunt", CFrame.new(0, 0, 0))
			local ok1 = CombatManager.HandleAttackIntent(player, enemyId)
			check.is_true(ok1)

			CombatManager.RemovePlayer(player)

			-- Without RemovePlayer clearing lastAttackAt, this second attack
			-- (against a different enemy, no time elapsed) would be rejected
			-- as "OnCooldown" — the exact leak this method exists to prevent.
			local otherEnemyId = EnemySpawner.SpawnEnemy("Grunt", CFrame.new(0, 0, 0))
			local ok2, reason2 = CombatManager.HandleAttackIntent(player, otherEnemyId)

			check.is_true(ok2)
			check.equal(reason2, nil)
		end)

		test.case("applies the equipped weapon's damage, not a hardcoded value", function()
			local data = { equippedWeapon = "Crossbow", level = 1, xp = 0, totalXp = 0 }
			local player = newPlayerAt(1, Vector3.new(0, 0, 0))
			wireCombatManager({ [player] = data })

			local enemyId = EnemySpawner.SpawnEnemy("Heavy", CFrame.new(0, 0, 0))
			local enemy = EnemySpawner.GetEnemy(enemyId)
			local healthBefore = enemy.humanoid.Health

			CombatManager.HandleAttackIntent(player, enemyId)

			check.equal(enemy.humanoid.Health, healthBefore - 25) -- Crossbow damage per WeaponTable
		end)

		test.case("awards XP and records the kill when an enemy dies", function()
			local data = { equippedWeapon = "BaseSword", level = 1, xp = 0, totalXp = 0 }
			local player = newPlayerAt(1, Vector3.new(0, 0, 0))
			local killedPlayers, xpAwardedTo = wireCombatManager({ [player] = data })

			local enemyId = EnemySpawner.SpawnEnemy("Scout", CFrame.new(0, 0, 0)) -- 20 hp, dies in 2 base-sword hits
			CombatManager.HandleAttackIntent(player, enemyId)
			task.wait(1.1)
			CombatManager.HandleAttackIntent(player, enemyId)

			check.equal(data.xp, 5) -- Scout's xpReward
			check.equal(#killedPlayers, 1)
			check.equal(killedPlayers[1], player)
			check.equal(xpAwardedTo[player], 5)
		end)
	end)

	test.suite("CombatManager._tickOneEnemyAttack — enemy attacks", function()
		test.case("melee enemy damages the nearest player in range", function()
			wireCombatManager({})
			local player = newPlayerAt(1, Vector3.new(0, 0, 0))
			local enemyId = EnemySpawner.SpawnEnemy("Grunt", CFrame.new(2, 0, 0))
			local enemy = EnemySpawner.GetEnemy(enemyId)
			local healthBefore = player.Character:FindFirstChildOfClass("Humanoid").Health

			CombatManager._tickOneEnemyAttack(enemy, os.clock())

			local healthAfter = player.Character:FindFirstChildOfClass("Humanoid").Health
			check.equal(healthAfter, healthBefore - 12) -- Grunt damage
		end)

		test.case("melee enemy does not attack a player outside its range", function()
			wireCombatManager({})
			local player = newPlayerAt(1, Vector3.new(1000, 0, 0))
			local enemyId = EnemySpawner.SpawnEnemy("Grunt", CFrame.new(0, 0, 0))
			local enemy = EnemySpawner.GetEnemy(enemyId)
			local healthBefore = player.Character:FindFirstChildOfClass("Humanoid").Health

			CombatManager._tickOneEnemyAttack(enemy, os.clock())

			local healthAfter = player.Character:FindFirstChildOfClass("Humanoid").Health
			check.equal(healthAfter, healthBefore)
		end)

		test.case("head-thrower telegraphs then instant-kills a player still in splash radius", function()
			wireCombatManager({})
			local player = newPlayerAt(1, Vector3.new(1, 0, 0))

			local enemy = TestHelpers.spawnUntilVariant(EnemySpawner, "Zombie", CFrame.new(0, 0, 0), "HeadThrow")
			check.not_nil(enemy)

			CombatManager._tickOneEnemyAttack(enemy, os.clock())

			-- Player should still be alive during the wind-up.
			local humanoid = player.Character:FindFirstChildOfClass("Humanoid")
			check.is_true(humanoid.Health > 0)

			task.wait(enemy.variantStats.windUpSeconds + 0.1)

			check.equal(humanoid.Health, 0)
		end)

		test.case("head-thrower does not explode if the player left splash radius during wind-up", function()
			wireCombatManager({})
			local player = newPlayerAt(1, Vector3.new(1, 0, 0))

			local enemy = TestHelpers.spawnUntilVariant(EnemySpawner, "Zombie", CFrame.new(0, 0, 0), "HeadThrow")
			check.not_nil(enemy)

			CombatManager._tickOneEnemyAttack(enemy, os.clock())

			-- Player moves far away during the wind-up.
			local rootPart = player.Character:FindFirstChild("HumanoidRootPart")
			rootPart.Position = Vector3.new(1000, 0, 0)

			task.wait(enemy.variantStats.windUpSeconds + 0.1)

			local humanoid = player.Character:FindFirstChildOfClass("Humanoid")
			check.is_true(humanoid.Health > 0)
		end)

		test.case("head-thrower does not explode if the zombie died during wind-up", function()
			wireCombatManager({})
			local player = newPlayerAt(1, Vector3.new(1, 0, 0))

			local enemy = TestHelpers.spawnUntilVariant(EnemySpawner, "Zombie", CFrame.new(0, 0, 0), "HeadThrow")
			check.not_nil(enemy)

			CombatManager._tickOneEnemyAttack(enemy, os.clock())
			enemy.humanoid:TakeDamage(math.huge) -- zombie dies mid wind-up

			task.wait(enemy.variantStats.windUpSeconds + 0.1)

			local humanoid = player.Character:FindFirstChildOfClass("Humanoid")
			check.is_true(humanoid.Health > 0)
		end)
	end)
end
