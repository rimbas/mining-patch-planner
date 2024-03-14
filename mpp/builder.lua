local mpp_util = require("mpp.mpp_util")
local coord_revert = mpp_util.revert
local builder = {}

---@class GhostSpecification : LuaSurface.create_entity_param.entity_ghost
---@field grid_x number Grid x coordinate
---@field grid_y number Grid x coordinate
---@field radius number? Object radius or default to 0.5 if nil
---@field thing GridBuilding Enum for the grid

---@class PowerPoleGhostSpecification : GhostSpecification
---@field no_light boolean

--- Builder for a convenience function that automatically translates
--- internal grid state for a surface.create_entity call
---@param state State
function builder.create_entity_builder(state)
	local c = state.coords
	local grid = state.grid
	local DIR = state.direction_choice
	local surface = state.surface
	local gx, gy, tw, th = c.gx, c.gy, c.tw, c.th
	local direction_conv = mpp_util.bp_direction[state.direction_choice]
	local collected_ghosts = state._collected_ghosts

	---@param ghost GhostSpecification
	return function(ghost)
		ghost.raise_built = true
		ghost.player = state.player
		ghost.force = state.player.force
		ghost.inner_name=ghost.name
		ghost.name="entity-ghost"
		-- Assume default entity size of 1 and subtract 0.5 from grid position 
		-- because entity origins in Factorio are offset by -0.5 from our grid coordinates
		-- Larger entities have to be specially handled anyway and can account for the subtraction
		ghost.position=coord_revert(gx, gy, DIR, ghost.grid_x-.5, ghost.grid_y-.5, tw, th)
		ghost.direction=direction_conv[ghost.direction or defines.direction.north]
		local result = surface.create_entity(ghost)
		if result then
			grid:build_specification(ghost)
			collected_ghosts[#collected_ghosts+1] = result
		end
		return result
	end
end

return builder
