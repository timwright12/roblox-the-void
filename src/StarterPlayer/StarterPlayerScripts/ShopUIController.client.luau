-- Renders shop menu from WeaponTable, sends purchase requests, reflects
-- server-confirmed state (don't optimistically show a purchase as successful
-- before server confirms). See the-void-implementation-plan.md Section 3.
--
-- Phase 2 scope: minimal, no styling — a toggleable list of the 3 starter
-- weapons with buy/equip buttons. Opens via the "B" key (shop menu is
-- "accessible any time", per product brief Section 5.4 — not gated to a
-- physical location).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local RemoteDefinitions = require(ReplicatedStorage.Remotes.RemoteDefinitions)
local WeaponTable = require(ReplicatedStorage.Data.WeaponTable)

local localPlayer = Players.LocalPlayer

local screenGui = Instance.new("ScreenGui")
screenGui.Name = "ShopUI"
screenGui.ResetOnSpawn = false
screenGui.Enabled = false
screenGui.Parent = localPlayer:WaitForChild("PlayerGui")

local frame = Instance.new("Frame")
frame.Name = "ShopFrame"
frame.Size = UDim2.fromOffset(280, 220)
frame.Position = UDim2.fromScale(0.5, 0.5)
frame.AnchorPoint = Vector2.new(0.5, 0.5)
frame.BackgroundTransparency = 0.1
frame.Parent = screenGui

local layout = Instance.new("UIListLayout")
layout.Padding = UDim.new(0, 4)
layout.Parent = frame

local statusLabel = Instance.new("TextLabel")
statusLabel.Size = UDim2.new(1, 0, 0, 24)
statusLabel.Text = ""
statusLabel.Parent = frame

local ownedWeapons = {}

local function isOwned(weaponId: string): boolean
	return table.find(ownedWeapons, weaponId) ~= nil
end

local weaponRows = {}

local function refreshRows()
	for weaponId, row in weaponRows do
		row.buyButton.Visible = not isOwned(weaponId)
		row.equipButton.Visible = isOwned(weaponId)
	end
end

local function buildRow(weaponId: string, weaponStats)
	local row = Instance.new("Frame")
	row.Name = weaponId
	row.Size = UDim2.new(1, 0, 0, 32)
	row.BackgroundTransparency = 1
	row.Parent = frame

	local label = Instance.new("TextLabel")
	label.Size = UDim2.new(0.6, 0, 1, 0)
	label.Text = `{weaponStats.name} ({weaponStats.cost} XP)`
	label.Parent = row

	local buyButton = Instance.new("TextButton")
	buyButton.Size = UDim2.new(0.2, 0, 1, 0)
	buyButton.Position = UDim2.new(0.6, 0, 0, 0)
	buyButton.Text = "Buy"
	buyButton.Parent = row

	local equipButton = Instance.new("TextButton")
	equipButton.Size = UDim2.new(0.2, 0, 1, 0)
	equipButton.Position = UDim2.new(0.8, 0, 0, 0)
	equipButton.Text = "Equip"
	equipButton.Parent = row

	buyButton.Activated:Connect(function()
		local result = RemoteDefinitions.PurchaseWeapon:InvokeServer(weaponId)
		if result.success then
			ownedWeapons = result.ownedWeapons
			statusLabel.Text = `Purchased {weaponStats.name}!`
			refreshRows()
		else
			statusLabel.Text = `Purchase failed: {result.reason}`
		end
	end)

	equipButton.Activated:Connect(function()
		RemoteDefinitions.EquipWeapon:FireServer(weaponId)
		statusLabel.Text = `Equipped {weaponStats.name}.`
	end)

	weaponRows[weaponId] = { buyButton = buyButton, equipButton = equipButton }
end

for weaponId, weaponStats in WeaponTable do
	buildRow(weaponId, weaponStats)
end

local initialState = RemoteDefinitions.RequestPlayerState:InvokeServer()
if initialState and initialState.ownedWeapons then
	ownedWeapons = initialState.ownedWeapons
end
refreshRows()

UserInputService.InputBegan:Connect(function(input, gameProcessedEvent)
	if gameProcessedEvent then
		return
	end

	if input.KeyCode == Enum.KeyCode.B then
		screenGui.Enabled = not screenGui.Enabled
	end
end)
