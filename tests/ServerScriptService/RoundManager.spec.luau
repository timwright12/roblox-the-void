-- Tests for RoundManager's quota tracking and round lifecycle. See the-void-
-- implementation-plan.md Section 5 Phase 3 for quota calculation
-- (quotaPerPlayer * playerCount) and Section 8 for the network contract.
--
-- Note: RoundManager keeps its state (state/quotaTarget/quotaProgress/etc.)
-- as module-level upvalues, not fields on the returned table, and Lune (like
-- Roblox) caches a required module — so every test case in this file shares
-- the same module instance. Each test calls RoundManager.StartRound() first
-- to reset to a known state rather than relying on test execution order.
-- RoundManager.Init() is deliberately never called here — it starts an
-- infinite task.spawn polling loop with no natural exit under Lune (see
-- CombatManager.spec.luau for the same reasoning). _dataManager is set
-- directly instead, the same field Init() would set.

local RobloxEnv = require("../mocks/RobloxEnv")
local env = RobloxEnv.setup()

local frktest = require("@frktest/frktest")
local test = frktest.test
local check = frktest.assert.check

local RoundManager = RobloxEnv.requireModule("../../src/ServerScriptService/RoundManager")
local FakePlayer = require("../mocks/FakePlayer")
local TestHelpers = require("../mocks/TestHelpers")

local function newPlayerWithData(userId: number)
	local player = FakePlayer.new(userId)
	local data = { stats = { roundsPlayed = 0, enemiesKilled = 0 } }
	return player, data
end

