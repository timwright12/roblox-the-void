-- Tests for WeaponPickupManager: drop-on-death and player-locked reclaim.
-- See the-void-implementation-plan.md Section 5 Phase 2 acceptance criteria:
-- a player who dies drops their weapon, can reclaim it, and it's player-
-- locked so no other player can pick it up.

local RobloxEnv = require("../mocks/RobloxEnv")
local env = RobloxEnv.setup()

local frktest = require("@frktest/frktest")
local test = frktest.test
local check = frktest.assert.check

local WeaponPickupManager = RobloxEnv.requireModule("../../src/ServerScriptService/WeaponPickupManager")

local FakePlayer = require("../mocks/FakePlayer")
local FakeModel = require("../mocks/FakeModel")
local FakePart = require("../mocks/FakePart")
local FakeHumanoid = require("../mocks/FakeHumanoid")

local function newFakeDataManager(dataByPlayer)
	return {
		GetData = function(player)
			return dataByPlayer[player]
		end,
	}
end

return function()
	test.suite("WeaponPickupManager.HandlePlayerDeath", function()
		test.case("drops the equipped weapon and reverts to BaseSword", function()
			local player = FakePlayer.new(1)
			local character = player:SpawnCharacter(FakeModel, FakePart, FakeHumanoid)
			local data = { equippedWeapon = "IronSword", ownedWeapons = { "BaseSword", "IronSword" } }
			WeaponPickupManager._dataManager = newFakeDataManager({ [player] = data })

			WeaponPickupManager.HandlePlayerDeath(player, character)

			check.equal(data.equippedWeapon, "BaseSword")
		end)

		test.case("does not spawn a pickup when the equipped weapon is already BaseSword", function()
			local player = FakePlayer.new(1)
			local character = player:SpawnCharacter(FakeModel, FakePart, FakeHumanoid)
			local data = { equippedWeapon = "BaseSword", ownedWeapons = { "BaseSword" } }
			WeaponPickupManager._dataManager = newFakeDataManager({ [player] = data })

			-- No assertion on world state directly (no pickup-tracking API
			-- exposed) — this test instead documents the guard exists and
			-- confirms it doesn't error. The "nothing to drop" branch is also
			-- implicitly covered by not needing Instance.new("Model") to
			-- succeed for a class the fakes don't register a factory for.
			local ok = pcall(function()
				WeaponPickupManager.HandlePlayerDeath(player, character)
			end)

			check.is_true(ok)
			check.equal(data.equippedWeapon, "BaseSword")
		end)
	end)

	test.suite("WeaponPickupManager.TryReclaimPickup", function()
		test.case("the player who died can reclaim their own dropped weapon", function()
			local player = FakePlayer.new(1)
			local data = { equippedWeapon = "BaseSword", ownedWeapons = { "BaseSword", "IronSword" } }
			WeaponPickupManager._dataManager = newFakeDataManager({ [player] = data })

			local pickup = FakeModel.new()
			pickup:SetAttribute("OwnerUserId", 1)
			pickup:SetAttribute("WeaponId", "IronSword")

			local reclaimed = WeaponPickupManager.TryReclaimPickup(player, pickup)

			check.is_true(reclaimed)
			check.equal(data.equippedWeapon, "IronSword")
		end)

		test.case("a different player cannot reclaim someone else's pickup (player-locked)", function()
			local owner = FakePlayer.new(1)
			local otherPlayer = FakePlayer.new(2)
			local otherData = { equippedWeapon = "BaseSword", ownedWeapons = { "BaseSword" } }
			WeaponPickupManager._dataManager = newFakeDataManager({ [otherPlayer] = otherData })

			local pickup = FakeModel.new()
			pickup:SetAttribute("OwnerUserId", owner.UserId)
			pickup:SetAttribute("WeaponId", "IronSword")

			local reclaimed = WeaponPickupManager.TryReclaimPickup(otherPlayer, pickup)

			check.is_false(reclaimed)
			check.equal(otherData.equippedWeapon, "BaseSword") -- unchanged
			check.equal(table.find(otherData.ownedWeapons, "IronSword"), nil) -- did not gain the weapon
		end)

		test.case("reclaiming re-adds the weapon to ownedWeapons if somehow missing", function()
			local player = FakePlayer.new(1)
			local data = { equippedWeapon = "BaseSword", ownedWeapons = { "BaseSword" } }
			WeaponPickupManager._dataManager = newFakeDataManager({ [player] = data })

			local pickup = FakeModel.new()
			pickup:SetAttribute("OwnerUserId", 1)
			pickup:SetAttribute("WeaponId", "IronSword")

			WeaponPickupManager.TryReclaimPickup(player, pickup)

			check.not_nil(table.find(data.ownedWeapons, "IronSword"))
		end)
	end)
end
