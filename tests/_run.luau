-- Test entrypoint. Run with: lune run tests/_run.luau
-- See DevPackages/_Index/itsfrank_frktest@0.0.2/frktest/examples/_run.luau
-- for the pattern this follows.

local fs = require("@lune/fs")

-- Scans tests/ServerScriptService for *.spec.luau files and requires each
-- one, rather than a hardcoded list — a forgotten update to a hardcoded list
-- would silently skip a new spec file's tests entirely, with no error to
-- signal the gap.
--
-- fs.readDir needs a real filesystem path, which (unlike require) is
-- resolved relative to the process's cwd, not this script's location — so
-- this derives the spec directory from this script's own path
-- (debug.info(1, "s"), e.g. ".../tests/_run") rather than assuming the
-- process was launched from the repo root.
local function loadTests()
	local thisScriptPath = debug.info(1, "s")
	local testsDir = thisScriptPath:match("^(.*)/_run$")
	assert(testsDir, `could not determine tests/ directory from script path "{thisScriptPath}"`)

	local specDir = `{testsDir}/ServerScriptService`
	for _, fileName in fs.readDir(specDir) do
		local moduleName = fileName:match("^(.*)%.luau$")
		if moduleName then
			require(`./ServerScriptService/{moduleName}`)()
		end
	end
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