return function()
	test.suite("RoundManager.StartRound", function()
		test.case("calculates quota as 10 per player", function()
			local p1, d1 = newPlayerWithData(1)
			local p2, d2 = newPlayerWithData(2)
			env.players:AddPlayer(p1)
			env.players:AddPlayer(p2)
			RoundManager._dataManager = TestHelpers.newFakeDataManager({ [p1] = d1, [p2] = d2 })

			RoundManager.StartRound()

			local state = RoundManager.GetState()
			check.equal(state.state, "Active")
			check.equal(state.quotaTarget, 20)
			check.equal(state.quotaProgress, 0)

			env.players:RemovePlayerFromGame(p1)
			env.players:RemovePlayerFromGame(p2)
		end)

		test.case("increments roundsPlayed for every player in the server", function()
			local p1, d1 = newPlayerWithData(1)
			env.players:AddPlayer(p1)
			RoundManager._dataManager = TestHelpers.newFakeDataManager({ [p1] = d1 })

			RoundManager.StartRound()

			check.equal(d1.stats.roundsPlayed, 1)

			env.players:RemovePlayerFromGame(p1)
		end)

		test.case("quota is never zero even with zero players", function()
			RoundManager._dataManager = TestHelpers.newFakeDataManager({})

			RoundManager.StartRound()

			check.equal(RoundManager.GetState().quotaTarget, 10)
		end)

		test.case("logs a RoundStarted analytics event for every player in the server", function()
			local p1, d1 = newPlayerWithData(1)
			local p2, d2 = newPlayerWithData(2)
			env.players:AddPlayer(p1)
			env.players:AddPlayer(p2)
			RoundManager._dataManager = TestHelpers.newFakeDataManager({ [p1] = d1, [p2] = d2 })
			local analytics, calls = TestHelpers.newFakeAnalytics()
			RoundManager._analytics = analytics

			RoundManager.StartRound()

			check.equal(#calls.LogRoundStarted, 1)
			local loggedPlayers = calls.LogRoundStarted[1][1]
			check.equal(#loggedPlayers, 2)

			env.players:RemovePlayerFromGame(p1)
			env.players:RemovePlayerFromGame(p2)
			RoundManager._analytics = nil
		end)
	end)

	test.suite("RoundManager.RecordKill", function()
		test.case("increments quota progress during an active round", function()
			local p1, d1 = newPlayerWithData(1)
			env.players:AddPlayer(p1)
			RoundManager._dataManager = TestHelpers.newFakeDataManager({ [p1] = d1 })
			RoundManager.StartRound()

			RoundManager.RecordKill(p1, 10)

			check.equal(RoundManager.GetState().quotaProgress, 1)
			check.equal(d1.stats.enemiesKilled, 1)

			env.players:RemovePlayerFromGame(p1)
		end)

		test.case("ends the round once quota is met", function()
			local p1, d1 = newPlayerWithData(1)
			env.players:AddPlayer(p1)
			RoundManager._dataManager = TestHelpers.newFakeDataManager({ [p1] = d1 })
			RoundManager.StartRound() -- quotaTarget = 10 (1 player)

			for _ = 1, 10 do
				RoundManager.RecordKill(p1, 5)
			end

			check.equal(RoundManager.GetState().state, "Ended")

			env.players:RemovePlayerFromGame(p1)
		end)

		test.case("counts lifetime enemiesKilled even outside an active round", function()
			local p1, d1 = newPlayerWithData(1)
			env.players:AddPlayer(p1)
			RoundManager._dataManager = TestHelpers.newFakeDataManager({ [p1] = d1 })
			RoundManager.StartRound()
			RoundManager.EndRound("QuotaMet") -- state is now "Ended", not "Active"

			RoundManager.RecordKill(p1, 5)

			check.equal(d1.stats.enemiesKilled, 1)
			check.equal(RoundManager.GetState().quotaProgress, 0) -- did not count toward quota

			env.players:RemovePlayerFromGame(p1)
		end)

		test.case("EndRound's pushed summary reports each player's kills and XP earned this round only", function()
			local p1, d1 = newPlayerWithData(1)
			local p2, d2 = newPlayerWithData(2)
			env.players:AddPlayer(p1)
			env.players:AddPlayer(p2)
			RoundManager._dataManager = TestHelpers.newFakeDataManager({ [p1] = d1, [p2] = d2 })
			RoundManager.StartRound()

			local pushedPayloads = {}
			env.remoteDefinitions.RoundStateUpdate.FireAllClients = function(_self, payload)
				table.insert(pushedPayloads, payload)
			end

			RoundManager.RecordKill(p1, 10)
			RoundManager.RecordKill(p1, 5)
			RoundManager.RecordKill(p2, 20)
			RoundManager.EndRound("Timeout")

			local summaryPayload = pushedPayloads[#pushedPayloads]
			check.equal(summaryPayload.reason, "Timeout")
			check.equal(summaryPayload.summaryByPlayer[tostring(p1.UserId)].kills, 2)
			check.equal(summaryPayload.summaryByPlayer[tostring(p1.UserId)].xpEarned, 15)
			check.equal(summaryPayload.summaryByPlayer[tostring(p2.UserId)].kills, 1)
			check.equal(summaryPayload.summaryByPlayer[tostring(p2.UserId)].xpEarned, 20)

			env.players:RemovePlayerFromGame(p1)
			env.players:RemovePlayerFromGame(p2)
		end)

		test.case("a player who scored no kills this round still appears in the summary at zero", function()
			local p1, d1 = newPlayerWithData(1)
			local p2, d2 = newPlayerWithData(2)
			env.players:AddPlayer(p1)
			env.players:AddPlayer(p2)
			RoundManager._dataManager = TestHelpers.newFakeDataManager({ [p1] = d1, [p2] = d2 })
			RoundManager.StartRound()

			local pushedPayloads = {}
			env.remoteDefinitions.RoundStateUpdate.FireAllClients = function(_self, payload)
				table.insert(pushedPayloads, payload)
			end

			RoundManager.RecordKill(p1, 10)
			RoundManager.EndRound("Timeout")

			local summaryPayload = pushedPayloads[#pushedPayloads]
			check.equal(summaryPayload.summaryByPlayer[tostring(p2.UserId)].kills, 0)
			check.equal(summaryPayload.summaryByPlayer[tostring(p2.UserId)].xpEarned, 0)

			env.players:RemovePlayerFromGame(p1)
			env.players:RemovePlayerFromGame(p2)
		end)

		test.case("logs a RoundEnded analytics event with the end reason for every player", function()
			local p1, d1 = newPlayerWithData(1)
			env.players:AddPlayer(p1)
			RoundManager._dataManager = TestHelpers.newFakeDataManager({ [p1] = d1 })
			local analytics, calls = TestHelpers.newFakeAnalytics()
			RoundManager._analytics = analytics
			RoundManager.StartRound()

			RoundManager.EndRound("QuotaMet")

			check.equal(#calls.LogRoundEnded, 1)
			local loggedPlayers, loggedReason = calls.LogRoundEnded[1][1], calls.LogRoundEnded[1][2]
			check.equal(#loggedPlayers, 1)
			check.equal(loggedReason, "QuotaMet")

			env.players:RemovePlayerFromGame(p1)
			RoundManager._analytics = nil
		end)

		test.case("does not double-end an already-ended round", function()
			local p1, d1 = newPlayerWithData(1)
			env.players:AddPlayer(p1)
			RoundManager._dataManager = TestHelpers.newFakeDataManager({ [p1] = d1 })
			RoundManager.StartRound()

			RoundManager.EndRound("Timeout")
			-- Calling EndRound again while already "Ended" must be a no-op —
			-- guards the double-fire bug found in review (a kill landing at
			-- the same moment as the timeout check could otherwise re-enter
			-- EndRound and double-schedule the next round).
			RoundManager.EndRound("QuotaMet")

			check.equal(RoundManager.GetState().state, "Ended")

			env.players:RemovePlayerFromGame(p1)
		end)
	end)
end
