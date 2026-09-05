-- Single place declaring every RemoteEvent/RemoteFunction so client and server
-- reference the same Instances and avoid typo mismatches. The server creates
-- each Instance under this module's Remotes folder on first require; clients
-- require this same module and get the same Instances once they exist.
-- See the-void-implementation-plan.md Section 4 for the full network contract
-- (payload shapes, direction, purpose of each remote).

local RunService = game:GetService("RunService")

local REMOTE_EVENTS = {
	"AttackIntent",
	"EnemyKilled",
	"ZombieHeadThrowTelegraph",
	"EquipWeapon",
	"RoundStateUpdate",
	"PlayerDied",
}

local REMOTE_FUNCTIONS = {
	"PurchaseWeapon",
	"RequestPlayerState",
}

local remotesFolder = script.Parent:FindFirstChild("RemoteInstances")
if not remotesFolder then
	remotesFolder = Instance.new("Folder")
	remotesFolder.Name = "RemoteInstances"
	remotesFolder.Parent = script.Parent
end

local function getOrCreate(name: string, className: string): Instance
	local existing = remotesFolder:FindFirstChild(name)
	if existing then
		return existing
	end

	if RunService:IsClient() then
		return remotesFolder:WaitForChild(name)
	end

	local instance = Instance.new(className)
	instance.Name = name
	instance.Parent = remotesFolder
	return instance
end

local RemoteDefinitions = {}

for _, name in REMOTE_EVENTS do
	RemoteDefinitions[name] = getOrCreate(name, "RemoteEvent")
end

for _, name in REMOTE_FUNCTIONS do
	RemoteDefinitions[name] = getOrCreate(name, "RemoteFunction")
end

return RemoteDefinitions
