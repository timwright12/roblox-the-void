-- Server entry point: requires and wires up the ServerScriptService modules.
-- Not listed explicitly in the-void-implementation-plan.md's module table
-- (which only lists the ModuleScripts), but every Rojo server tree needs one
-- concrete Script to actually run startup logic — this is that script.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local RemoteDefinitions = require(ReplicatedStorage.Remotes.RemoteDefinitions)
local EnemySpawner = require(script.EnemySpawner)
local XPManager = require(script.XPManager)
local CombatManager = require(script.CombatManager)

CombatManager.Init(EnemySpawner, XPManager)

RemoteDefinitions.RequestPlayerState.OnServerInvoke = function(player)
	return XPManager.GetState(player)
end

Players.PlayerAdded:Connect(function(player)
	XPManager.InitPlayer(player)
end)

Players.PlayerRemoving:Connect(function(player)
	XPManager.RemovePlayer(player)
end)

EnemySpawner.StartPhase1Spawns()
