-- Validates and processes weapon purchase requests: checks XP balance, deducts
-- XP, adds to ownedWeapons, sets equippedWeapon. Rejects purchases server-side
-- even if client UI misbehaves. See the-void-implementation-plan.md Section 3.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local WeaponTable = require(ReplicatedStorage.Data.WeaponTable)
local RemoteDefinitions = require(ReplicatedStorage.Remotes.RemoteDefinitions)

local ShopManager = {}

--- Wires the module up against a live DataManager and Analytics. Called
--- once at server startup.
function ShopManager.Init(dataManager, analytics)
	ShopManager._dataManager = dataManager
	ShopManager._analytics = analytics

	RemoteDefinitions.PurchaseWeapon.OnServerInvoke = function(player, weaponId)
		return ShopManager.PurchaseWeapon(player, weaponId)
	end

	RemoteDefinitions.EquipWeapon.OnServerEvent:Connect(function(player, weaponId)
		ShopManager.EquipWeapon(player, weaponId)
	end)
end

local function ownsWeapon(data, weaponId: string): boolean
	return table.find(data.ownedWeapons, weaponId) ~= nil
end

--- Validates and processes a weapon purchase. Exposed as a direct function
--- (not just via the remote) so it's testable and reusable. Always returns a
--- table matching the PurchaseWeapon network contract, never throws for
--- invalid input — bad requests are rejected, not crashed on.
function ShopManager.PurchaseWeapon(player: Player, weaponId: string)
	local weaponStats = WeaponTable[weaponId]
	if not weaponStats then
		return { success = false, reason = "UnknownWeapon" }
	end

	local data = ShopManager._dataManager.GetData(player)
	if not data then
		return { success = false, reason = "ProfileNotLoaded" }
	end

	if ownsWeapon(data, weaponId) then
		return { success = false, reason = "AlreadyOwned" }
	end

	if data.xp < weaponStats.cost then
		return { success = false, reason = "InsufficientXP" }
	end

	data.xp -= weaponStats.cost
	table.insert(data.ownedWeapons, weaponId)
	data.equippedWeapon = weaponId

	if ShopManager._analytics then
		ShopManager._analytics.LogWeaponPurchased(player, weaponId, weaponStats.cost, data.xp)
	end

	return {
		success = true,
		newXp = data.xp,
		ownedWeapons = data.ownedWeapons,
	}
end

--- Switches the player's equipped weapon among weapons they already own. No
--- XP cost. Silently no-ops on an invalid/unowned weaponId — equip requests
--- have no failure payload in the network contract (RemoteEvent, not
--- RemoteFunction), so there's nothing meaningful to report back to a
--- misbehaving client beyond simply not applying the change.
function ShopManager.EquipWeapon(player: Player, weaponId: string)
	if not WeaponTable[weaponId] then
		return
	end

	local data = ShopManager._dataManager.GetData(player)
	if not data then
		return
	end

	if not ownsWeapon(data, weaponId) then
		return
	end

	data.equippedWeapon = weaponId
end

return ShopManager
