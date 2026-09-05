-- Tests for XPManager's XP-award and level-up math. See
-- the-void-implementation-plan.md Section 2.1 for the schema this reads/
-- writes (xp resets on level-up, totalXp never decreases).

local RobloxEnv = require("../mocks/RobloxEnv")
RobloxEnv.setup()

local frktest = require("@frktest/frktest")
local test = frktest.test
local check = frktest.assert.check

local XPManager = RobloxEnv.requireModule("../../src/ServerScriptService/XPManager")

local function newFakeDataManager(initialData)
	local data = initialData
	return {
		GetData = function(player)
			return data
		end,
	}
end

return function()
	test.suite("XPManager.AwardXP", function()
		test.case("awards XP without leveling up when below threshold", function()
			local dataManager = newFakeDataManager({ level = 1, xp = 0, totalXp = 0 })
			XPManager.Init(dataManager)

			local result = XPManager.AwardXP({}, 40)

			check.equal(result.level, 1)
			check.equal(result.xp, 40)
			check.equal(result.totalXp, 40)
		end)

		test.case("levels up exactly at the 100 XP threshold", function()
			local dataManager = newFakeDataManager({ level = 1, xp = 90, totalXp = 90 })
			XPManager.Init(dataManager)

			local result = XPManager.AwardXP({}, 10)

			check.equal(result.level, 2)
			check.equal(result.xp, 0)
			check.equal(result.totalXp, 100)
		end)

		test.case("handles a single award crossing multiple levels", function()
			local dataManager = newFakeDataManager({ level = 1, xp = 0, totalXp = 0 })
			XPManager.Init(dataManager)

			local result = XPManager.AwardXP({}, 250)

			check.equal(result.level, 3)
			check.equal(result.xp, 50)
			check.equal(result.totalXp, 250)
		end)

		test.case("totalXp accumulates across multiple awards and never resets", function()
			local dataManager = newFakeDataManager({ level = 1, xp = 0, totalXp = 0 })
			XPManager.Init(dataManager)

			XPManager.AwardXP({}, 60)
			local result = XPManager.AwardXP({}, 60)

			check.equal(result.level, 2)
			check.equal(result.xp, 20)
			check.equal(result.totalXp, 120)
		end)

		test.case("returns nil when the player's profile isn't loaded", function()
			local dataManager = { GetData = function(player) return nil end }
			XPManager.Init(dataManager)

			local result = XPManager.AwardXP({}, 10)

			check.equal(result, nil)
		end)
	end)

	test.suite("XPManager.GetState", function()
		test.case("returns level/xp/totalXp for a loaded profile", function()
			local dataManager = newFakeDataManager({ level = 3, xp = 20, totalXp = 220 })
			XPManager.Init(dataManager)

			local state = XPManager.GetState({})

			check.equal(state.level, 3)
			check.equal(state.xp, 20)
			check.equal(state.totalXp, 220)
		end)

		test.case("returns nil when the player's profile isn't loaded", function()
			local dataManager = { GetData = function(player) return nil end }
			XPManager.Init(dataManager)

			check.equal(XPManager.GetState({}), nil)
		end)
	end)
end
