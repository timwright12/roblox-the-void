-- Sets up the fake Roblox global environment (game, workspace, Players,
-- Instance) that server modules need to load and run under Lune. Call
-- RobloxEnv.setup() once at the top of a test file, before requiring any
-- src/ServerScriptService module. Then use RobloxEnv.requireModule(path)
-- (not a plain require(...)) to load the production module under test.
--
-- Design note: server modules do `require(ReplicatedStorage.Data.EnemyTable)`
-- — real Roblox `require()` resolves an Instance reference to its
-- ModuleScript content. Lune's require() only resolves file paths, so fake
-- service properties (e.g. `ReplicatedStorage.Data.EnemyTable`) are wrapped
-- as `{ __fakeModuleData = <the real required table> }` markers.
--
-- Globally reassigning `require` for the whole test process was tried and
-- rejected: Lune's require() loses correct relative-path resolution for
-- nested requires (e.g. frktest's own internal `require("./test")`) once the
-- global `require` identifier has been reassigned anywhere in the process —
-- confirmed by direct experiment, not an assumption. Instead,
-- RobloxEnv.requireModule() shims `require` only for the synchronous
-- duration of loading one specific production module (whose own top-level
-- `require(ReplicatedStorage.X)` calls run once, synchronously, during that
-- window) and restores the real `require` immediately after — before
-- frktest or anything else runs. This is a test-only accommodation; no
-- production code changes.

local FakeInstance = require("./FakeInstance")
local FakePlayers = require("./FakePlayers")

local realRequire = require

local function fakeModule(data)
	return { __fakeModuleData = data }
end

local function shimmedRequire(target)
	if type(target) == "table" and target.__fakeModuleData ~= nil then
		return target.__fakeModuleData
	end
	return realRequire(target)
end

local RobloxEnv = {}

--- Wraps a value (typically a fake service module, e.g. a fake ProfileStore)
--- so that a production module's `require(ReplicatedStorage.X)` /
--- `require(ServerScriptService.ServerPackages.Y)` call resolves to it. See
--- the design note above for why this marker+shim exists instead of a real
--- Instance/ModuleScript.
RobloxEnv.fakeModule = fakeModule

--- Requires a production module (by real Lune path, e.g.
--- "../../src/ServerScriptService/EnemySpawner") with the fake-module-marker
--- shim active only for this one call. See the design note above for why
--- this can't just be a permanent global reassignment.
function RobloxEnv.requireModule(path: string)
	require = shimmedRequire :: any
	local ok, result = pcall(realRequire, path)
	require = realRequire :: any

	if not ok then
		error(result, 0)
	end
	return result
end

--- Sets up all fake Roblox globals. Returns a handle with references to the
--- fakes a test will want direct access to (players service, etc).
function RobloxEnv.setup()
	local roblox = realRequire("@lune/roblox")
	Instance = FakeInstance :: any
	task = realRequire("@lune/task") :: any

	-- Real Roblox datatypes: @lune/roblox implements these as real value
	-- types (math, equality, etc. all behave correctly) — no fake needed,
	-- unlike Instance/Humanoid which need simulated engine behavior.
	Vector3 = roblox.Vector3 :: any
	CFrame = roblox.CFrame :: any
	Color3 = roblox.Color3 :: any
	UDim2 = roblox.UDim2 :: any
	Enum = roblox.Enum :: any

	local enemyTable = realRequire("../../src/ReplicatedStorage/Data/EnemyTable")
	local weaponTable = realRequire("../../src/ReplicatedStorage/Data/WeaponTable")
	local playerFinder = realRequire("../../src/ReplicatedStorage/Modules/PlayerFinder")

	-- RemoteDefinitions normally creates real RemoteEvent/RemoteFunction
	-- Instances on require. Server-side unit tests call module functions
	-- directly (e.g. CombatManager.HandleAttackIntent) rather than going
	-- through remotes, so a fake with no-op Fire/Invoke methods is enough —
	-- the handful of places that do fire remotes (e.g. EnemyKilled) just
	-- need the call to not error.
	local function fakeRemoteEvent()
		return {
			FireClient = function() end,
			FireAllClients = function() end,
			OnServerEvent = { Connect = function() end },
		}
	end
	local function fakeRemoteFunction()
		return {
			OnServerInvoke = nil,
		}
	end
	local remoteDefinitions = {
		AttackIntent = fakeRemoteEvent(),
		EnemyKilled = fakeRemoteEvent(),
		ZombieHeadThrowTelegraph = fakeRemoteEvent(),
		PurchaseWeapon = fakeRemoteFunction(),
		EquipWeapon = fakeRemoteEvent(),
		RoundStateUpdate = fakeRemoteEvent(),
		PlayerDied = fakeRemoteEvent(),
		RequestPlayerState = fakeRemoteFunction(),
	}

	local players = FakePlayers.new()

	local replicatedStorage = {
		Data = {
			EnemyTable = fakeModule(enemyTable),
			WeaponTable = fakeModule(weaponTable),
		},
		Remotes = {
			RemoteDefinitions = fakeModule(remoteDefinitions),
		},
		Modules = {
			PlayerFinder = fakeModule(playerFinder),
		},
		-- EnemyModels is deliberately absent by default: EnemySpawner falls
		-- back to a placeholder model when it's not there (see
		-- EnemySpawner.luau's buildEnemyModel), which is what every existing
		-- test relies on. A test that needs a real model sets
		-- env.replicatedStorage.EnemyModels itself (see EnemySpawner.spec.luau).
		FindFirstChild = function(self, name: string)
			return self[name]
		end,
	}

	local serverPackages = {
		-- Tests that need DataManager provide their own fake ProfileStore
		-- here rather than a shared default, since ProfileStore's session
		-- semantics are central to what DataManager tests actually verify.
		ProfileStore = nil,
	}

	local services = {
		Players = players,
		ReplicatedStorage = replicatedStorage,
		RunService = { IsStudio = function() return false end },
		ServerScriptService = { ServerPackages = serverPackages },
		CollectionService = {
			_tags = {},
			AddTag = function(self, instance, tag)
				self._tags[tag] = self._tags[tag] or {}
				table.insert(self._tags[tag], instance)
			end,
			GetTagged = function(self, tag)
				return self._tags[tag] or {}
			end,
		},
	}

	game = {
		GetService = function(_, name)
			local service = services[name]
			if not service then
				error(`RobloxEnv: no fake registered for service "{name}"`)
			end
			return service
		end,
	} :: any

	-- Raycast defaults to "hit nothing" (no terrain in the fake environment)
	-- — EnemySpawner's placeOnGround falls back to the original spawnCFrame
	-- unchanged in that case, which is what every existing spawn test
	-- relies on. A test that needs a real ground hit sets
	-- workspace.Raycast itself (see EnemySpawner.spec.luau).
	workspace = {
		Name = "Workspace",
		Raycast = function()
			return nil
		end,
	} :: any

	return {
		players = players,
		replicatedStorage = replicatedStorage,
		serverPackages = serverPackages,
		remoteDefinitions = remoteDefinitions,
	}
end

return RobloxEnv
