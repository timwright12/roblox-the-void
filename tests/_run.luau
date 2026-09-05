-- Test entrypoint. Run with: lune run tests/_run.luau
-- See DevPackages/_Index/itsfrank_frktest@0.0.2/frktest/examples/_run.luau
-- for the pattern this follows.

local function loadTests()
	require("./ServerScriptService/XPManager.spec")()
	require("./ServerScriptService/ShopManager.spec")()
	require("./ServerScriptService/RoundManager.spec")()
	require("./ServerScriptService/EnemySpawner.spec")()
	require("./ServerScriptService/CombatManager.spec")()
	require("./ServerScriptService/WeaponPickupManager.spec")()
	require("./ServerScriptService/DataManager.spec")()
end

local function runTests()
	local frktest = require("@frktest/frktest")
	local lune_console_reporter = require("@frktest/reporters/lune_console_reporter")

	lune_console_reporter.init()
	local success = frktest.run()

	-- Force-exit rather than letting the process wait for any pending
	-- task.delay/task.spawn scheduled by production code under test (e.g.
	-- RoundManager's end-of-round summary delay) — those are meant to run
	-- for the lifetime of a real Roblox server, not to gate a test process
	-- exiting. Without this, the suite gets slower every time a test
	-- exercises a code path that schedules a delayed callback.
	require("@lune/process").exit(success and 0 or 1)
end

loadTests()
runTests()
