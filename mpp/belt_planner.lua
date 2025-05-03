local max, min = math.max, math.min
local floor, ceil = math.floor, math.ceil
local builder  = require("mpp.builder")
local mpp_util = require("mpp.mpp_util")
local EAST, NORTH, SOUTH, WEST, ROTATION = mpp_util.directions()
local coord_convert, coord_revert = mpp_util.coord_convert, mpp_util.coord_revert

---@class BeltinatorState : TaskState
---@field start_x number
---@field bound_y1 number
---@field bound_y2 number
---@field belt_x number
---@field belt_y number
---@field belt_specification BeltPlannerSpecification
---@field belt_choice string
---@field belt_direction defines.direction

---@class BeltOutputPosition
---@field x number
---@field y number
---@field index number
---@field direction defines.direction

local function coord_transformer(direction)
	direction = direction % ROTATION
	if direction == EAST then
		return
		function(x, y) return -x, -y end,
		function(x, y) return -x, -y end
	elseif direction == NORTH then
		return
		function(x, y) return y, -x end,
		function(x, y) return -y, x	end
	elseif direction == SOUTH then
		return
		function(x, y) return -y, x end,
		function(x, y) return y, -x end
	else
		return
		function(x, y) return x, y end,
		function(x, y) return x, y end
	end
end

local belt_planner = {}

---@alias BeltinatorSegmentType
---| "elbow"

---@class BeltinatorSegmentSpecification
---@field belt_choice string
---field type BeltinatorSegmentType
---@field start_direction defines.direction
---@field end_direction defines.direction
---@field x1 number
---@field y1 number
---@field x2 number
---@field y2 number

