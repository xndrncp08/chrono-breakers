--!strict
-- Minimal synchronous signal. Handlers run in connection order; disconnecting during a fire is safe.
-- Used for in-process events between services (never replicated).

export type Connection = {
	Connected: boolean,
	Disconnect: (self: Connection) -> (),
}

export type Signal<T...> = {
	Connect: (self: Signal<T...>, handler: (T...) -> ()) -> Connection,
	Once: (self: Signal<T...>, handler: (T...) -> ()) -> Connection,
	Fire: (self: Signal<T...>, T...) -> (),
	DisconnectAll: (self: Signal<T...>) -> (),
	GetConnectionCount: (self: Signal<T...>) -> number,
}

type Handler = {
	fn: (...any) -> (),
	connection: Connection,
}

local Signal = {}

function Signal.new<T...>(): Signal<T...>
	local handlers: { Handler } = {}
	local self = {} :: any

	local function removeHandler(target: Handler)
		local index = table.find(handlers, target)
		if index then
			table.remove(handlers, index)
		end
	end

	function self:Connect(fn: (T...) -> ()): Connection
		local handler = {} :: Handler
		local connection = { Connected = true } :: any
		function connection:Disconnect()
			if not connection.Connected then
				return
			end
			connection.Connected = false
			removeHandler(handler)
		end
		handler.fn = fn :: any
		handler.connection = connection
		table.insert(handlers, handler)
		return connection
	end

	function self:Once(fn: (T...) -> ()): Connection
		local connection: Connection
		connection = self:Connect(function(...)
			connection:Disconnect()
			fn(...)
		end)
		return connection
	end

	function self:Fire(...: T...)
		-- Snapshot so handlers that connect/disconnect during dispatch don't disturb iteration.
		local snapshot = table.clone(handlers)
		for _, handler in snapshot do
			if handler.connection.Connected then
				handler.fn(...)
			end
		end
	end

	function self:DisconnectAll()
		for _, handler in table.clone(handlers) do
			handler.connection:Disconnect()
		end
	end

	function self:GetConnectionCount(): number
		return #handlers
	end

	return self :: Signal<T...>
end

return Signal
