-- Authoritative damage resolution for player-vs-enemy hits, for both robots and
-- zombies. Client sends attack intent, server validates range/cooldown and
-- applies damage. Also owns the zombie head-thrower projectile: telegraph
-- timer, thrown head projectile, and splash-radius instant-kill resolution.
-- See the-void-implementation-plan.md Section 3.
--
-- Phase 1 scope: server-validated melee attack against the single Grunt
-- enemy type using BaseSword stats (no shop/equip system yet — that's
-- Phase 2). Zombie/head-thrower handling arrives in Phase 2 alongside
-- zombies themselves.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local WeaponTable = require(ReplicatedStorage.Data.WeaponTable)
local RemoteDefinitions = require(ReplicatedStorage.Remotes.RemoteDefinitions)

local BASE_WEAPON = WeaponTable.BaseSword
local ATTACK_COOLDOWN_SECONDS = 1 / BASE_WEAPON.fireRate

local CombatManager = {}

local lastAttackAt = {}

--- Wires the module up against a live EnemySpawner and XPManager. Called once
--- at server startup.
function CombatManager.Init(enemySpawner, xpManager)
	CombatManager._enemySpawner = enemySpawner
	CombatManager._xpManager = xpManager

	RemoteDefinitions.AttackIntent.OnServerEvent:Connect(function(player, enemyId)
		CombatManager.HandleAttackIntent(player, enemyId)
	end)
end

local function isInRange(player: Player, model: Model): boolean
	local character = player.Character
	if not character then
		return false
	end

	local playerRoot = character:FindFirstChild("HumanoidRootPart")
	local enemyRoot = model.PrimaryPart
	if not playerRoot or not enemyRoot then
		return false
	end

	local distance = (playerRoot.Position - enemyRoot.Position).Magnitude
	return distance <= BASE_WEAPON.range
end

--- Validates and resolves one attack attempt against an enemy. Exposed as a
--- direct function (not just via the remote) so it's testable and reusable.
function CombatManager.HandleAttackIntent(player: Player, enemyId: number): (boolean, string?)
	local now = os.clock()
	local last = lastAttackAt[player]
	if last and (now - last) < ATTACK_COOLDOWN_SECONDS then
		return false, "OnCooldown"
	end

	local enemySpawner = CombatManager._enemySpawner
	local enemy = enemySpawner.GetEnemy(enemyId)
	if not enemy then
		return false, "EnemyNotFound"
	end

	if not isInRange(player, enemy.model) then
		return false, "OutOfRange"
	end

	lastAttackAt[player] = now

	local humanoid = enemy.humanoid
	humanoid:TakeDamage(BASE_WEAPON.damage)

	if humanoid.Health <= 0 then
		local xpManager = CombatManager._xpManager
		local newState = xpManager.AwardXP(player, enemy.xpReward)

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
