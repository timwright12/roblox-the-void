-- Round lifecycle: lobby -> start -> track quota progress -> end (win or
-- timeout) -> return to lobby. Calculates per-player quota scaled to team size
-- at round start. Quota counts kills of any enemy type (robot or zombie).
-- See the-void-implementation-plan.md Section 3.

local RoundManager = {}

return RoundManager
