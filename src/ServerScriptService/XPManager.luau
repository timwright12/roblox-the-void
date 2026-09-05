-- Awards XP on enemy kill, handles level-up math, fires client-facing updates.
-- Owns the xp/totalXp/level fields. See the-void-implementation-plan.md Section 3.
--
-- Phase 2: state moved from an in-memory table to DataManager's per-player
-- profile (the single owner of persistent player data) — XPManager is now a
-- pure logic layer over DataManager.GetData(player). See the-void-
-- implementation-plan.md Section 2.1 for the shared schema this reads/writes.

local XP_PER_LEVEL = 100

local XPManager = {}

--- Wires the module up against a live DataManager. Called once at server
--- startup, before any player joins.
function XPManager.Init(dataManager)
	XPManager._dataManager = dataManager
end

function XPManager.GetState(player: Player)
	local data = XPManager._dataManager.GetData(player)
	if not data then
		return nil
	end
	return { level = data.level, xp = data.xp, totalXp = data.totalXp }
end

function XPManager.AwardXP(player: Player, amount: number)
	assert(amount >= 0, "XP award amount must not be negative")

	local data = XPManager._dataManager.GetData(player)
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
