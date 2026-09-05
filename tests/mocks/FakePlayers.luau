-- A minimal stand-in for the Players service. Implements exactly the surface
-- the game code under test actually calls: GetPlayers, GetPlayerFromCharacter,
-- PlayerAdded, PlayerRemoving.

local Signal = require("./Signal")

local FakePlayers = {}
FakePlayers.__index = FakePlayers

function FakePlayers.new()
	return setmetatable({
		_players = {},
		PlayerAdded = Signal.new(),
		PlayerRemoving = Signal.new(),
	}, FakePlayers)
end

--- Adds a player to the service (marking them "in game" via Parent) and
--- fires PlayerAdded. Test helper — not a real Players method name.
function FakePlayers:AddPlayer(player)
	player.Parent = self
	table.insert(self._players, player)
	self.PlayerAdded:Fire(player)
end

--- Removes a player from the service and fires PlayerRemoving. Test helper.
function FakePlayers:RemovePlayerFromGame(player)
	local index = table.find(self._players, player)
	if index then
		table.remove(self._players, index)
	end
	player.Parent = nil
	self.PlayerRemoving:Fire(player)
end

function FakePlayers:GetPlayers()
	return table.clone(self._players)
end

--- Test helper: clears all players without firing PlayerRemoving for each
--- (tests generally don't care about that signal firing during cleanup, just
--- that leftover players from a previous test case don't leak in).
function FakePlayers:Reset()
	self._players = {}
end

function FakePlayers:GetPlayerFromCharacter(character)
	for _, player in self._players do
		if player.Character == character then
			return player
		end
	end
	return nil
end

return FakePlayers
