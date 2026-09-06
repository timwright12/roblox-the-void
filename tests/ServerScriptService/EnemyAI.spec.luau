-- Tests for EnemyAI's aggro/release state machine. See the-void-
-- implementation-plan.md Section 9 for the design: an Idle enemy starts
-- Chasing once a player is within AGGRO_RADIUS_STUDS, and a Chasing enemy
-- returns to Idle once no player is within RELEASE_RADIUS_STUDS (a larger
-- radius than the trigger, so an enemy doesn't flicker at the boundary).
--
-- Movement itself (PathfindingService, Humanoid:MoveTo) isn't tested here —
-- neither exists in Lune's fake Roblox environment, and per Section 9.4 this
-- is an accepted, Studio-playtest-only gap, the same category as
-- AnalyticsService. Only the state decisions (should this enemy start/stop
-- chasing, given distances) are unit-tested.

local RobloxEnv = require("../mocks/RobloxEnv")
local env = RobloxEnv.setup()

local frktest = require("@frktest/frktest")
local test = frktest.test
local check = frktest.assert.check

local EnemyAI = RobloxEnv.requireModule("../../src/ServerScriptService/EnemyAI")

local FakePlayer = require("../mocks/FakePlayer")
local FakeModel = require("../mocks/FakeModel")
local FakePart = require("../mocks/FakePart")
local FakeHumanoid = require("../mocks/FakeHumanoid")

local function newPlayerAt(userId: number, position)
	env.players:Reset()
	local player = FakePlayer.new(userId)
	local _character, rootPart = player:SpawnCharacter(FakeModel, FakePart, FakeHumanoid)
	rootPart.Position = position
	env.players:AddPlayer(player)
	return player
end

return function()
	test.suite("EnemyAI._nextState", function()
		test.case("Idle enemy becomes Chasing when a player enters the aggro radius", function()
			newPlayerAt(1, Vector3.new(10, 0, 0)) -- 10 studs away

			local nextState = EnemyAI._nextState("Idle", Vector3.new(0, 0, 0), env.players:GetPlayers())

			check.equal(nextState, "Chasing")
		end)

		test.case("Idle enemy stays Idle when no player is within the aggro radius", function()
			newPlayerAt(1, Vector3.new(100, 0, 0)) -- far outside AGGRO_RADIUS_STUDS

			local nextState = EnemyAI._nextState("Idle", Vector3.new(0, 0, 0), env.players:GetPlayers())

			check.equal(nextState, "Idle")
		end)

		test.case("Chasing enemy stays Chasing while a player remains within the release radius", function()
			-- Beyond the aggro (trigger) radius but still within the larger
			-- release radius — an already-chasing enemy should not give up
			-- just because the player stepped slightly further away.
			newPlayerAt(1, Vector3.new(30, 0, 0))

			local nextState = EnemyAI._nextState("Chasing", Vector3.new(0, 0, 0), env.players:GetPlayers())

			check.equal(nextState, "Chasing")
		end)

		test.case("Chasing enemy returns to Idle once no player is within the release radius", function()
			newPlayerAt(1, Vector3.new(100, 0, 0))

			local nextState = EnemyAI._nextState("Chasing", Vector3.new(0, 0, 0), env.players:GetPlayers())

			check.equal(nextState, "Idle")
		end)

		test.case("stays Idle with zero players in the server", function()
			env.players:Reset()

			local nextState = EnemyAI._nextState("Idle", Vector3.new(0, 0, 0), env.players:GetPlayers())

			check.equal(nextState, "Idle")
		end)
	end)
end
