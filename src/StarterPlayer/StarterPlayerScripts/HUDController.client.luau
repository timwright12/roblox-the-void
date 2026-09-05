-- Displays XP/level/quota progress/round timer from server-pushed state. See
-- the-void-implementation-plan.md Section 3.
--
-- Phase 1: minimal XP/level display only, no styling, built entirely in code
-- (no StarterGui asset needed yet).
--
-- Phase 2: adds the head-thrower wind-up warning. This is the fairness-
-- critical client feedback for the telegraph (see product brief Section 8
-- risk) — without it, players have no way to react to the ~1s wind-up before
-- the instant-kill splash. No art/sound yet, just visible text.

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

local warningLabel = Instance.new("TextLabel")
warningLabel.Name = "HeadThrowWarning"
warningLabel.Size = UDim2.fromOffset(400, 48)
warningLabel.Position = UDim2.new(0.5, -200, 0.15, 0)
warningLabel.BackgroundTransparency = 0.3
warningLabel.BackgroundColor3 = Color3.new(0.6, 0, 0)
warningLabel.TextColor3 = Color3.new(1, 1, 1)
warningLabel.TextScaled = true
warningLabel.Text = ""
warningLabel.Visible = false
warningLabel.Parent = screenGui

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

RemoteDefinitions.ZombieHeadThrowTelegraph.OnClientEvent:Connect(function(payload)
	warningLabel.Text = "ZOMBIE THROWING ITS HEAD — GET BACK!"
	warningLabel.Visible = true

	task.delay(payload.windUpSeconds, function()
		warningLabel.Visible = false
	end)
end)
