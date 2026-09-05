-- Thin wrapper around Roblox's AnalyticsService, centralizing event
-- names/shapes for the events the-void-implementation-plan.md Section 6
-- calls for: round start/end, completion vs timeout, session length, and
-- per-weapon purchase frequency. See
-- https://create.roblox.com/docs/production/analytics/custom-events and
-- .../economy-events for the underlying API this wraps.
--
-- AnalyticsService "Events can only be sent from the server and in
-- published games. Events can't be sent from the client or Studio" (per
-- Roblox's own docs) — so none of this is verifiable locally; it can only
-- be confirmed once actually published (Section 8) via the Creator
-- Dashboard's Analytics tab, which is why this is a thin, easily-swappable
-- wrapper rather than logic worth unit-testing for behavior beyond "does it
-- call through with the right arguments".

local AnalyticsService = game:GetService("AnalyticsService")

local Analytics = {}

--- Fires a "RoundStarted" counter event for every player in the round, so
--- round frequency can be tracked per-player over time.
function Analytics.LogRoundStarted(players: { Player })
	for _, player in players do
		AnalyticsService:LogCustomEvent(player, "RoundStarted")
	end
end

--- Fires "RoundEnded" (a value event, value = round duration in seconds)
--- plus a "RoundCompletion" event whose value is 1 for QuotaMet and 0 for
--- Timeout, letting the completion-vs-timeout rate be computed as an
--- average value in the dashboard without needing a custom field.
function Analytics.LogRoundEnded(players: { Player }, reason: string, durationSeconds: number)
	local completionValue = if reason == "QuotaMet" then 1 else 0
	for _, player in players do
		AnalyticsService:LogCustomEvent(player, "RoundEnded", durationSeconds)
		AnalyticsService:LogCustomEvent(player, "RoundCompletion", completionValue)
	end
end

--- Fires "SessionLength" (value = seconds since the player's DataManager
--- profile finished loading) when a player leaves. Session start is
--- measured from profile load, not PlayerAdded, since that's when a player
--- actually begins participating rather than still loading in.
function Analytics.LogSessionEnded(player: Player, sessionLengthSeconds: number)
	AnalyticsService:LogCustomEvent(player, "SessionLength", sessionLengthSeconds)
end

--- Fires a "Shop" sink economy event for a successful weapon purchase, so
--- per-weapon purchase frequency and XP spend show up on the Economy
--- dashboard. Only called for a *successful* purchase — a rejected
--- purchase (insufficient XP, already owned, etc.) never spent XP, so there
--- is nothing to log as an economy sink for it.
function Analytics.LogWeaponPurchased(player: Player, weaponId: string, cost: number, newXp: number)
	AnalyticsService:LogEconomyEvent(
		player,
		Enum.AnalyticsEconomyFlowType.Sink,
		"XP",
		cost,
		newXp,
		Enum.AnalyticsEconomyTransactionType.Shop.Name,
		weaponId
	)
end

return Analytics
