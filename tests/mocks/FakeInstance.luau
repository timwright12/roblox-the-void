-- Global Instance.new(className) dispatcher for tests. Real Roblox instances
-- automatically register themselves as a child of whatever they're Parented
-- to; these fakes replicate just that one piece of "magic" via __newindex on
-- the Parent key; every other property is a plain field access.
--
-- See FakeModel/FakePart/FakeHumanoid for what's actually implemented on each
-- fake — deliberately just the surface the game code under test calls.

local FakeModel = require("./FakeModel")
local FakePart = require("./FakePart")
local FakeHumanoid = require("./FakeHumanoid")

local function withParentTracking(fake)
	local raw = {}
	local proxy = setmetatable({}, {
		__index = function(_, key)
			if key == "Parent" then
				return raw.Parent
			end
			return fake[key]
		end,
		__newindex = function(_, key, value)
			if key == "Parent" then
				raw.Parent = value
				if value ~= nil and value.AddChild then
					value:AddChild(fake)
				end
			else
				fake[key] = value
			end
		end,
	})
	return proxy
end

local Instance = {}

function Instance.new(className: string)
	if className == "Model" then
		return withParentTracking(FakeModel.new())
	elseif className == "Part" then
		return withParentTracking(FakePart.new())
	elseif className == "Humanoid" then
		return withParentTracking(FakeHumanoid.new())
	end

	error(`FakeInstance: unsupported className "{className}" — add a fake for it in tests/mocks`)
end

return Instance
