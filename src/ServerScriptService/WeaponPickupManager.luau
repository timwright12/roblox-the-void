-- On player death, spawns a physical weapon pickup at death location, reverts
-- player to base weapon; handles pickup interaction. Pickup is player-locked —
-- only the player who died can reclaim it. See the-void-implementation-plan.md
-- Section 3.
--
-- Phase 2: despawn timer is 60 seconds (confirmed with design owner — see
-- the-void-implementation-plan.md Section 6). No XP loss on death — the
-- weapon drop is the entire penalty (product brief Section 5.7).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local RemoteDefinitions = require(ReplicatedStorage.Remotes.RemoteDefinitions)

local BASE_WEAPON_ID = "BaseSword"
local PICKUP_DESPAWN_SECONDS = 60

local WeaponPickupManager = {}

--- Wires the module up against a live DataManager and connects to every
--- current/future player's death. Called once at server startup.
function WeaponPickupManager.Init(dataManager)
	WeaponPickupManager._dataManager = dataManager

	local function onCharacterAdded(player: Player, character: Model)
		local humanoid = character:WaitForChild("Humanoid")
		humanoid.Died:Connect(function()
			WeaponPickupManager.HandlePlayerDeath(player, character)
		end)
	end

	local function onPlayerAdded(player: Player)
		if player.Character then
			onCharacterAdded(player, player.Character)
		end
		player.CharacterAdded:Connect(function(character)
			onCharacterAdded(player, character)
		end)
	end

	for _, player in Players:GetPlayers() do
		onPlayerAdded(player)
	end
	Players.PlayerAdded:Connect(onPlayerAdded)
end

local function buildPickupModel(weaponId: string, position: Vector3, ownerUserId: number): Model
	local model = Instance.new("Model")
	model.Name = `WeaponPickup_{weaponId}`
	model:SetAttribute("WeaponId", weaponId)
	model:SetAttribute("OwnerUserId", ownerUserId)

	local part = Instance.new("Part")
	part.Name = "Handle"
	part.Size = Vector3.new(1, 1, 3)
	part.Anchored = true
	part.CanCollide = false
	part.Position = position
	part.Parent = model

	model.PrimaryPart = part

	part.Touched:Connect(function(otherPart)
		local touchingCharacter = otherPart.Parent
		if not touchingCharacter then
			return
		end

		local touchingPlayer = Players:GetPlayerFromCharacter(touchingCharacter)
		if touchingPlayer then
			WeaponPickupManager.TryReclaimPickup(touchingPlayer, model)
		end
	end)

	return model
end

--- Drops the player's currently equipped weapon at their death location as a
--- player-locked pickup, and reverts their equipped weapon to BaseSword for
--- respawn. Exposed as a direct function so it's testable and reusable.
function WeaponPickupManager.HandlePlayerDeath(player: Player, character: Model)
	local data = WeaponPickupManager._dataManager.GetData(player)
	if not data then
		return
	end

	local droppedWeaponId = data.equippedWeapon
	data.equippedWeapon = BASE_WEAPON_ID

	if droppedWeaponId == BASE_WEAPON_ID then
		-- Nothing meaningful to drop — the base weapon has no purchase cost
		-- and is always available, so there's no pickup to spawn.
		RemoteDefinitions.PlayerDied:FireClient(player, {
			droppedWeaponId = nil,
			respawnWeaponId = BASE_WEAPON_ID,
		})
		return
	end

	local rootPart = character:FindFirstChild("HumanoidRootPart")
	local deathPosition = rootPart and rootPart.Position or Vector3.new(0, 5, 0)

	local pickupModel = buildPickupModel(droppedWeaponId, deathPosition, player.UserId)
	pickupModel.Parent = workspace

	task.delay(PICKUP_DESPAWN_SECONDS, function()
		if pickupModel.Parent then
			pickupModel:Destroy()
		end
	end)

	RemoteDefinitions.PlayerDied:FireClient(player, {
		droppedWeaponId = droppedWeaponId,
		respawnWeaponId = BASE_WEAPON_ID,
	})
end

--- Handles a player attempting to reclaim a dropped weapon. Player-locked:
--- only the player whose UserId matches the pickup's OwnerUserId can succeed.
--- Returns true if the pickup was reclaimed (and destroys it), false
--- otherwise. Exposed as a direct function so it's testable and reusable.
function WeaponPickupManager.TryReclaimPickup(player: Player, pickupModel: Model): boolean
	local ownerUserId = pickupModel:GetAttribute("OwnerUserId")
	if ownerUserId ~= player.UserId then
		return false
	end

	local weaponId = pickupModel:GetAttribute("WeaponId")
	local data = WeaponPickupManager._dataManager.GetData(player)
	if not data then
		return false
	end

	if not table.find(data.ownedWeapons, weaponId) then
		table.insert(data.ownedWeapons, weaponId)
	end
	data.equippedWeapon = weaponId

	pickupModel:Destroy()
	return true
end

return WeaponPickupManager
