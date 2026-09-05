-- Shared helpers used across multiple spec files: a fake DataManager builder,
-- and forcing a specific low-probability zombie weapon-variant roll (HeadThrow
-- is 1% per spawn — see EnemyTable.lua) without asserting on the RNG directly.

local TestHelpers = {}

--- Builds a fake DataManager whose GetData(player) looks up `dataByPlayer`
--- (a table keyed by player instance). Every server module under test only
--- calls DataManager.GetData(player) — this is the one fake needed to stand
--- in for it everywhere. Was previously duplicated with slightly different
--- shapes across 5 spec files; centralized here after a review found the
--- duplication.
function TestHelpers.newFakeDataManager(dataByPlayer)
	return {
		GetData = function(player)
			return dataByPlayer[player]
		end,
	}
end

--- Builds a fake Analytics module that records every call instead of
--- reaching real AnalyticsService (which doesn't exist under Lune, and per
--- Roblox's own docs never sends events outside a published game anyway —
--- see Analytics.luau's header comment). Returns the fake plus a `calls`
--- table (keyed by method name, e.g. calls.LogRoundStarted) that
--- accumulates each call's arguments as a sub-table, in call order.
function TestHelpers.newFakeAnalytics()
	local calls = {
		LogRoundStarted = {},
		LogRoundEnded = {},
		LogSessionEnded = {},
		LogWeaponPurchased = {},
	}

	local fake = {}
	for methodName in calls do
		fake[methodName] = function(...)
			table.insert(calls[methodName], { ... })
		end
	end

	return fake, calls
end

--- Spawns zombies via `enemySpawner` until one rolls the given variant, or
--- gives up after `maxAttempts` and returns nil. Default maxAttempts (5000)
-- gives a (1 - 0.99^5000) ≈ 100% chance of finding a 1%-probability variant —
-- effectively deterministic, unlike a smaller bound. A prior version of this
-- pattern used 500 attempts inline at each call site and was confirmed flaky
-- (~0.66% miss chance per call, observed failing in a 25-run repeated test)
-- before being centralized here with a safer bound.
function TestHelpers.spawnUntilVariant(enemySpawner, enemyTypeName: string, cframe, variantName: string, maxAttempts: number?)
	for _ = 1, maxAttempts or 5000 do
		local enemyId = enemySpawner.SpawnEnemy(enemyTypeName, cframe)
		local enemy = enemySpawner.GetEnemy(enemyId)
		if enemy.weaponVariant == variantName then
			return enemy
		end
	end
	return nil
end

return TestHelpers
