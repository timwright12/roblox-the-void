-- Load/save player data via DataStore. Single owner of DataStore access —
-- nothing else touches DataStore directly. See the-void-implementation-plan.md
-- Section 3 for full responsibility and Section 2.1 for the player data schema.
--
-- Phase 2: real persistence via ProfileStore (github.com/MadStudioRoblox/ProfileStore),
-- vendored via Wally. ProfileStore handles session locking, auto-save, and
-- retry internally, which is why this module doesn't hand-roll its own
-- UpdateAsync/backoff logic per the original plan wording — see the
-- conversation record for why ProfileStore was chosen over hand-rolling.

local RunService = game:GetService("RunService")
local Players = game:GetService("Players")
local ServerScriptService = game:GetService("ServerScriptService")

local ProfileStore = require(ServerScriptService.ServerPackages.ProfileStore)

local PROFILE_TEMPLATE = {
	level = 1,
	xp = 0,
	totalXp = 0,
	ownedWeapons = { "BaseSword" },
	equippedWeapon = "BaseSword",
	stats = {
		roundsPlayed = 0,
		enemiesKilled = 0,
		deaths = 0,
	},
	dataVersion = 1,
}

local DataManager = {}

local PlayerStore = ProfileStore.New("PlayerStore", PROFILE_TEMPLATE)
if RunService:IsStudio() then
	-- Avoid writing to live DataStore keys while iterating in Studio.
	-- See the ProfileStore.Mock notice in its API docs.
	PlayerStore = PlayerStore.Mock
end

local profiles = {}
local sessionStartedAt = {}

--- Wires the module up against Analytics (for session-length events).
--- Called once at server startup.
function DataManager.Init(analytics)
	DataManager._analytics = analytics
end

function DataManager.LoadPlayer(player: Player)
	local profile = PlayerStore:StartSessionAsync(`{player.UserId}`, {
		Cancel = function()
			return player.Parent ~= Players
		end,
	})

	if profile == nil then
		player:Kick("Profile load fail - please rejoin")
		return
	end

	profile:AddUserId(player.UserId)
	profile:Reconcile()

	profile.OnSessionEnd:Connect(function()
		profiles[player] = nil
		player:Kick("Profile session end - please rejoin")
	end)

	if player.Parent ~= Players then
		-- Player left before the session finished starting.
		profile:EndSession()
		return
	end

	profiles[player] = profile
	sessionStartedAt[player] = os.clock()
end

function DataManager.RemovePlayer(player: Player)
	local profile = profiles[player]
	if profile then
		profile:EndSession()
		profiles[player] = nil

		if DataManager._analytics and sessionStartedAt[player] then
			DataManager._analytics.LogSessionEnded(player, os.clock() - sessionStartedAt[player])
		end
		sessionStartedAt[player] = nil
	end
end

--- Returns the live, mutable Data table for a player, or nil if their profile
--- isn't loaded (not yet loaded, or already ended).
function DataManager.GetData(player: Player)
	local profile = profiles[player]
	if not profile then
		return nil
	end
	return profile.Data
end

return DataManager
