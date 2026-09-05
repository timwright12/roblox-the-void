-- Awards XP on enemy kill, handles level-up math, fires client-facing updates.
-- Owns the xp/totalXp/level fields. See the-void-implementation-plan.md Section 3.
--
-- Phase 1: in-memory only (no DataStore persistence yet — that's Phase 2 via
-- DataManager). State is lost on server restart until then.

local XP_PER_LEVEL = 100

local XPManager = {}

local playerData = {}

local function defaultPlayerData()
	return {
		level = 1,
		xp = 0,
		totalXp = 0,
	}
end

function XPManager.InitPlayer(player: Player)
	playerData[player] = defaultPlayerData()
end

function XPManager.RemovePlayer(player: Player)
	playerData[player] = nil
end

function XPManager.GetState(player: Player)
	local data = playerData[player]
	if not data then
		return nil
	end
	return { level = data.level, xp = data.xp, totalXp = data.totalXp }
end

function XPManager.AwardXP(player: Player, amount: number)
	assert(amount >= 0, "XP award amount must not be negative")

	local data = playerData[player]
	if not data then
		return nil
	end

	data.xp += amount
	data.totalXp += amount

	while data.xp >= XP_PER_LEVEL do
		data.xp -= XP_PER_LEVEL
		data.level += 1
	end

	return { level = data.level, xp = data.xp, totalXp = data.totalXp }
end

return XPManager
