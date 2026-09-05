-- Spawns robots and zombies by tier/type at spawn points, rolls a zombie's
-- weapon variant (punch/sword/head-thrower) once at spawn time per EnemyTable
-- odds, respawns on timer, tracks live enemy count for quota purposes.
-- See the-void-implementation-plan.md Section 3.
--
-- Phase 1 scope: single robot type (Grunt), fixed spawn points, code-built
-- placeholder model (no art pass yet — see the-void-implementation-plan.md
-- Section 5, Phase 1/4). Real models are swapped in later by pointing this
-- module's model construction at EnemyTable's modelName instead.

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

--- Spawns a single enemy of the given type at the given CFrame. Returns the
--- enemy's id (used by CombatManager to look it up) and its Model instance.
function EnemySpawner.SpawnEnemy(enemyTypeName: string, spawnCFrame: CFrame)
	local stats = EnemyTable[enemyTypeName]
	assert(stats, `Unknown enemy type: {enemyTypeName}`)

	nextEnemyId += 1
	local enemyId = nextEnemyId

	local model = buildPlaceholderModel(enemyTypeName, stats)
	model:SetPrimaryPartCFrame(spawnCFrame)
	model:SetAttribute("EnemyId", enemyId)
	CollectionService:AddTag(model, ENEMY_TAG)
	model.Parent = workspace

	local record = {
		id = enemyId,
		enemyType = enemyTypeName,
		xpReward = stats.xpReward,
		model = model,
		humanoid = model:FindFirstChildOfClass("Humanoid"),
		spawnCFrame = spawnCFrame,
	}
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

function EnemySpawner.GetLiveEnemyCount()
	local count = 0
	for _ in liveEnemies do
		count += 1
	end
	return count
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

return EnemySpawner
