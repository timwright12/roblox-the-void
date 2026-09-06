-- Shared "find the nearest player within range of a point" logic, used by
-- both CombatManager (melee attack range, head-thrower splash) and EnemyAI
-- (chase aggro/release radius) — extracted here to avoid duplicating it once
-- EnemyAI needed the same lookup CombatManager already had.
--
-- Takes the Players service as a parameter rather than calling
-- game:GetService("Players") itself: confirmed by direct debugging that this
-- module (required directly by RobloxEnv.setup(), rather than through
-- RobloxEnv.requireModule()'s require-shim like every production module
-- under test) does not see the same `game` global the test harness sets up
-- for production code — a Lune module-loading quirk specific to this
-- require path. Every caller (CombatManager, EnemyAI) already has its own
-- reliable Players reference, so passing it in sidesteps the issue entirely
-- rather than working around Lune's global scoping.

local PlayerFinder = {}

--- Returns the player's HumanoidRootPart, or nil if they have no character
--- or it hasn't loaded yet.
function PlayerFinder.getPlayerRoot(player: Player): BasePart?
	local character = player.Character
	if not character then
		return nil
	end
	return character:FindFirstChild("HumanoidRootPart")
end

--- Finds the nearest player within `range` studs of `originPosition`, or nil
--- if none are in range. Skips players with no loaded character.
function PlayerFinder.findNearestPlayerInRange(players: { Player }, originPosition: Vector3, range: number): Player?
	local nearestPlayer = nil
	local nearestDistance = range

	for _, player in players do
		local playerRoot = PlayerFinder.getPlayerRoot(player)
		if playerRoot then
			local distance = (playerRoot.Position - originPosition).Magnitude
			if distance <= nearestDistance then
				nearestDistance = distance
				nearestPlayer = player
			end
		end
	end

	return nearestPlayer
end

return PlayerFinder
