-- A minimal stand-in for a Roblox Model. Implements exactly the surface the
-- game code under test actually calls: Name, PrimaryPart, SetPrimaryPartCFrame
-- (records the CFrame and updates PrimaryPart.Position to match, since that's
-- all the real engine call is used for here), SetAttribute/GetAttribute,
-- FindFirstChildOfClass/FindFirstChild (search children added via the
-- `children` field, by class or by Name respectively), Destroy (sets Parent
-- to nil, matching what CombatManager checks to detect a zombie destroyed mid
-- wind-up), and Parent.

local FakeModel = {}
FakeModel.__index = FakeModel

function FakeModel.new()
	return setmetatable({
		Name = "Model",
		PrimaryPart = nil,
		Parent = nil,
		children = {},
		_attributes = {},
	}, FakeModel)
end

function FakeModel:AddChild(instance)
	table.insert(self.children, instance)
end

function FakeModel:SetPrimaryPartCFrame(cframe)
	if self.PrimaryPart then
		self.PrimaryPart.Position = cframe.Position
	end
end

function FakeModel:SetAttribute(name: string, value)
	self._attributes[name] = value
end

function FakeModel:GetAttribute(name: string)
	return self._attributes[name]
end

function FakeModel:FindFirstChildOfClass(className: string)
	for _, child in self.children do
		if child._className == className then
			return child
		end
	end
	return nil
end

function FakeModel:FindFirstChild(name: string)
	for _, child in self.children do
		if child.Name == name then
			return child
		end
	end
	return nil
end

function FakeModel:Destroy()
	self.Parent = nil
end

return FakeModel
