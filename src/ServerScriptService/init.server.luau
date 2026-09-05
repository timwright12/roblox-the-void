-- Server entry point: requires and wires up the ServerScriptService modules.
-- Not listed explicitly in the-void-implementation-plan.md's module table
-- (which only lists the ModuleScripts), but every Rojo server tree needs one
-- concrete Script to actually run startup logic — this is that script.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local RemoteDefinitions = require(ReplicatedStorage.Remotes.RemoteDefinitions)
local DataManager = require(script.DataManager)
local EnemySpawner = require(script.EnemySpawner)
local XPManager = require(script.XPManager)
local CombatManager = require(script.CombatManager)
local ShopManager = require(script.ShopManager)
local WeaponPickupManager = require(script.WeaponPickupManager)

XPManager.Init(DataManager)
CombatManager.Init(EnemySpawner, XPManager, DataManager)
ShopManager.Init(DataManager)
WeaponPickupManager.Init(DataManager)

RemoteDefinitions.RequestPlayerState.OnServerInvoke = function(player)
	return DataManager.GetData(player)
end

local function onPlayerAdded(player: Player)
	DataManager.LoadPlayer(player)
end

-- Handle players who joined before this script started running.
for _, player in Players:GetPlayers() do
	task.spawn(onPlayerAdded, player)
end

Players.PlayerAdded:Connect(onPlayerAdded)

Players.PlayerRemoving:Connect(function(player)
	CombatManager.RemovePlayer(player)
	DataManager.RemovePlayer(player)
end)

EnemySpawner.StartPhase2Spawns()
