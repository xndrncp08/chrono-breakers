--!strict
-- In-memory DataStore adapter with UpdateAsync semantics (transform returning nil cancels the
-- write). Used by unit tests and as the explicit, clearly-logged fallback when Studio has no
-- DataStore API access. Data stored here is lost when the server stops.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TableUtil = require(ReplicatedStorage.Shared.Modules.TableUtil)

export type MemoryDataStore = {
	UpdateAsync: (self: MemoryDataStore, key: string, transform: (any) -> any) -> any,
	GetRaw: (self: MemoryDataStore, key: string) -> any,
	SetRaw: (self: MemoryDataStore, key: string, value: any) -> (),
	FailNext: (self: MemoryDataStore, count: number) -> (),
	writes: number,
}

local MemoryDataStore = {}

function MemoryDataStore.new(): MemoryDataStore
	local data: { [string]: any } = {}
	local failures = 0
	local self = { writes = 0 } :: any

	function self:UpdateAsync(key: string, transform: (any) -> any): any
		if failures > 0 then
			failures -= 1
			error("MemoryDataStore: simulated transient failure")
		end
		local current = TableUtil.deepCopy(data[key])
		local nextValue = transform(current)
		if nextValue == nil then
			return nil
		end
		data[key] = TableUtil.deepCopy(nextValue)
		self.writes += 1
		return TableUtil.deepCopy(nextValue)
	end

	function self:GetRaw(key: string): any
		return TableUtil.deepCopy(data[key])
	end

	function self:SetRaw(key: string, value: any)
		data[key] = TableUtil.deepCopy(value)
	end

	function self:FailNext(count: number)
		failures = count
	end

	return self :: MemoryDataStore
end

return MemoryDataStore
