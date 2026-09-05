-- Minimal RBXScriptSignal-like mock for tests. Real Roblox signals also
-- support :Wait() and :Disconnect(); only :Connect()/:Fire() are implemented
-- since that's the entire surface the game code under test uses.

local Signal = {}
Signal.__index = Signal

function Signal.new()
	return setmetatable({ _listeners = {} }, Signal)
end

function Signal:Connect(callback)
	table.insert(self._listeners, callback)
	local connection = {}
	function connection.Disconnect()
		local index = table.find(self._listeners, callback)
		if index then
			table.remove(self._listeners, index)
		end
	end
	return connection
end

function Signal:Fire(...)
	-- Copy before iterating: a listener could disconnect itself or another
	-- listener during the call, which would corrupt in-progress iteration
	-- over the live _listeners array.
	local listenersSnapshot = table.clone(self._listeners)
	for _, callback in listenersSnapshot do
		callback(...)
	end
end

return Signal
