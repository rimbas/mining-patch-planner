local enum = require("mpp.enums")

local compatibility = {}

--[[----------------------------------------------------------------------------
	Space Exploration
----------------------------------------------------------------------------]]--

local space_exploration_active = nil
---@return boolean
compatibility.is_space_exploration_active = function()
	if space_exploration_active == nil then
		space_exploration_active = script.active_mods["space-exploration"] and true or false
	end
	return space_exploration_active
end

--- @class SERemoteViewToggledEventData: EventData
--- @field player_index uint

-- Thanks Raiguard
compatibility.get_se_events = function()
	local se, events = remote.interfaces["space-exploration"], {}
	if not se then return events end

	if se.get_on_remote_view_started_event then
		events["get_on_remote_view_started_event"] = remote.call("space-exploration", "get_on_remote_view_started_event")
	end
	if se.get_on_remote_view_stopped_event then
		events["get_on_remote_view_stopped_event"] = remote.call("space-exploration", "get_on_remote_view_stopped_event")
	end
	return events
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
		---@cast surface_identification LuaSurface
		surface_identification = surface_identification.index
	end

	local memoized = memoize_space_surfaces[surface_index]
	if memoized ~= nil then return memoized end

	if script.active_mods["space-exploration"] then
		local zone = remote.call("space-exploration", "get_zone_from_surface_index", {surface_index = surface_index} --[[@as table]]) --[[@as LuaSurface?]]
		if not zone then
			memoize_space_surfaces[surface_index] = false
			return false
		end
		local result = remote.call("space-exploration", "get_zone_is_space", {zone_index = zone.index} --[[@as table]]) --[[@as boolean]]
		memoize_space_surfaces[surface_index] = result
		return result
	end
	memoize_space_surfaces[surface_index] = false
	return false
end

---@type LuaCollisionLayerPrototype
local space_collision_layer = prototypes.collision_layer["space_tile"]

---@type table<string, boolean>
local memoize_space_buildable = {}

function compatibility.is_buildable_in_space(name)
	local buildable_status = memoize_space_buildable[name]
	if buildable_status ~= nil then
		return buildable_status
	elseif space_collision_layer == nil then
		return true
	end

	local entity_proto = prototypes.entity[name]
	local allowed = not entity_proto.collision_mask.layers[space_collision_layer.name]

	memoize_space_buildable[name] = allowed

	return allowed
end


--- Return true to skip non space item
---@param is_space boolean
---@param protype LuaEntityPrototype
---@return boolean
compatibility.guess_space_item = function(is_space, protype)
	if not is_space then return false end
	return string.match(protype.name, "^se%-")
end

--[[----------------------------------------------------------------------------
	Pyanodons
----------------------------------------------------------------------------]]--

local pyanodons_active = nil
---@return boolean
compatibility.is_pyanodons_active = function()
	if pyanodons_active == nil then
		local active_mods = script.active_mods
		-- pyanodons_active = script.active_mods["space-exploration"] and true or false
		for k, v in ipairs{"pyrawores", "pycoalprocessing", "pyalienlife"} do
			if active_mods[v] then
				pyanodons_active = true
				break
			end
		end
		pyanodons_active = false
	end
	return pyanodons_active
end

return compatibility
