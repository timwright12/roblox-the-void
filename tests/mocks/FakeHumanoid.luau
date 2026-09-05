-- A minimal stand-in for Roblox's Humanoid. @lune/roblox's Instance.new
-- creates real Instances but does NOT simulate Humanoid-specific behavior
-- (TakeDamage, Died firing on health reaching 0) — it's a generic property
-- bag. This fake implements exactly the surface the game code under test
-- actually uses: MaxHealth, Health, WalkSpeed, Parent, :TakeDamage(), .Died.

local Signal = require("./Signal")

local FakeHumanoid = {}
FakeHumanoid.__index = FakeHumanoid

function FakeHumanoid.new()
	return setmetatable({
		_className = "Humanoid",
		MaxHealth = 100,
		Health = 100,
		WalkSpeed = 16,
		Parent = nil,
		Died = Signal.new(),
		_hasDied = false,
	}, FakeHumanoid)
end

function FakeHumanoid:TakeDamage(amount: number)
	if self._hasDied then
		return
	end

	self.Health = math.max(0, self.Health - amount)

	if self.Health <= 0 then
		self._hasDied = true
		self.Died:Fire()
	end
end

return FakeHumanoid
