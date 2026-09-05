-- A minimal stand-in for ProfileStore (github.com/MadStudioRoblox/ProfileStore,
-- see ServerPackages/_Index/lm-loleris_profilestore@1.0.3/profilestore/docs
-- for the real API this mirrors). Implements exactly the surface DataManager
-- uses: New, :StartSessionAsync (Cancel param respected), Mock (same
-- in-memory behavior — no real DataStore under test either way), and on the
-- returned Profile: .Data, .OnSessionEnd, :AddUserId, :Reconcile, :EndSession.
--
-- Real ProfileStore persists Data across sessions via the DataStore; this
-- fake persists it in-memory per profile_key for the lifetime of the test
-- process, which is enough to test DataManager's own logic (load/save
-- wiring, Cancel handling, session-end cleanup) without needing real
-- DataStore access.

local Signal = require("./Signal")

local FakeProfileStore = {}
FakeProfileStore.__index = FakeProfileStore

function FakeProfileStore.New(_storeName: string, template)
	local store = setmetatable({
		_template = template,
		_dataByKey = {},
	}, FakeProfileStore)
	store.Mock = store -- no real/mock distinction needed for a fake
	return store
end

function FakeProfileStore:StartSessionAsync(profileKey: string, params)
	if params and params.Cancel and params.Cancel() then
		return nil
	end

	if not self._dataByKey[profileKey] then
		self._dataByKey[profileKey] = table.clone(self._template)
	end

	local template = self._template
	local profile = {
		Data = self._dataByKey[profileKey],
		OnSessionEnd = Signal.new(),
		_ended = false,
	}

	function profile:AddUserId(_userId: number) end

	function profile:Reconcile()
		for key, value in template do
			if self.Data[key] == nil then
				self.Data[key] = value
			end
		end
	end

	function profile:EndSession()
		if not self._ended then
			self._ended = true
			self.OnSessionEnd:Fire()
		end
	end

	return profile
end

return FakeProfileStore
