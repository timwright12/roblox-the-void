-- Shared helpers for tests that need to force a specific low-probability
-- zombie weapon-variant roll (HeadThrow is 1% per spawn — see EnemyTable.lua)
-- without asserting on the RNG directly.

local TestHelpers = {}

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
