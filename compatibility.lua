local enum = require("enums")

local compatibility = {}

local space_exploration_active = nil
---@return boolean
compatibility.is_space_exploration_active = function()
	if space_exploration_active == nil then
		space_exploration_active = game.active_mods["space-exploration"] and true or false
	end
	return space_exploration_active
end

local memoize_space_surfaces = {}

--- Wrapper for Space Exploration get_zone_is_space remote interface calls
---@param surface_identification SurfaceIdentification
---@return boolean
compatibility.is_space = function(surface_identification)
	local surface_index = surface_identification
	if type(surface_identification) == "string" then
		surface_identification = game.get_surface(surface_identification).index
	elseif type(surface_identification) == "userdata" then
		surface_identification = surface_identification.index
	end

	local memoized = memoize_space_surfaces[surface_index]
	if memoized ~= nil then return memoized end

	if game.active_mods["space-exploration"] then
		local zone = remote.call("space-exploration", "get_zone_from_surface_index", {surface_index = surface_index})
		if not zone then
			memoize_space_surfaces[surface_index] = false
			return false
		end
		local result = remote.call("space-exploration", "get_zone_is_space", {zone_index = zone.index})
		memoize_space_surfaces[surface_index] = result
		return result
	end
	memoize_space_surfaces[surface_index] = false
	return false
end

--- Return true to skip non space item
---@param is_space boolean
---@param protype LuaEntityPrototype
---@return boolean
compatibility.guess_space_item = function(is_space, protype)
	if not is_space then return false end
	return string.match(protype.name, "^se%-")
end

return compatibility
