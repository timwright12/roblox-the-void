-- Aggro/chase behavior once a player enters an enemy's detection radius.
-- See the-void-implementation-plan.md Section 9 for the full design.
--
-- Added after Phase 4 real terrain/models existed — stationary enemies felt
-- inert (any ranged weapon could damage one risk-free from outside its
-- ENEMY_MELEE_RANGE). Runs its own independent tick loop (same pattern as
-- CombatManager.TickEnemyAttacks, but separate — this module never resolves
-- damage, CombatManager never moves anything, per Section 9.3).
--
-- Movement (PathfindingService, Humanoid:MoveTo) isn't unit-tested — neither
-- exists in Lune's fake Roblox environment, same category as
-- AnalyticsService. Only the state decision (_nextState) is a pure function,
-- unit-tested in EnemyAI.spec.luau; verifying an enemy actually walks toward
-- a player (and navigates around a tree) is a manual Studio playtest per
-- Section 9.4.

local PathfindingService = game:GetService("PathfindingService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local PlayerFinder = require(ReplicatedStorage.Modules.PlayerFinder)

local TICK_INTERVAL_SECONDS = 1
local PATH_RECOMPUTE_INTERVAL_SECONDS = 1
local AGGRO_RADIUS_STUDS = 25
local RELEASE_RADIUS_STUDS = AGGRO_RADIUS_STUDS * 1.5

local EnemyAI = {}

-- Per-enemy state: "Idle" | "Chasing". Not persisted — reset per server
-- session, same lifetime as EnemySpawner's own liveEnemies.
local stateByEnemyId = {}
local lastPathComputeAt = {}

--- Wires the module up against a live EnemySpawner and starts the aggro tick
--- loop. Called once at server startup.
function EnemyAI.Init(enemySpawner)
	EnemyAI._enemySpawner = enemySpawner

	task.spawn(function()
		while true do
			task.wait(TICK_INTERVAL_SECONDS)
			EnemyAI.Tick()
		end
	end)
end

--- Pure decision: given an enemy's current state, its position, and the
--- current list of players, returns the state it should be in next.
--- Idle -> Chasing once any player is within AGGRO_RADIUS_STUDS.
--- Chasing -> Idle once no player remains within RELEASE_RADIUS_STUDS (a
--- larger radius than the trigger, so an enemy doesn't flicker between
--- states when a player sits right at the boundary).
function EnemyAI._nextState(currentState: string, enemyPosition: Vector3, players: { Player }): string
	if currentState == "Idle" then
		local target = PlayerFinder.findNearestPlayerInRange(players, enemyPosition, AGGRO_RADIUS_STUDS)
		if target then
			return "Chasing"
		end
		return "Idle"
	end

	-- Chasing
	local stillInRange = PlayerFinder.findNearestPlayerInRange(players, enemyPosition, RELEASE_RADIUS_STUDS)
	if stillInRange then
		return "Chasing"
	end
	return "Idle"
end

--- Computes a path to `destination` and walks the enemy's Humanoid along it.
--- A thin wrapper around PathfindingService — not unit-tested, see module
--- header.
local function moveTowards(enemy, destination: Vector3)
	local origin = enemy.model.PrimaryPart.Position
	local path = PathfindingService:CreatePath({})
	local ok = pcall(function()
		path:ComputeAsync(origin, destination)
	end)

	print("DEBUG EnemyAI moveTowards:", enemy.enemyName, "ok=", ok, "status=", path.Status)

	if not ok or path.Status ~= Enum.PathStatus.Success then
		return
	end

	local waypoints = path:GetWaypoints()
	print("DEBUG EnemyAI waypoints count=", #waypoints)
	if waypoints[2] then
		enemy.humanoid:MoveTo(waypoints[2].Position)
	end
end

--- Runs one pass of chase-state updates and, for any Chasing enemy whose
--- path is due for a refresh, recomputes it toward the nearest player.
function EnemyAI.Tick()
	local Players = game:GetService("Players")
	local players = Players:GetPlayers()
	local now = os.clock()

	for _, enemy in EnemyAI._enemySpawner.GetAllLiveEnemies() do
		local currentState = stateByEnemyId[enemy.id] or "Idle"
		local enemyPosition = enemy.model.PrimaryPart.Position
		local nextState = EnemyAI._nextState(currentState, enemyPosition, players)
		stateByEnemyId[enemy.id] = nextState
		print("DEBUG EnemyAI tick:", enemy.enemyName, currentState, "->", nextState, "pos=", enemyPosition, "walkSpeed=", enemy.humanoid.WalkSpeed)

		if nextState == "Chasing" then
			local lastCompute = lastPathComputeAt[enemy.id]
			if not lastCompute or (now - lastCompute) >= PATH_RECOMPUTE_INTERVAL_SECONDS then
				lastPathComputeAt[enemy.id] = now
				local target = PlayerFinder.findNearestPlayerInRange(players, enemyPosition, RELEASE_RADIUS_STUDS)
				if target then
					local targetRoot = PlayerFinder.getPlayerRoot(target)
					if targetRoot then
						moveTowards(enemy, targetRoot.Position)
					end
				end
			end
		elseif currentState == "Chasing" and nextState == "Idle" then
			-- Just released: path back to spawn once, rather than every tick.
			lastPathComputeAt[enemy.id] = nil
			moveTowards(enemy, enemy.spawnCFrame.Position)
		end
	end
end

--- Test-only: clears all chase state. Lune (like Roblox) caches a required
--- module, so every spec file sharing this test process would otherwise see
--- stale state from whatever ran before it — same reasoning as
--- EnemySpawner._resetForTests.
function EnemyAI._resetForTests()
	stateByEnemyId = {}
	lastPathComputeAt = {}
end

return EnemyAI
