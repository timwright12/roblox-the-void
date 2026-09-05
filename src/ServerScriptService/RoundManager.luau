-- Round lifecycle: lobby -> start -> track quota progress -> end (win or
-- timeout) -> return to lobby. Calculates per-player quota scaled to team size
-- at round start. Quota counts kills of any enemy type (robot or zombie).
-- See the-void-implementation-plan.md Section 3.
--
-- Phase 3: quotaPerPlayer = 10 and the backstop timer = 10 minutes are
-- starting placeholders (confirmed with design owner) — real tuning happens
-- in Phase 5 against actual playtest data, per Section 6.
--
-- End-of-round summary (kills, XP earned this round, quota result) is sent
-- by extending RoundStateUpdate's payload with summary fields only present
-- when state == "Ended", rather than a separate remote — see the-void-
-- implementation-plan.md Section 4 for the documented addition.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local RemoteDefinitions = require(ReplicatedStorage.Remotes.RemoteDefinitions)

local QUOTA_PER_PLAYER = 10
local ROUND_TIMER_SECONDS = 10 * 60
local STATE_PUSH_INTERVAL_SECONDS = 1
local LOBBY_TO_ROUND_DELAY_SECONDS = 10
local END_SUMMARY_DISPLAY_SECONDS = 10

local RoundManager = {}

local state = "Lobby" -- "Lobby" | "Active" | "Ended"
local quotaTarget = 0
local quotaProgress = 0
local roundEndsAt = 0
local roundStartedAt = 0

-- Per-round (not lifetime) tracking for the end-of-round summary. Reset on
-- every StartRound; intentionally not persisted — this data has no meaning
-- once the round ends.
local roundKillsByPlayer = {}
local roundXpByPlayer = {}

local function buildStatePayload(extra: { [string]: any }?)
	local timeRemaining = state == "Active" and math.max(0, roundEndsAt - os.clock()) or 0

	local payload = {
		state = state,
		quotaTarget = quotaTarget,
		quotaProgress = quotaProgress,
		timeRemaining = timeRemaining,
	}

	if extra then
		for key, value in extra do
			payload[key] = value
		end
	end

	return payload
end

local function pushStateToAll(extra: { [string]: any }?)
	RemoteDefinitions.RoundStateUpdate:FireAllClients(buildStatePayload(extra))
end

--- Wires the module up against a live DataManager (for per-player round/kill
--- stats) and Analytics (for round start/end events), and starts the
--- lobby-to-round scheduling loop. Called once at server startup.
function RoundManager.Init(dataManager, analytics)
	RoundManager._dataManager = dataManager
	RoundManager._analytics = analytics

	task.spawn(function()
		while true do
			task.wait(STATE_PUSH_INTERVAL_SECONDS)
			if state == "Active" and os.clock() >= roundEndsAt then
				RoundManager.EndRound("Timeout")
			end
			if state ~= "Ended" then
				pushStateToAll()
			end
		end
	end)

	RoundManager.ScheduleNextRound()
end

--- Starts a round: calculates quota from current player count, resets
--- progress, and begins the backstop timer.
function RoundManager.StartRound()
	local playerCount = #Players:GetPlayers()
	quotaTarget = QUOTA_PER_PLAYER * math.max(playerCount, 1)
	quotaProgress = 0
	roundStartedAt = os.clock()
	roundEndsAt = roundStartedAt + ROUND_TIMER_SECONDS
	state = "Active"
	roundKillsByPlayer = {}
	roundXpByPlayer = {}

	for _, player in Players:GetPlayers() do
		local data = RoundManager._dataManager.GetData(player)
		if data then
			data.stats.roundsPlayed += 1
		end
	end

	if RoundManager._analytics then
		RoundManager._analytics.LogRoundStarted(Players:GetPlayers())
	end

	pushStateToAll()
end

--- Records one enemy kill toward the round's quota. Called directly by
--- CombatManager on every confirmed kill (see the-void-implementation-plan.md
--- Section 3 module responsibilities — modules call each other directly
--- rather than through an event bus, consistent with the rest of this
--- codebase).
function RoundManager.RecordKill(player: Player, xpAwarded: number)
	-- Lifetime stat: counts regardless of round state, since a kill happened
	-- either way (e.g. during the Lobby countdown before a round starts).
	local data = RoundManager._dataManager.GetData(player)
	if data then
		data.stats.enemiesKilled += 1
	end

	if state ~= "Active" then
		return
	end

	quotaProgress += 1
	roundKillsByPlayer[player] = (roundKillsByPlayer[player] or 0) + 1
	roundXpByPlayer[player] = (roundXpByPlayer[player] or 0) + xpAwarded

	if quotaProgress >= quotaTarget then
		RoundManager.EndRound("QuotaMet")
	end
end

--- Ends the current round, pushes the final state plus summary fields
--- (reason, per-player kills/XP this round), and schedules the next
--- lobby-to-round transition. `reason` is "QuotaMet" or "Timeout".
function RoundManager.EndRound(reason: string)
	if state ~= "Active" then
		return
	end
	state = "Ended"

	local summaryByPlayer = {}
	for _, player in Players:GetPlayers() do
		summaryByPlayer[tostring(player.UserId)] = {
			kills = roundKillsByPlayer[player] or 0,
			xpEarned = roundXpByPlayer[player] or 0,
		}
	end

	pushStateToAll({
		reason = reason,
		summaryByPlayer = summaryByPlayer,
	})

	if RoundManager._analytics then
		RoundManager._analytics.LogRoundEnded(Players:GetPlayers(), reason, os.clock() - roundStartedAt)
	end

	-- Hold the "Ended" state visible for a bit before returning to lobby, so
	-- the summary isn't immediately overwritten by the next state push.
	task.delay(END_SUMMARY_DISPLAY_SECONDS, function()
		RoundManager.ScheduleNextRound()
	end)
end

--- Returns to lobby state after a short delay, then starts the next round.
function RoundManager.ScheduleNextRound()
	state = "Lobby"
	quotaProgress = 0
	pushStateToAll()

	task.delay(LOBBY_TO_ROUND_DELAY_SECONDS, function()
		RoundManager.StartRound()
	end)
end

function RoundManager.GetState()
	return buildStatePayload()
end

return RoundManager
