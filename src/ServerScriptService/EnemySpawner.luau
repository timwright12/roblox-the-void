-- Spawns robots and zombies by tier/type at spawn points, rolls a zombie's
-- weapon variant (punch/sword/head-thrower) once at spawn time per EnemyTable
-- odds, respawns on timer, tracks live enemy count for quota purposes.
-- See the-void-implementation-plan.md Section 3.
--
-- Phase 1: single robot type (Grunt), fixed spawn points, code-built
-- placeholder model (no art pass yet — see the-void-implementation-plan.md
-- Section 5, Phase 1/4).
--
-- Phase 4: real models, sourced from the Toolbox and placed by hand in
-- Studio under ReplicatedStorage.EnemyModels (named per EnemyTable's
-- modelName field — ScoutRobot/GruntRobot/HeavyRobot/ZombieBase), are now
-- cloned per spawn instead of the placeholder — see buildEnemyModel. Since
-- Toolbox models aren't Rojo-managed source files, a type with no matching
-- model there (or in a test's fake environment) still falls back to the
-- placeholder cube rather than erroring.
--
-- Phase 2: adds Scout/Heavy robots and the zombie enemy type. A zombie's
-- weapon variant (Punch/Sword/HeadThrow) is rolled once here at spawn time
-- per EnemyTable.Zombie.weaponVariants.spawnChance and stored on the enemy
-- record for CombatManager to read — it does not change for that zombie's
-- lifetime.

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local EnemyTable = require(ReplicatedStorage.Data.EnemyTable)

local RESPAWN_DELAY_SECONDS = 5
local ENEMY_TAG = "Enemy"

local EnemySpawner = {}

local nextEnemyId = 0
local liveEnemies = {}

local function buildPlaceholderModel(enemyTypeName: string, stats)
	local model = Instance.new("Model")
	model.Name = enemyTypeName

	local torso = Instance.new("Part")
	torso.Name = "Torso"
	torso.Size = Vector3.new(2, 2, 1)
	torso.Anchored = false
	torso.Parent = model

	local humanoid = Instance.new("Humanoid")
	humanoid.MaxHealth = stats.hp
	humanoid.Health = stats.hp
	humanoid.WalkSpeed = stats.speed
	humanoid.Parent = model

	model.PrimaryPart = torso

	return model
end

--- Builds the Model to use for a newly-spawned enemy: clones the real model
--- from ReplicatedStorage.EnemyModels (named per stats.modelName — see
--- EnemyTable.luau) if one has been placed there, applying this enemy's
--- HP/speed onto the clone's Humanoid (a shared template can't bake in
--- per-tier stats). Falls back to the code-built placeholder cube when no
--- such model exists yet — this is what keeps the game running (and the
--- test suite passing, since the fake Roblox environment has no
--- EnemyModels folder) before every enemy type has a real model authored.
local function buildEnemyModel(enemyTypeName: string, stats)
	local enemyModels = ReplicatedStorage:FindFirstChild("EnemyModels")
	local template = enemyModels and enemyModels:FindFirstChild(stats.modelName)
	if not template then
		return buildPlaceholderModel(enemyTypeName, stats)
	end

	local model = template:Clone()
	local humanoid = model:FindFirstChildOfClass("Humanoid")
	humanoid.MaxHealth = stats.hp
	humanoid.Health = stats.hp
	humanoid.WalkSpeed = stats.speed

	return model
end

--- Rolls a weighted random key from a table of { spawnChance = number, ... }
--- entries. Weights are expected to sum to 1.0 (see EnemyTable.lua).
local function rollWeightedVariant(weaponVariants): (string, table)
	local roll = math.random()
	local cumulative = 0

	for variantName, variantStats in weaponVariants do
		cumulative += variantStats.spawnChance
		if roll <= cumulative then
			return variantName, variantStats
		end
	end

	-- Floating point rounding safety net: fall back to the last entry
	-- iterated rather than erroring if weights don't sum to exactly 1.0.
	local lastName, lastStats
	for variantName, variantStats in weaponVariants do
		lastName, lastStats = variantName, variantStats
	end
	return lastName, lastStats
end

