--!strict
-- Trove-style cleanup container. Tracks RBXScriptConnections, Instances, Signal connections, threads,
-- functions, and nested Cleanup objects, and releases them all (in reverse order) on Clean().
-- After Destroy(), further Add() calls clean the item immediately so late additions cannot leak.

export type Cleanup = {
	Add: <T>(self: Cleanup, item: T) -> T,
	Remove: (self: Cleanup, item: any) -> boolean,
	Clean: (self: Cleanup) -> (),
	Destroy: (self: Cleanup) -> (),
	Count: (self: Cleanup) -> number,
	IsDestroyed: (self: Cleanup) -> boolean,
}

local Cleanup = {}

local function release(item: any)
	local kind = typeof(item)
	if kind == "function" then
		item()
	elseif kind == "thread" then
		if coroutine.status(item) ~= "dead" then
			-- task.cancel is only available in Roblox/Lune runtimes; both provide it.
			pcall(task.cancel, item)
		end
	elseif kind == "RBXScriptConnection" then
		item:Disconnect()
	elseif kind == "Instance" then
		item:Destroy()
	elseif kind == "table" then
		if type(item.Destroy) == "function" then
			item:Destroy()
		elseif type(item.Disconnect) == "function" then
			item:Disconnect()
		elseif type(item.Clean) == "function" then
			item:Clean()
		else
			error("Cleanup: table item has no Destroy/Disconnect/Clean method", 3)
		end
	else
		error(`Cleanup: unsupported item type {kind}`, 3)
	end
end

function Cleanup.new(): Cleanup
	local items: { any } = {}
	local destroyed = false
	local cleaning = false
	local self = {} :: any

	function self:Add<T>(item: T): T
		if destroyed then
			release(item)
			return item
		end
		table.insert(items, item)
		return item
	end

	function self:Remove(item: any): boolean
		local index = table.find(items, item)
		if index then
			table.remove(items, index)
			return true
		end
		return false
	end

	function self:Clean()
		if cleaning then
			return
		end
		cleaning = true
		while #items > 0 do
			local item = table.remove(items) -- LIFO
			-- Packed because `release` returns nothing (keeps strict typing happy).
			local outcome = table.pack(pcall(release, item))
			if not outcome[1] then
				warn(`[Cleanup] failed to release item: {outcome[2]}`)
			end
		end
		cleaning = false
	end

	function self:Destroy()
		self:Clean()
		destroyed = true
	end

	function self:Count(): number
		return #items
	end

	function self:IsDestroyed(): boolean
		return destroyed
	end

	return self :: Cleanup
end

return Cleanup