---@param state BeltinatorState
function belt_planner.layout(state)
	
	local belt_specification = state.belt_specification
	local count = belt_specification.count
	local tx, ty = state.belt_x, state.belt_y
	local world_direction = state.belt_direction
	local belt_choice = state.belt_choice
	local start_x = state.start_x
	
	local conv = coord_convert[state.direction_choice]
	-- local rot = mpp_util.bp_direction[state.direction_choice][direction]
	-- local bump = state.direction_choice == "north" or state.direction_choice EAST
	-- local belt_direction = mpp_util.clamped_rotation(((-defines.direction[state.direction_choice]) % ROTATION)-EAST, world_direction)
	local belt_direction = world_direction
	
	local create_entity = builder.create_entity_builder(state)
	
	rendering.clear()
	local converter = mpp_util.reverter_delegate(state.coords, state.direction_choice)

	local function plan_west(op_x, op_y)
		--[[ debug rendering
			for i, belt in ipairs(belt_specification) do
				local belt_y = belt.y
				local target_y = ty + i - count

				local gx, gy = converter(belt.x1-1, belt.y)
				rendering.draw_circle{
					surface = state.surface,
					target = {gx+.5, gy+.5},
					radius = 0.45,
					width = 3,
					color = {1, 0.7, 0},
				}
				rendering.draw_text{
					surface = state.surface,
					target = {gx+.5, gy},
					color = {1, 0.7, 0},
					text = i,
					alignment= "center",
					scale = 2,
				}
				gx, gy = converter(tx, target_y)
				rendering.draw_circle{
					surface = state.surface,
					target = {gx+.5, gy+.5},
					radius = 0.45,
					width = 3,
					color = {.39, .58, .93},
				}
				rendering.draw_text{
					surface = state.surface,
					target = {gx+.5, gy},
					color = {.39, .58, .93},
					text = i,
					alignment= "center",
					scale = 2,
				}
			end
		end --]]
		
		local breaking_point = -count
		
		for i, belt in ipairs(belt_specification) do
			local belt_y = belt.y
			local target_y = op_y + i - count
			
			if belt_y >= target_y then
				breaking_point = i -- belt that doesn't need to accomodate spacing for other belts
				break
			end
		end
		
		if belt_specification[count].y < op_y then
			breaking_point = count + 1
		end
		
		local accomodation_value = breaking_point - 1.5
		for i, belt in ipairs(belt_specification) do
			local accomodation_shift = math.ceil(math.abs(accomodation_value))
			local target_y = op_y + i - count
			
			-- local gx, gy = converter(belt.x1-accomodation_shift, belt.y)
			-- rendering.draw_circle{
			-- 	surface = state.surface,
			-- 	target = {gx+.5, gy+.5},
			-- 	radius = 0.45,
			-- 	width = 3,
			-- 	color = {1, 0, 0},
			-- }
			
			if target_y ~= belt.y then
				belt_planner.build_elbow(create_entity, {
					start_direction = WEST,
					end_direction = accomodation_value >= 0 and SOUTH or NORTH,
					x1 = belt.x1-1,
					y1 = belt.y,
					x2 = belt.x1-accomodation_shift,
					y2 = target_y + math.sign(accomodation_value),
					belt_choice = belt_choice,
				})
				belt_planner.build_line_horizontal(create_entity, {
					start_direction = WEST,
					x1 = op_x,
					y1 = target_y,
					x2 = belt.x1 - accomodation_shift,
					belt_choice = belt_choice,
				})
			else
				belt_planner.build_line_horizontal(create_entity, {
					start_direction = WEST,
					x1 = op_x,
					y1 = target_y,
					x2 = belt.x1 - 1,
					belt_choice = belt_choice,
				})
			end
			
			accomodation_value = accomodation_value - 1
		end
	end
	
	---@param op_x number
	---@param op_y number
	---@param op_direction defines.direction
	---@return List<BeltOutputPosition>
	local function plan_vertical(op_x, op_y, op_direction)
		local output_positions = List()
		local x_direction = op_direction == NORTH and 1 or -1
		-- local create_entity = function() end
		for i, belt in ipairs(belt_specification) do
			belt_planner.build_elbow(create_entity, {
			-- table.insert(segment_specification, {
				start_direction = WEST,
				end_direction = op_direction,
				type = "elbow",
				x1 = belt.x1 - 1,
				y1 = belt.y,
				x2 = op_x + (count - i) * x_direction,
				y2 = op_y,
				belt_choice = belt_choice,
			})
			
			output_positions:push{
				x = op_x + (count - i) * x_direction,
				y = op_y,
				direction = op_direction,
				index = belt.index,
			}
		end
		
		return output_positions
	end
	
	local function plan_east(op_x, op_y)
		local op_y1, op_y2 = belt_specification[1].y, belt_specification[belt_specification.count].y
		local op_direction = op_y < op_y1 and NORTH or SOUTH
		local intermediate_y = op_direction == NORTH and op_y1 or op_y2
		local direction_accomodation = op_direction == NORTH and -belt_specification.count or -1
		
		local actual_x = min(start_x, op_x+1)
		
		local output_positions = plan_vertical(actual_x+direction_accomodation, intermediate_y, op_direction)
		
		for _, position in ipairs(output_positions) do
			---@cast position BeltOutputPosition
			belt_planner.build_elbow(create_entity, {
				belt_choice = belt_choice,
				start_direction = op_direction,
				end_direction = EAST,
				x1 = position.x,
				y1 = position.y,
				x2 = op_x,
				y2 = op_y+position.index-1,
			})
		end
	end
	
	if belt_direction == EAST then
		plan_east(tx, ty)
	elseif belt_direction == WEST then
		plan_west(tx, ty)
	else
		plan_vertical(tx, ty, belt_direction)
	end
end


---@param builder_func EntityBuilderFunction
---@param t BeltinatorSegmentSpecification
function belt_planner.build_elbow(builder_func, t)
	local belt_choice = t.belt_choice
	local end_direction = t.end_direction
	local start_direction = t.start_direction
	
	local w2l, l2w = coord_transformer(t.start_direction)
	
	local lx1, ly1 = w2l(t.x1, t.y1)
	local lx2, ly2 = w2l(t.x2, t.y2)
	
	local loop_incrementer = lx2 < lx1 and -1 or 1
	for ix = lx1, lx2, loop_incrementer do
		if ix == lx2 then goto cont end
		local wx, wy = l2w(ix, ly1)
		builder_func{
			name = belt_choice,
			grid_x = wx,
			grid_y = wy,
			direction = start_direction,
		}
		::cont::
	end
	
	loop_incrementer = ly2 < ly1 and -1 or 1
	for iy = ly1, ly2, loop_incrementer do
		local wx, wy = l2w(lx2, iy)
		builder_func{
			name = belt_choice,
			grid_x = wx,
			grid_y = wy,
			direction = end_direction,
		}
	end
end

---@param builder_func EntityBuilderFunction
---@param t BeltinatorSegmentSpecification
function belt_planner.build_line_horizontal(builder_func, t)
	local belt_choice = t.belt_choice
	local start_direction = t.start_direction
	local ty = t.y1
	for ix = t.x1, t.x2 do
		
		builder_func{
			name = belt_choice,
			grid_x = ix,
			grid_y = ty,
			direction = start_direction,
		}
	end
end

---@param builder_func EntityBuilderFunction
---@param t BeltinatorSegmentSpecification
function belt_planner.build_line_vertical(builder_func, t)
	local belt_choice = t.belt_choice
	local start_direction = t.start_direction
	local tx = t.x1
	for iy = t.y1, t.y2 do
		
		builder_func{
			name = belt_choice,
			grid_x = tx,
			grid_y = iy,
			direction = start_direction,
		}
	end
end

return belt_planner