--- Spawns a single enemy of the given type at the given CFrame. Returns the
--- enemy's id (used by CombatManager to look it up) and its Model instance.
function EnemySpawner.SpawnEnemy(enemyTypeName: string, spawnCFrame: CFrame)
	local stats = EnemyTable[enemyTypeName]
	assert(stats, `Unknown enemy type: {enemyTypeName}`)

	nextEnemyId += 1
	local enemyId = nextEnemyId

	local model = buildEnemyModel(enemyTypeName, stats)
	model:SetPrimaryPartCFrame(spawnCFrame)
	model:SetAttribute("EnemyId", enemyId)
	CollectionService:AddTag(model, ENEMY_TAG)
	model.Parent = workspace

	local record = {
		id = enemyId,
		enemyType = stats.enemyType,
		enemyName = enemyTypeName,
		model = model,
		humanoid = model:FindFirstChildOfClass("Humanoid"),
		spawnCFrame = spawnCFrame,
	}

	if stats.weaponVariants then
		local variantName, variantStats = rollWeightedVariant(stats.weaponVariants)
		record.weaponVariant = variantName
		record.xpReward = variantStats.xpReward
		record.attackType = variantStats.attackType
		record.variantStats = variantStats
		model:SetAttribute("WeaponVariant", variantName)
	else
		record.xpReward = stats.xpReward
		record.attackType = "melee"
		record.damage = stats.damage
	end

	liveEnemies[enemyId] = record

	record.humanoid.Died:Connect(function()
		liveEnemies[enemyId] = nil
		model:Destroy()

		task.delay(RESPAWN_DELAY_SECONDS, function()
			EnemySpawner.SpawnEnemy(enemyTypeName, spawnCFrame)
		end)
	end)

	return enemyId, model
end

function EnemySpawner.GetEnemy(enemyId: number)
	return liveEnemies[enemyId]
end

--- Returns a snapshot array of all currently-live enemy records.
function EnemySpawner.GetAllLiveEnemies()
	local snapshot = {}
	for _, record in liveEnemies do
		table.insert(snapshot, record)
	end
	return snapshot
end

function EnemySpawner.GetLiveEnemyCount()
	local count = 0
	for _ in liveEnemies do
		count += 1
	end
	return count
end

--- Clears all live-enemy state and resets the id counter. Test-only: a real
--- Roblox server never needs to reset this at runtime. Exists because Lune
--- (like Roblox) caches a required module, so every spec file that requires
--- EnemySpawner in the same `tests/_run.luau` process shares this module's
--- upvalues — without a reset, enemies spawned by one spec file's tests stay
--- "live" when a later spec file's tests run.
function EnemySpawner._resetForTests()
	nextEnemyId = 0
	liveEnemies = {}
end

--- Phase 1 bootstrap: spawns a fixed set of Grunt robots at hardcoded points.
--- Real spawn-point placement happens against the finished map in Phase 4.
function EnemySpawner.StartPhase1Spawns()
	local spawnPoints = {
		CFrame.new(10, 5, 10),
		CFrame.new(-10, 5, 10),
		CFrame.new(0, 5, -15),
	}

	for _, cframe in spawnPoints do
		EnemySpawner.SpawnEnemy("Grunt", cframe)
	end
end

--- Phase 2 bootstrap: adds Scout/Heavy robots and zombies to the spawn
--- rotation alongside Phase 1's Grunts. Fixed points, same caveat as above —
--- real placement is a Phase 4 concern.
function EnemySpawner.StartPhase2Spawns()
	EnemySpawner.StartPhase1Spawns()

	local scoutAndHeavyPoints = {
		Scout = CFrame.new(15, 5, -10),
		Heavy = CFrame.new(-15, 5, -10),
	}
	for enemyTypeName, cframe in scoutAndHeavyPoints do
		EnemySpawner.SpawnEnemy(enemyTypeName, cframe)
	end

	local zombieSpawnPoints = {
		CFrame.new(5, 5, 20),
		CFrame.new(-5, 5, 20),
		CFrame.new(0, 5, 25),
	}
	for _, cframe in zombieSpawnPoints do
		EnemySpawner.SpawnEnemy("Zombie", cframe)
	end
end

return EnemySpawner
