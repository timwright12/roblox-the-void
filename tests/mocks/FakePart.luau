-- A minimal stand-in for a Roblox Part/BasePart. Implements exactly the
-- properties the game code under test actually reads/writes: Name, Size,
-- Anchored, CanCollide, Position, Parent, plus a Touched signal.

local Signal = require("./Signal")

local FakePart = {}
FakePart.__index = FakePart

function FakePart.new()
	return setmetatable({
		_className = "Part",
		Name = "Part",
		Size = nil,
		Anchored = false,
		CanCollide = true,
		Position = nil,
		Parent = nil,
		Touched = Signal.new(),
	}, FakePart)
end

return FakePart
