local max, min = math.max, math.min
local mpp_util = require("mpp.mpp_util")
local EAST, NORTH, SOUTH, WEST, ROTATION = mpp_util.directions()

---@class BeltinatorState : TaskState
---@field belt_x number
---@field belt_y number
---@field belt_specification BeltPlannerSpecification
---@field belt_choice string
---@field belt_direction defines.direction

local function coord_transformer(origin_x, origin_y, direction)
	local world_to_local, local_to_world
	direction = direction % ROTATION
	if direction == EAST then
		world_to_local = function(x, y)
			return -(x-origin_x), -(y-origin_y)
		end
		local_to_world = function(x, y)
			return -x+origin_x, -y+origin_y
		end
	elseif direction == SOUTH then
		world_to_local = function(x, y)
			return y-origin_y, -(x-origin_x)
		end
		local_to_world = function(x, y)
			return -y+origin_y, x+origin_x
		end
	elseif direction == NORTH then
		world_to_local = function(x, y)
			return -(y-origin_y), x-origin_x
		end
		local_to_world = function(x, y)
			return y+origin_y, -x+origin_x
		end
	else
		world_to_local = function(x, y)
			return x-origin_x, y-origin_y
		end
		local_to_world = function(x, y)
			return x+origin_x, y+origin_y
		end
	end
	return world_to_local, local_to_world
end

local belt_planner = {}

---@alias BeltinatorSegmentType
---| "elbow"

---@class BeltinatorSegmentSpecification
---@field belt_choice string
---@field type BeltinatorSegmentType
---@field start_direction defines.direction
---@field end_direction defines.direction
---@field x1 number
---@field y1 number
---@field x2 number
---@field y2 number

---comment
---@param builder EntityBuilderFunction
---@param t BeltinatorSegmentSpecification
function belt_planner.build_elbow(builder, t)
	
	local end_direction = t.end_direction
	local start_direction = t.start_direction
	
	local w2l, l2w = coord_transformer(t.x1, t.y1, t.start_direction)
	
	do
		local lx1, ly1 = w2l(t.x1, t.y1)
		local lx2, ly2 = w2l(t.x2, t.y2)
		
		local lx3
		
		local breakpoint = true
		
		local loop_incrementer = lx2 < lx1 and -1 or 1
		for ix = lx1, lx2, loop_incrementer do
			if ix == lx2 then goto cont end
			local wx, wy = l2w(ix, ly1)
			builder{
				name = t.belt_choice,
				grid_x = wx,
				grid_y = wy,
				direction = start_direction,
			}
			::cont::
		end
		
		loop_incrementer = ly2 < ly1 and -1 or 1
		for iy = ly1, ly2, loop_incrementer do
		-- for iy = min(ly1, ly2), max(ly1, ly2) do
			local wx, wy = l2w(lx2, iy)
			builder{
				name = t.belt_choice,
				grid_x = wx,
				grid_y = wy,
				direction = end_direction,
			}
		end
		
		-- builder{
		-- 	name = t.choice,
		-- 	-- grid_x = tx + x_direction * (count - i),
		-- 	grid_x = t.x2,
		-- 	grid_y = t.y1,
		-- 	direction = end_direction,
		-- }
	end
	
	
	local a = true
end

return belt_planner
