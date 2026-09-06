-- Tests for EnemySpawner: spawn/respawn, and the zombie weapon-variant
-- weighted roll. See the-void-implementation-plan.md Section 5 Phase 2
-- acceptance criteria: "Spawning a large sample of zombies produces variant
-- odds statistically close to 80/19/1" — verified below.

local RobloxEnv = require("../mocks/RobloxEnv")
local env = RobloxEnv.setup()

local frktest = require("@frktest/frktest")
local test = frktest.test
local check = frktest.assert.check

local EnemySpawner = RobloxEnv.requireModule("../../src/ServerScriptService/EnemySpawner")
local TestHelpers = require("../mocks/TestHelpers")

-- EnemySpawner is a cached module shared with every other spec file in this
-- test process (Lune, like Roblox, caches by required path) — reset its
-- live-enemy state so this file's tests aren't affected by whatever ran
-- before it. See EnemySpawner._resetForTests's doc comment.
EnemySpawner._resetForTests()

return function()
	test.suite("EnemySpawner.SpawnEnemy — robots", function()
		test.case("spawns a Grunt with the correct HP and melee attackType", function()
			local enemyId = EnemySpawner.SpawnEnemy("Grunt", CFrame.new(0, 0, 0))

			local enemy = EnemySpawner.GetEnemy(enemyId)
			check.equal(enemy.enemyType, "robot")
			check.equal(enemy.attackType, "melee")
			check.equal(enemy.humanoid.MaxHealth, 60) -- Grunt hp per EnemyTable
			check.equal(enemy.damage, 12) -- Grunt damage per EnemyTable
		end)

		test.case("groundedSpawnCFrame lifts a spawn point so the model's feet touch the given ground height", function()
			-- A model whose PrimaryPart sits at the vertical center of its
			-- bounding box (e.g. a Torso/HumanoidRootPart mid-body), height 6
			-- studs tall — half above, half below the PrimaryPart.
			local groundedY = EnemySpawner._groundedSpawnY(0, 6)

			-- PrimaryPart needs to be 3 studs (half the height) above the
			-- ground so the model's bottom (3 studs below PrimaryPart) lands
			-- exactly on the ground.
			check.equal(groundedY, 3)
		end)

		test.case("clones the real model from ReplicatedStorage.EnemyModels when one exists", function()
			local template = Instance.new("Model")
			template.Name = "GruntRobot"
			local head = Instance.new("Part")
			head.Name = "Head"
			head.Parent = template
			local humanoid = Instance.new("Humanoid")
			humanoid.Parent = template
			template.PrimaryPart = head

			local enemyModels = Instance.new("Model") -- reused as a plain container; only :FindFirstChild matters
			enemyModels.Name = "EnemyModels"
			template.Parent = enemyModels
			env.replicatedStorage.EnemyModels = enemyModels

			local enemyId = EnemySpawner.SpawnEnemy("Grunt", CFrame.new(0, 0, 0))
			local enemy = EnemySpawner.GetEnemy(enemyId)

			check.equal(enemy.model.Name, "GruntRobot")
			check.not_nil(enemy.model:FindFirstChild("Head"))

			env.replicatedStorage.EnemyModels = nil
		end)

		test.case("falls back to the placeholder model if the real one has no Humanoid", function()
			local brokenTemplate = Instance.new("Model")
			brokenTemplate.Name = "GruntRobot"
			local torso = Instance.new("Part")
			torso.Name = "Torso"
			torso.Parent = brokenTemplate
			brokenTemplate.PrimaryPart = torso
			-- Deliberately no Humanoid — simulates a Toolbox model someone
			-- forgot to add one to (a real mistake made once during this
			-- project's own Phase 4 model setup).

			local enemyModels = Instance.new("Model")
			enemyModels.Name = "EnemyModels"
			brokenTemplate.Parent = enemyModels
			env.replicatedStorage.EnemyModels = enemyModels

			-- This case deliberately triggers EnemySpawner's warn() call —
			-- expected, intentional output per the project's testing rules on
			-- intentionally-triggered errors/warnings (there's no warn-capture
			-- seam in this test harness, so this is verified by reading the
			-- test's own console output for the "no Humanoid" line above,
			-- rather than a programmatic assertion).
			local ok, enemyIdOrError = pcall(EnemySpawner.SpawnEnemy, "Grunt", CFrame.new(0, 0, 0))
			env.replicatedStorage.EnemyModels = nil

			check.is_true(ok)
			if not ok then
				error(enemyIdOrError, 0)
			end
			local enemy = EnemySpawner.GetEnemy(enemyIdOrError)

			check.equal(enemy.model.Name, "Grunt") -- placeholder's name, not "GruntRobot"
			check.equal(enemy.humanoid.MaxHealth, 60)
		end)

		test.case("respawns after death at the same spawn point", function()
			local enemyId = EnemySpawner.SpawnEnemy("Scout", CFrame.new(1, 2, 3))
			local enemy = EnemySpawner.GetEnemy(enemyId)

			enemy.humanoid:TakeDamage(math.huge)

			check.equal(EnemySpawner.GetEnemy(enemyId), nil) -- old id no longer live

			task.wait(5.1) -- RESPAWN_DELAY_SECONDS
			local liveEnemies = EnemySpawner.GetAllLiveEnemies()
			local respawned = false
			for _, e in liveEnemies do
				if e.enemyName == "Scout" and e.id ~= enemyId then
					respawned = true
				end
			end
			check.is_true(respawned)
		end)
	end)

	test.suite("EnemySpawner.SpawnEnemy — zombie weapon variant roll", function()
		test.case("every spawned zombie gets a valid weapon variant", function()
			for _ = 1, 20 do
				local enemyId = EnemySpawner.SpawnEnemy("Zombie", CFrame.new(0, 0, 0))
				local enemy = EnemySpawner.GetEnemy(enemyId)
				local isValidVariant = enemy.weaponVariant == "Punch"
					or enemy.weaponVariant == "Sword"
					or enemy.weaponVariant == "HeadThrow"
				check.is_true(isValidVariant)
			end
		end)

		test.case("variant odds are statistically close to 80/19/1 over a large sample", function()
			local counts = { Punch = 0, Sword = 0, HeadThrow = 0 }
			local sampleSize = 10000

			for _ = 1, sampleSize do
				local enemyId = EnemySpawner.SpawnEnemy("Zombie", CFrame.new(0, 0, 0))
				local enemy = EnemySpawner.GetEnemy(enemyId)
				counts[enemy.weaponVariant] += 1
			end

			local punchPct = counts.Punch / sampleSize
			local swordPct = counts.Sword / sampleSize
			local headThrowPct = counts.HeadThrow / sampleSize

			-- Tolerances sized to ~6 standard deviations at this sample size
			-- (stdev for Punch/Sword is ~0.004, for HeadThrow ~0.001 at
			-- n=10000), so this should only ever fail on a real
			-- implementation bug, not sampling noise. An earlier version of
			-- this test used n=2000 with tighter tolerances and was
			-- confirmed flaky (~1-in-8 runs) by direct repeated-run testing
			-- before this fix — three independent statistical checks in one
			-- test compounds each one's small individual failure chance.
			check.is_true(math.abs(punchPct - 0.80) < 0.025)
			check.is_true(math.abs(swordPct - 0.19) < 0.025)
			check.is_true(math.abs(headThrowPct - 0.01) < 0.008)
		end)

		test.case("HeadThrow variant has no damage field (bypasses damage rolls)", function()
			local foundHeadThrow = TestHelpers.spawnUntilVariant(EnemySpawner, "Zombie", CFrame.new(0, 0, 0), "HeadThrow")

			check.not_nil(foundHeadThrow)
			if foundHeadThrow then
				check.equal(foundHeadThrow.variantStats.damage, nil)
				check.equal(foundHeadThrow.attackType, "projectileInstantKillSplash")
			end
		end)
	end)
end
