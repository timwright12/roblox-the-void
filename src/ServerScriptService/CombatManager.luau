-- Authoritative damage resolution for player-vs-enemy hits, for both robots and
-- zombies. Client sends attack intent, server validates range/cooldown and
-- applies damage. Also owns the zombie head-thrower projectile: telegraph
-- timer, thrown head projectile, and splash-radius instant-kill resolution.
-- See the-void-implementation-plan.md Section 3.
--
-- Phase 1: server-validated melee attack against the single Grunt enemy type
-- using BaseSword stats (no shop/equip system yet — that's Phase 2).
--
-- Phase 2: enemies now attack back. Scope is intentionally minimal —
-- stationary enemies check for a player within range on a fixed interval and
-- attack (punch/sword damage, or the head-thrower telegraph/splash sequence).
-- No chase/pathfinding AI yet; that's deferred past Phase 2 since it isn't
-- called for in the-void-implementation-plan.md and risks rework once real
-- map geometry exists in Phase 4 to path against. Player damage/range/cooldown
-- now come from the player's DataManager-tracked equippedWeapon instead of a
-- hardcoded BaseSword constant.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local WeaponTable = require(ReplicatedStorage.Data.WeaponTable)
local RemoteDefinitions = require(ReplicatedStorage.Remotes.RemoteDefinitions)
local Players = game:GetService("Players")

local FALLBACK_WEAPON = WeaponTable.BaseSword
local ENEMY_ATTACK_CHECK_INTERVAL_SECONDS = 1
local ENEMY_MELEE_RANGE = 6

local CombatManager = {}

local lastAttackAt = {}
local lastEnemyAttackAt = {}
local pendingHeadThrows = {}

--- Wires the module up against a live EnemySpawner, XPManager, DataManager,
--- and RoundManager. Called once at server startup.
function CombatManager.Init(enemySpawner, xpManager, dataManager, roundManager)
	CombatManager._enemySpawner = enemySpawner
	CombatManager._xpManager = xpManager
	CombatManager._dataManager = dataManager
	CombatManager._roundManager = roundManager

	RemoteDefinitions.AttackIntent.OnServerEvent:Connect(function(player, enemyId)
		CombatManager.HandleAttackIntent(player, enemyId)
	end)

	task.spawn(function()
		while true do
			task.wait(ENEMY_ATTACK_CHECK_INTERVAL_SECONDS)
			CombatManager.TickEnemyAttacks()
		end
	end)
end

--- Cleans up per-player tracking state. Call on PlayerRemoving to avoid
--- leaking entries for players who have left.
function CombatManager.RemovePlayer(player: Player)
	lastAttackAt[player] = nil
end

--- Returns the WeaponTable entry for the player's currently equipped weapon,
--- falling back to BaseSword if their profile isn't loaded yet or their
--- equipped weapon id is somehow invalid (defensive — should not happen).
local function getEquippedWeapon(player: Player)
	local data = CombatManager._dataManager.GetData(player)
	if not data then
		return FALLBACK_WEAPON
	end

	return WeaponTable[data.equippedWeapon] or FALLBACK_WEAPON
end

local function getPlayerRoot(player: Player): BasePart?
	local character = player.Character
	if not character then
		return nil
	end
	return character:FindFirstChild("HumanoidRootPart")
end

local function isInRange(player: Player, model: Model, range: number): boolean
	local playerRoot = getPlayerRoot(player)
	local enemyRoot = model.PrimaryPart
	if not playerRoot or not enemyRoot then
		return false
	end

	local distance = (playerRoot.Position - enemyRoot.Position).Magnitude
	return distance <= range
end

--- Finds the nearest player within `range` studs of `originPosition`, or nil.
local function findNearestPlayerInRange(originPosition: Vector3, range: number): Player?
	local nearestPlayer = nil
	local nearestDistance = range

	for _, player in Players:GetPlayers() do
		local playerRoot = getPlayerRoot(player)
		if playerRoot then
			local distance = (playerRoot.Position - originPosition).Magnitude
			if distance <= nearestDistance then
				nearestDistance = distance
				nearestPlayer = player
			end
		end
	end

	return nearestPlayer
end

local function damagePlayer(player: Player, amount: number)
	local character = player.Character
	if not character then
		return
	end

	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid:TakeDamage(amount)
	end
end

local function instantKillPlayer(player: Player)
	local character = player.Character
	if not character then
		return
	end

	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		-- TakeDamage (not setting Health = 0 directly) is the reliable way to
		-- guarantee Humanoid.Died fires — Roblox has documented edge cases
		-- where a direct Health assignment to 0 doesn't fire Died, which
		-- would silently break the death-penalty flow (WeaponPickupManager).
		humanoid:TakeDamage(math.huge)
	end
end

--- Resolves one zombie's head-throw: telegraph, then a splash-radius instant
--- kill of any player still in range when the head lands. The thrown head
--- itself has no travel-time simulation in Phase 2 — the wind-up is the
--- telegraph, and the splash resolves at the zombie's position on landing.
local function startHeadThrow(enemy)
	if pendingHeadThrows[enemy.id] then
		return
	end
	pendingHeadThrows[enemy.id] = true

	local variantStats = enemy.variantStats
	RemoteDefinitions.ZombieHeadThrowTelegraph:FireAllClients({
		zombieId = enemy.id,
		windUpSeconds = variantStats.windUpSeconds,
	})

	task.delay(variantStats.windUpSeconds, function()
		pendingHeadThrows[enemy.id] = nil

		if not enemy.model.Parent then
			return -- zombie died mid wind-up; no explosion.
		end

		local originPosition = enemy.model.PrimaryPart.Position
		for _, player in Players:GetPlayers() do
			local playerRoot = getPlayerRoot(player)
			if playerRoot then
				local distance = (playerRoot.Position - originPosition).Magnitude
				if distance <= variantStats.splashRadius then
					instantKillPlayer(player)
				end
			end
		end
	end)
end

--- Runs one pass of enemy-vs-player attacks. Stationary/interval-based by
--- design for Phase 2 — see module header.
function CombatManager.TickEnemyAttacks()
	local enemySpawner = CombatManager._enemySpawner
	local now = os.clock()

	for _, enemy in enemySpawner.GetAllLiveEnemies() do
		CombatManager._tickOneEnemyAttack(enemy, now)
	end
end

function CombatManager._tickOneEnemyAttack(enemy, now: number)
	if enemy.attackType == "melee" then
		local last = lastEnemyAttackAt[enemy.id]
		if last and (now - last) < 1 then
			return
		end

		local originPosition = enemy.model.PrimaryPart.Position
		local target = findNearestPlayerInRange(originPosition, ENEMY_MELEE_RANGE)
		if target then
			lastEnemyAttackAt[enemy.id] = now
			damagePlayer(target, enemy.variantStats and enemy.variantStats.damage or enemy.damage)
		end
	elseif enemy.attackType == "projectileInstantKillSplash" then
		local originPosition = enemy.model.PrimaryPart.Position
		local anyPlayerInRange = findNearestPlayerInRange(originPosition, ENEMY_MELEE_RANGE) ~= nil
		if anyPlayerInRange then
			startHeadThrow(enemy)
		end
	end
end

--- Validates and resolves one attack attempt against an enemy. Exposed as a
--- direct function (not just via the remote) so it's testable and reusable.
function CombatManager.HandleAttackIntent(player: Player, enemyId: number): (boolean, string?)
	local weapon = getEquippedWeapon(player)
	local cooldownSeconds = 1 / weapon.fireRate

	local now = os.clock()
	local last = lastAttackAt[player]
	if last and (now - last) < cooldownSeconds then
		return false, "OnCooldown"
	end

	local enemySpawner = CombatManager._enemySpawner
	local enemy = enemySpawner.GetEnemy(enemyId)
	if not enemy then
		return false, "EnemyNotFound"
	end

	if not isInRange(player, enemy.model, weapon.range) then
		return false, "OutOfRange"
	end

	lastAttackAt[player] = now

	local humanoid = enemy.humanoid
	humanoid:TakeDamage(weapon.damage)

	if humanoid.Health <= 0 then
		lastEnemyAttackAt[enemyId] = nil
		pendingHeadThrows[enemyId] = nil

		local xpManager = CombatManager._xpManager
		local newState = xpManager.AwardXP(player, enemy.xpReward)

		CombatManager._roundManager.RecordKill(player, enemy.xpReward)

		if newState then
			RemoteDefinitions.EnemyKilled:FireClient(player, {
				enemyId = enemyId,
				enemyType = enemy.enemyType,
				xpAwarded = enemy.xpReward,
				newXp = newState.xp,
				newLevel = newState.level,
			})
		end
	end

	return true, nil
end

return CombatManager
