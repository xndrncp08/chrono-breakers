--!strict
-- Small, dependency-free table helpers.

local TableUtil = {}

function TableUtil.deepCopy<T>(value: T): T
	if type(value) ~= "table" then
		return value
	end
	local copy = {}
	for key, item in value :: any do
		copy[TableUtil.deepCopy(key)] = TableUtil.deepCopy(item)
	end
	return copy :: any
end

function TableUtil.count(map: { [any]: any }): number
	local n = 0
	for _ in map do
		n += 1
	end
	return n
end

function TableUtil.keys<K>(map: { [K]: any }): { K }
	local list = {}
	for key in map do
		table.insert(list, key)
	end
	return list
end

function TableUtil.shallowEqual(a: { [any]: any }, b: { [any]: any }): boolean
	for key, value in a do
		if b[key] ~= value then
			return false
		end
	end
	for key in b do
		if a[key] == nil then
			return false
		end
	end
	return true
end

-- Truncates a display string to a maximum number of UTF-8 characters, appending an ellipsis.
function TableUtil.truncate(text: string, maxChars: number): string
	local length = utf8.len(text)
	if length == nil or length <= maxChars then
		return text
	end
	local byteIndex = utf8.offset(text, maxChars)
	if byteIndex == nil then
		return text
	end
	return string.sub(text, 1, byteIndex - 1) .. "…"
end

return table.freeze(TableUtil)
