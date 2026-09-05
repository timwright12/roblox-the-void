-- Tests for ShopManager's purchase/equip validation. See
-- the-void-implementation-plan.md Section 5 Phase 2 acceptance criteria:
-- purchasing with insufficient XP must be rejected server-side even if
-- attempted directly (i.e. bypassing whatever the client UI would normally
-- prevent) — these tests call ShopManager.PurchaseWeapon directly, which is
-- exactly that "spoofed call" scenario.

local RobloxEnv = require("../mocks/RobloxEnv")
RobloxEnv.setup()

local frktest = require("@frktest/frktest")
local test = frktest.test
local check = frktest.assert.check

local ShopManager = RobloxEnv.requireModule("../../src/ServerScriptService/ShopManager")
local TestHelpers = require("../mocks/TestHelpers")

return function()
	test.suite("ShopManager.PurchaseWeapon", function()
		test.case("succeeds when the player has enough XP", function()
			local player = {}
			local data = { xp = 100, ownedWeapons = { "BaseSword" }, equippedWeapon = "BaseSword" }
			ShopManager._dataManager = TestHelpers.newFakeDataManager({ [player] = data })

			local result = ShopManager.PurchaseWeapon(player, "IronSword")

			check.is_true(result.success)
			check.equal(result.newXp, 50) -- IronSword costs 50
			check.equal(data.equippedWeapon, "IronSword")
		end)

		test.case("rejects a purchase with insufficient XP, even called directly", function()
			local player = {}
			local data = { xp = 10, ownedWeapons = { "BaseSword" }, equippedWeapon = "BaseSword" }
			ShopManager._dataManager = TestHelpers.newFakeDataManager({ [player] = data })

			local result = ShopManager.PurchaseWeapon(player, "IronSword")

			check.is_false(result.success)
			check.equal(result.reason, "InsufficientXP")
			check.equal(data.xp, 10) -- unchanged
			check.equal(data.equippedWeapon, "BaseSword") -- unchanged
		end)

		test.case("rejects purchasing an already-owned weapon", function()
			local player = {}
			local data = { xp = 100, ownedWeapons = { "BaseSword", "IronSword" }, equippedWeapon = "BaseSword" }
			ShopManager._dataManager = TestHelpers.newFakeDataManager({ [player] = data })

			local result = ShopManager.PurchaseWeapon(player, "IronSword")

			check.is_false(result.success)
			check.equal(result.reason, "AlreadyOwned")
			check.equal(data.xp, 100) -- unchanged, not double-charged
		end)

		test.case("succeeds purchasing a Phase 5 tier-2 weapon (WarHammer)", function()
			local player = {}
			local data = { xp = 200, ownedWeapons = { "BaseSword" }, equippedWeapon = "BaseSword" }
			ShopManager._dataManager = TestHelpers.newFakeDataManager({ [player] = data })

			local result = ShopManager.PurchaseWeapon(player, "WarHammer")

			check.is_true(result.success)
			check.equal(result.newXp, 200 - 150) -- WarHammer costs 150
			check.equal(data.equippedWeapon, "WarHammer")
		end)

		test.case("rejects an unknown weapon id", function()
			local player = {}
			local data = { xp = 1000, ownedWeapons = { "BaseSword" }, equippedWeapon = "BaseSword" }
			ShopManager._dataManager = TestHelpers.newFakeDataManager({ [player] = data })

			local result = ShopManager.PurchaseWeapon(player, "NotARealWeapon")

			check.is_false(result.success)
			check.equal(result.reason, "UnknownWeapon")
		end)

		test.case("rejects when the player's profile isn't loaded", function()
			ShopManager._dataManager = TestHelpers.newFakeDataManager({})

			local result = ShopManager.PurchaseWeapon({}, "IronSword")

			check.is_false(result.success)
			check.equal(result.reason, "ProfileNotLoaded")
		end)
	end)

	test.suite("ShopManager.EquipWeapon", function()
		test.case("equips a weapon the player already owns", function()
			local player = {}
			local data = { ownedWeapons = { "BaseSword", "Crossbow" }, equippedWeapon = "BaseSword" }
			ShopManager._dataManager = TestHelpers.newFakeDataManager({ [player] = data })

			ShopManager.EquipWeapon(player, "Crossbow")

			check.equal(data.equippedWeapon, "Crossbow")
		end)

		test.case("does not equip a weapon the player does not own", function()
			local player = {}
			local data = { ownedWeapons = { "BaseSword" }, equippedWeapon = "BaseSword" }
			ShopManager._dataManager = TestHelpers.newFakeDataManager({ [player] = data })

			ShopManager.EquipWeapon(player, "Crossbow")

			check.equal(data.equippedWeapon, "BaseSword")
		end)

		test.case("silently no-ops on an unknown weapon id", function()
			local player = {}
			local data = { ownedWeapons = { "BaseSword" }, equippedWeapon = "BaseSword" }
			ShopManager._dataManager = TestHelpers.newFakeDataManager({ [player] = data })

			ShopManager.EquipWeapon(player, "NotARealWeapon")

			check.equal(data.equippedWeapon, "BaseSword")
		end)
	end)
end
