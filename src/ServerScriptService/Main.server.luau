-- Server entry point: requires and wires up the ServerScriptService modules.
-- Not listed explicitly in the-void-implementation-plan.md's module table
-- (which only lists the ModuleScripts), but every Rojo server tree needs one
-- concrete Script to actually run startup logic — this is that script.
--
-- A plain named Script (rather than init.server.luau usurping the
-- ServerScriptService folder itself) so the other modules are its siblings,
-- not its children — required via script.Parent accordingly. Rojo's
-- init.server.luau "usurp" mechanism doesn't apply cleanly when the folder
-- being usurped is a real Instance service (ServerScriptService can't be
-- reclassified as a Script), which produced a duplicate/orphaned instance
-- that never actually ran.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local RemoteDefinitions = require(ReplicatedStorage.Remotes.RemoteDefinitions)
local Analytics = require(script.Parent.Analytics)
local DataManager = require(script.Parent.DataManager)
local EnemySpawner = require(script.Parent.EnemySpawner)
local EnemyAI = require(script.Parent.EnemyAI)
local XPManager = require(script.Parent.XPManager)
local CombatManager = require(script.Parent.CombatManager)
local ShopManager = require(script.Parent.ShopManager)
local WeaponPickupManager = require(script.Parent.WeaponPickupManager)
local RoundManager = require(script.Parent.RoundManager)

DataManager.Init(Analytics)
XPManager.Init(DataManager)
RoundManager.Init(DataManager, Analytics)
CombatManager.Init(EnemySpawner, XPManager, DataManager, RoundManager)
EnemyAI.Init(EnemySpawner)
ShopManager.Init(DataManager, Analytics)
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
