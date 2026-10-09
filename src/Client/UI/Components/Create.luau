--!strict
-- Declarative-ish instance builder used by every UI module:
--   Create("Frame", { Name = "X", Size = ... }, { child1, child2 })
-- Keeps construction code compact and consistent without a UI framework dependency.

local function Create(className: string, props: { [string]: any }?, children: { any }?): any
	local instance = Instance.new(className) :: any
	local parent: Instance? = nil
	if props then
		for key, value in props do
			if key == "Parent" then
				parent = value
			else
				instance[key] = value
			end
		end
	end
	if children then
		for _, child in children do
			child.Parent = instance
		end
	end
	if parent then
		instance.Parent = parent
	end
	return instance
end

return Create
