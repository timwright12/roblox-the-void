-- A minimal stand-in for a Roblox Player. Implements exactly the surface the
-- game code under test actually reads: UserId, Character, CharacterAdded,
-- Parent (used by DataManager/WeaponPickupManager to detect whether a player
-- is still in the game), and :Kick() (DataManager calls this on profile load
-- failure — recorded rather than actually disconnecting anything, since
-- there's no real connection to disconnect under test).

local Signal = require("./Signal")

local FakePlayer = {}
FakePlayer.__index = FakePlayer

function FakePlayer.new(userId: number)
	return setmetatable({
		UserId = userId,
		Character = nil,
		CharacterAdded = Signal.new(),
		Parent = nil, -- tests set this to the FakePlayers service once "in game"
		_kickReason = nil,
	}, FakePlayer)
end

function FakePlayer:Kick(reason: string)
	self._kickReason = reason
end

--- Gives the player a character with a HumanoidRootPart and a Humanoid, and
--- fires CharacterAdded — matches the shape CombatManager/WeaponPickupManager
--- expect (character:FindFirstChild("HumanoidRootPart"), :FindFirstChildOfClass("Humanoid")).
function FakePlayer:SpawnCharacter(FakeModel, FakePart, FakeHumanoid)
	local character = FakeModel.new()
	local rootPart = FakePart.new()
	rootPart.Name = "HumanoidRootPart"
	character:AddChild(rootPart)

	local humanoid = FakeHumanoid.new()
	character:AddChild(humanoid)

	-- Match the real Instance:FindFirstChild(name) surface used by
	-- CombatManager.getPlayerRoot — searched by Name, not just by class.
	function character:FindFirstChild(name: string)
		for _, child in self.children do
			if child.Name == name then
				return child
			end
		end
		return nil
	end

	self.Character = character
	self.CharacterAdded:Fire(character)
	return character, rootPart, humanoid
end

return FakePlayer
