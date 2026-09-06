-- Renders shop menu from WeaponTable, sends purchase requests, reflects
-- server-confirmed state (don't optimistically show a purchase as successful
-- before server confirms). See the-void-implementation-plan.md Section 3.
--
-- Minimal, no styling — a toggleable list of every WeaponTable entry with
-- buy/equip buttons. Opens via the "B" key or the always-visible corner
-- button below (shop menu is "accessible any time", per product brief
-- Section 5.4 — not gated to a physical location). The corner button exists
-- because "B" has no equivalent on touch-only devices (e.g. iPad) — without
-- it, the shop would be unreachable there.
--
-- Not unit-tested: client UI/input isn't exercisable in Lune's fake Roblox
-- environment (no rendering, no real Instance event wiring), same accepted
-- gap as EnemyAI's movement code. Verified manually in Studio.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local RemoteDefinitions = require(ReplicatedStorage.Remotes.RemoteDefinitions)
local WeaponTable = require(ReplicatedStorage.Data.WeaponTable)

local localPlayer = Players.LocalPlayer

local playerGui = localPlayer:WaitForChild("PlayerGui")

local screenGui = Instance.new("ScreenGui")
screenGui.Name = "ShopUI"
screenGui.ResetOnSpawn = false
screenGui.Enabled = false
screenGui.Parent = playerGui

-- Separate ScreenGui (not toggled) so the open/close button stays visible
-- even while the shop panel itself is hidden.
local toggleGui = Instance.new("ScreenGui")
toggleGui.Name = "ShopToggleUI"
toggleGui.ResetOnSpawn = false
toggleGui.Parent = playerGui

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

local function toggleShop()
	screenGui.Enabled = not screenGui.Enabled
end

UserInputService.InputBegan:Connect(function(input, gameProcessedEvent)
	if gameProcessedEvent then
		return
	end

	if input.KeyCode == Enum.KeyCode.B then
		toggleShop()
	end
end)

local toggleButton = Instance.new("TextButton")
toggleButton.Name = "ShopToggleButton"
toggleButton.Size = UDim2.fromOffset(80, 36)
toggleButton.Position = UDim2.new(1, -90, 0, 10)
toggleButton.Text = "Shop"
toggleButton.Parent = toggleGui

toggleButton.Activated:Connect(toggleShop)
