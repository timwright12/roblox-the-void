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
--
-- Phase 3: adds quota progress/round timer display and the end-of-round
-- summary (kills, XP earned this round, quota result) — see RoundStateUpdate
-- in the-void-implementation-plan.md Section 4.

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

local roundLabel = Instance.new("TextLabel")
roundLabel.Name = "RoundLabel"
roundLabel.Size = UDim2.fromOffset(260, 32)
roundLabel.Position = UDim2.fromOffset(16, 56)
roundLabel.BackgroundTransparency = 0.4
roundLabel.TextXAlignment = Enum.TextXAlignment.Left
roundLabel.Parent = screenGui

local summaryFrame = Instance.new("Frame")
summaryFrame.Name = "RoundSummary"
summaryFrame.Size = UDim2.fromOffset(320, 160)
summaryFrame.Position = UDim2.fromScale(0.5, 0.5)
summaryFrame.AnchorPoint = Vector2.new(0.5, 0.5)
summaryFrame.BackgroundTransparency = 0.1
summaryFrame.Visible = false
summaryFrame.Parent = screenGui

local summaryLabel = Instance.new("TextLabel")
summaryLabel.Size = UDim2.fromScale(1, 1)
summaryLabel.TextWrapped = true
summaryLabel.Parent = summaryFrame

local function render(level: number, xp: number)
	label.Text = `Level {level}  ({xp}/100 XP)`
end

local function formatTime(seconds: number): string
	local minutes = math.floor(seconds / 60)
	local remainderSeconds = math.floor(seconds % 60)
	return string.format("%d:%02d", minutes, remainderSeconds)
end

local function renderRoundState(payload)
	if payload.state == "Lobby" then
		roundLabel.Text = "Waiting for next round..."
	elseif payload.state == "Active" then
		roundLabel.Text = `Quota: {payload.quotaProgress}/{payload.quotaTarget}  Time: {formatTime(payload.timeRemaining)}`
	elseif payload.state == "Ended" then
		roundLabel.Text = payload.reason == "QuotaMet" and "Round complete!" or "Round timed out."
	end

	if payload.state == "Ended" and payload.summaryByPlayer then
		local myKey = tostring(localPlayer.UserId)
		local mySummary = payload.summaryByPlayer[myKey]
		if mySummary then
			summaryLabel.Text = `Round Result: {payload.reason}\nYour kills: {mySummary.kills}\nYour XP earned: {mySummary.xpEarned}`
			summaryFrame.Visible = true
		end
	else
		summaryFrame.Visible = false
	end
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

RemoteDefinitions.RoundStateUpdate.OnClientEvent:Connect(renderRoundState)
