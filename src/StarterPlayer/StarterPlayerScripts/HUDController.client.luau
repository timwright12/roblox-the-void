-- Displays XP/level/quota progress/round timer from server-pushed state. See
-- the-void-implementation-plan.md Section 3.
--
-- Phase 1 scope: minimal XP/level display only, no styling, built entirely
-- in code (no StarterGui asset needed yet).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local RemoteDefinitions = require(ReplicatedStorage.Remotes.RemoteDefinitions)

local localPlayer = Players.LocalPlayer

local screenGui = Instance.new("ScreenGui")
screenGui.Name = "HUD"
screenGui.ResetOnSpawn = false
screenGui.Parent = localPlayer:WaitForChild("PlayerGui")

local label = Instance.new("TextLabel")
label.Name = "XPLevelLabel"
label.Size = UDim2.fromOffset(220, 32)
label.Position = UDim2.fromOffset(16, 16)
label.BackgroundTransparency = 0.4
label.TextXAlignment = Enum.TextXAlignment.Left
label.Parent = screenGui

local function render(level: number, xp: number)
	label.Text = `Level {level}  ({xp}/100 XP)`
end

render(1, 0)

local initialState = RemoteDefinitions.RequestPlayerState:InvokeServer()
if initialState then
	render(initialState.level, initialState.xp)
end

RemoteDefinitions.EnemyKilled.OnClientEvent:Connect(function(payload)
	render(payload.newLevel, payload.newXp)
end)
