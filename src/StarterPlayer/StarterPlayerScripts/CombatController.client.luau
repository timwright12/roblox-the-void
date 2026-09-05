-- Reads player input, sends attack intent to server, plays local hit
-- feedback/animation (cosmetic only — never trusted for damage). See
-- the-void-implementation-plan.md Section 3.
--
-- Phase 1 scope: click/tap targets the nearest live enemy within weapon
-- range (see the-void-implementation-plan.md Section 5, Phase 1). No local
-- hit feedback yet — that's a later polish pass.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local RemoteDefinitions = require(ReplicatedStorage.Remotes.RemoteDefinitions)
local WeaponTable = require(ReplicatedStorage.Data.WeaponTable)

local ATTACK_RANGE = WeaponTable.BaseSword.range
local ENEMY_TAG = "Enemy"

local localPlayer = Players.LocalPlayer

local function findNearestEnemyInRange(): number?
	local character = localPlayer.Character
	if not character then
		return nil
	end

	local root = character:FindFirstChild("HumanoidRootPart")
	if not root then
		return nil
	end

	local nearestEnemyId = nil
	local nearestDistance = ATTACK_RANGE

	for _, model in CollectionService:GetTagged(ENEMY_TAG) do
		local enemyRoot = model.PrimaryPart
		if enemyRoot then
			local distance = (root.Position - enemyRoot.Position).Magnitude
			if distance <= nearestDistance then
				nearestDistance = distance
				nearestEnemyId = model:GetAttribute("EnemyId")
			end
		end
	end

	return nearestEnemyId
end

local function attemptAttack()
	local enemyId = findNearestEnemyInRange()
	if enemyId then
		RemoteDefinitions.AttackIntent:FireServer(enemyId)
	end
end

UserInputService.InputBegan:Connect(function(input, gameProcessedEvent)
	if gameProcessedEvent then
		return
	end

	if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
		attemptAttack()
	end
end)
