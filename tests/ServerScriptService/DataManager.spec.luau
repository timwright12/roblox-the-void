-- Tests for DataManager: profile load/save wiring against ProfileStore. See
-- the-void-implementation-plan.md Section 2.1 for the schema and Section 5
-- Phase 2 acceptance criteria ("Rejoining after leaving restores level, XP,
-- and owned weapons correctly").
--
-- Uses FakeProfileStore (an in-memory stand-in matching the real
-- ProfileStore API) rather than the real ProfileStore/DataStore — this tests
-- DataManager's own load/save/session wiring logic, not DataStore
-- reliability itself, which isn't something a unit test can verify anyway
-- (see the-void-implementation-plan.md Section 7 testing checklist: DataStore
-- save/load across a real server restart still needs verifying in Studio).

local RobloxEnv = require("../mocks/RobloxEnv")
local env = RobloxEnv.setup()

local FakeProfileStore = require("../mocks/FakeProfileStore")
env.serverPackages.ProfileStore = RobloxEnv.fakeModule(FakeProfileStore)

local frktest = require("@frktest/frktest")
local test = frktest.test
local check = frktest.assert.check

local DataManager = RobloxEnv.requireModule("../../src/ServerScriptService/DataManager")

local FakePlayer = require("../mocks/FakePlayer")

return function()
	test.suite("DataManager.LoadPlayer / GetData", function()
		test.case("loads a new player with the default template", function()
			local player = FakePlayer.new(1)
			env.players:AddPlayer(player)

			DataManager.LoadPlayer(player)

			local data = DataManager.GetData(player)
			check.not_nil(data)
			check.equal(data.level, 1)
			check.equal(data.xp, 0)
			check.equal(data.equippedWeapon, "BaseSword")
		end)

		test.case("returns nil for a player whose profile hasn't loaded", function()
			local player = FakePlayer.new(2)

			check.equal(DataManager.GetData(player), nil)
		end)

		test.case("persists changes across a simulated rejoin (same profile key)", function()
			local player = FakePlayer.new(3)
			env.players:AddPlayer(player)
			DataManager.LoadPlayer(player)

			local data = DataManager.GetData(player)
			data.level = 5
			data.xp = 42
			table.insert(data.ownedWeapons, "IronSword")

			DataManager.RemovePlayer(player)
			check.equal(DataManager.GetData(player), nil) -- session ended

			-- Simulate rejoining: a new Player instance, same UserId (as
			-- Roblox would give on a real rejoin), loading the same
			-- underlying profile key.
			local rejoinedPlayer = FakePlayer.new(3)
			env.players:AddPlayer(rejoinedPlayer)
			DataManager.LoadPlayer(rejoinedPlayer)

			local reloadedData = DataManager.GetData(rejoinedPlayer)
			check.equal(reloadedData.level, 5)
			check.equal(reloadedData.xp, 42)
			check.not_nil(table.find(reloadedData.ownedWeapons, "IronSword"))
		end)

		test.case("two different new players' nested stats tables are independent, not shared", function()
			local playerA = FakePlayer.new(101)
			local playerB = FakePlayer.new(102)
			env.players:AddPlayer(playerA)
			env.players:AddPlayer(playerB)

			DataManager.LoadPlayer(playerA)
			DataManager.LoadPlayer(playerB)

			local dataA = DataManager.GetData(playerA)
			local dataB = DataManager.GetData(playerB)

			dataA.stats.enemiesKilled = 5
			table.insert(dataA.ownedWeapons, "IronSword")

			check.equal(dataB.stats.enemiesKilled, 0)
			check.equal(#dataB.ownedWeapons, 1)
		end)

		test.case("kicks the player if the session fails to start (Cancel returns true)", function()
			local player = FakePlayer.new(4)
			-- Deliberately not added to env.players, so Parent stays nil —
			-- DataManager's Cancel callback checks `player.Parent ~= Players`,
			-- which is true here, matching "player left before session start".

			DataManager.LoadPlayer(player)

			check.not_nil(player._kickReason)
			check.equal(DataManager.GetData(player), nil)
		end)
	end)

	test.suite("DataManager.RemovePlayer", function()
		test.case("ends the session so GetData returns nil afterward", function()
			local player = FakePlayer.new(5)
			env.players:AddPlayer(player)
			DataManager.LoadPlayer(player)
			check.not_nil(DataManager.GetData(player))

			DataManager.RemovePlayer(player)

			check.equal(DataManager.GetData(player), nil)
		end)

		test.case("is a no-op for a player with no active session", function()
			local player = FakePlayer.new(6)

			local ok = pcall(function()
				DataManager.RemovePlayer(player)
			end)

			check.is_true(ok)
		end)
	end)
end
