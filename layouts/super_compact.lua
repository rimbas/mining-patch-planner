local floor, ceil = math.floor, math.ceil
local min, max = math.min, math.max

local common = require("layouts.common")
local simple = require("layouts.simple")
local mpp_util = require("mpp_util")
local builder = require("builder")
local mpp_revert = mpp_util.revert

---@class SuperCompactLayout : SimpleLayout
local layout = table.deepcopy(simple)

layout.name = "super_compact"
layout.translation = {"mpp.settings_layout_choice_super_compact"}

layout.restrictions.miner_near_radius = {1, 1}
layout.restrictions.miner_far_radius = {1, 10e3}
layout.restrictions.uses_underground_belts = true
layout.restrictions.pole_omittable = true
layout.restrictions.pole_width = {1, 1}
layout.restrictions.pole_length = {5, 10e3}
layout.restrictions.pole_supply_area = {2.5, 10e3}
layout.restrictions.coverage_tuning = true
layout.restrictions.lamp_available = false
layout.restrictions.module_available = true
layout.restrictions.pipe_available = false

---@class SuperCompactState : SimpleState
---@field miner_bounds any

-- Validate the selection
---@param self SuperCompactLayout
---@param state SimpleState
function layout:validate(state)
	local c = state.coords
	if (state.direction_choice == "west" or state.direction_choice == "east") then
		if c.h < 3 then
			return nil, {"mpp.msg_miner_err_1_w", 3}
		end
	else
		if c.w < 3 then
			return nil, {"mpp.msg_miner_err_1_h", 3}
		end
	end
	return true
end

---@param self SuperCompactLayout
---@param state SimpleState
---@return PlacementAttempt
function layout:_placement_attempt(state, shift_x, shift_y)
	local grid = state.grid
	local size, near, fullsize = state.miner.size, state.miner.near, state.miner.full_size
	local neighbor_sum = 0
	local far_neighbor_sum = 0
	local miners, postponed = {}, {}
	local simple_density = 0
	local real_density = 0
	local leech_sum = 0
	local empty_space = 0
	local lane_layout = {}
	
	--@param tile GridTile
	--local function heuristic(tile) return tile.neighbor_count > 2 end

	local heuristic = self:_get_miner_placement_heuristic(state)
	
	local function miner_stagger(start_x, start_y, direction, stagger_step, mark_lane)
		local miner_index = 1
		for y = 1 + shift_y + start_y, state.coords.th + 2, size * 3 + 1 do
			if mark_lane then lane_layout[#lane_layout+1] = {y=y} end
			for x = 1 + shift_x + start_x, state.coords.tw + 2, size * 2 do
				local tile = grid:get_tile(x, y)
				local center = grid:get_tile(x+near, y+near) --[[@as GridTile]]
				local miner = {
					tile = tile,
					center = center,
					direction = direction,
					stagger = stagger_step,
					line = miner_index,
				}
				if center.far_neighbor_count > 0 then
					if heuristic(center) then
						miners[#miners+1] = miner
						neighbor_sum = neighbor_sum + center.neighbor_count
						far_neighbor_sum = far_neighbor_sum + center.far_neighbor_count
						empty_space = empty_space + (size^2) - center.neighbor_count
						simple_density = simple_density + center.neighbor_count / (size ^ 2)
						real_density = real_density + center.far_neighbor_count / (fullsize ^ 2)
						leech_sum = leech_sum + max(0, center.far_neighbor_count - center.neighbor_count)
					else
						postponed[#postponed+1] = miner
					end
				end
			end
			miner_index = miner_index + 1
		end
	end

	miner_stagger(0, -2, "south", 1)
	miner_stagger(3, 0, "east", 1, true)
	miner_stagger(0, 2, "north", 1)

	-- the redundant calculation makes it easier to find the stagger offset
	miner_stagger(0+size, -2+size+2, "south", 2)
	miner_stagger(3-size, 0+size+2, "east", 2, true)
	miner_stagger(0+size, 2+size+2, "north", 2)

	local result = {
		sx=shift_x, sy=shift_y,
		miners = miners,
		miner_count=#miners,
		lane_layout=lane_layout,
		postponed = postponed,
		neighbor_sum = neighbor_sum,
		far_neighbor_sum = far_neighbor_sum,
		leech_sum=leech_sum,
		simple_density = simple_density,
		real_density = real_density,
		empty_space=empty_space,
		unconsumed_count = 0,
		postponed_count = 0,
	}

	common.process_postponed(state, result, miners, postponed)

	return result
end


---@param self SimpleLayout
---@param state SimpleState
---@return CallbackState
function layout:prepare_miner_layout(state)

	local miners = state.best_attempt.miners
	local default = miners[1].center
	local min_x, min_y = default.x, default.y
	local max_x, max_y = default.x, default.y

	local e_north, e_east, e_south = 0, 0, 0

	for _, miner in ipairs(miners) do
		local center = miner.center

		-- accomodating for belt
		if min_y > center.y and miner.direction == "north" then
			e_north = 1
		elseif min_y > center.y then
			e_north = 0
		end
		if max_x < center.x and miner.direction == "east" then
			e_east = 1
		elseif max_x < center.x then
			e_east = 0
		end
		if max_y < center.y and miner.direction == "south" then
			e_south = 1
		elseif max_y < center.y then
			e_south = 0
		end
		
		min_x = min(min_x, center.x)
		min_y = min(min_y, center.y)
		max_x = max(max_x, center.x)
		max_y = max(max_y, center.y)

		--[[ debug visualisation - miner placement
		local color = {1, 0, 0}
		if miner.direction == "west" then
			color = {0, 1, 0}
		elseif miner.direction == "north" then
			color = {0, 0, 1}
		end
		local rect_color = miner.stagger == 1 and {1, 1, 1} or {0, 0, 0}
		local off = state.miner.size / 2 - 0.1

		local tx, ty = coord_revert[DIR](center.x, center.y, c.tw, c.th)
		rendering.draw_rectangle{
			surface = state.surface,
			filled = false,
			--color = miner.postponed and {1, 0, 0} or {0, 1, 0},
			color = rect_color,
			width = 3,
			--target = {c.x1 + x, c.y1 + y},
			left_top = {c.gx+tx-off, c.gy + ty - off},
			right_bottom = {c.gx+tx+off, c.gy + ty + off},
		}

		rendering.draw_text{
			surface=state.surface,
			color=color,
			text=miner_dir,
			target=mpp_revert(c.gx, c.gy, DIR, center.x, center.y, c.tw, c.th),
			vertical_alignment = "top",
			alignment = "center",
		}

		rendering.draw_text{
			surface=state.surface,
			color={1, 1, 1},
			text=miner.line * 2 + miner.stagger - 2,
			target={c.gx + tx, c.gy + ty},
			vertical_alignment = "bottom",
			alignment = "center",
		}

		--]]
	end

	state.miner_bounds = {
		min_x=min_x,
		min_y=min_y,
		max_x=max_x,
		max_y=max_y,
		e_north	= e_north,
		e_east	= e_east,
		e_south	= e_south,
	}

	return "unagressive_deconstruct"
end

---@param self SuperCompactLayout
---@param state SuperCompactState
---@return DeconstructSpecification
function layout:_prepare_deconstruct_specification(state)
	local m = state.miner
	local bounds = state.miner_bounds

	state.deconstruct_specification = {
		x = bounds.min_x   - m.near - m.size,
		y = bounds.min_y-1 - m.near - bounds.e_north,
		width = bounds.max_x - bounds.min_x + m.near * 2 + m.size + bounds.e_east,
		height = bounds.max_y - bounds.min_y+1 + m.near * 2 + bounds.e_north + bounds.e_south,
	}

	return state.deconstruct_specification
end

---@param self SuperCompactLayout
---@param state SimpleState
---@return CallbackState
function layout:placement_miners(state)
	local create_entity = builder.create_entity_builder(state)

	local grid = state.grid
	local module_inv_size = state.miner.module_inventory_size --[[@as uint]]

	for _, miner in ipairs(state.best_attempt.miners) do
		local center = miner.center
		
		grid:build_miner(center.x, center.y)
		local ghost = create_entity{
			name = state.miner_choice,
			grid_x = center.x,
			grid_y = center.y,
			direction = defines.direction[miner.direction],
		}

		if state.module_choice ~= "none" then
			ghost.item_requests = {[state.module_choice] = module_inv_size}
		end
	end

	return "placement_belts"
end

---@param self SuperCompactLayout
---@param state SimpleState
function layout:placement_belts(state)
	local m = state.miner
	local g = state.grid
	local attempt = state.best_attempt
	local underground_belt = game.entity_prototypes[state.belt_choice].related_underground_belt.name
	local create_entity = builder.create_entity_builder(state)

	local power_poles = {}
	state.power_poles_all = power_poles
	
	---@type table<number, MinerPlacement[]>
	local miner_lanes = {}
	local miner_lane_number = 0 -- highest index of a lane, because using # won't do the job if a lane is missing

	state.belt_count = 0

	for _, miner in ipairs(attempt.miners) do
		local index = miner.line * 2 + miner.stagger - 2
		miner_lane_number = max(miner_lane_number, index)
		if not miner_lanes[index] then miner_lanes[index] = {} end
		local line = miner_lanes[index]
		if miner.center.x > (line.last_x or 0) then
			line.last_x = miner.center.x
			line.last_miner = miner
		end
		line[#line+1] = miner
	end

	local shift_x, shift_y = state.best_attempt.sx, state.best_attempt.sy

	local function place_belts(start_x, end_x, y)
		local belt_start = 1 + shift_x + start_x
		if start_x == 0 then
			-- straight runoff
			for sx = 0, 2 do
				create_entity{
					name=state.belt_choice,
					thing="belt",
					grid_x=belt_start-sx,
					grid_y=y,
					direction=defines.direction[state.direction_choice],
				}
			end
		else
			-- underground exit
			create_entity{
				name=underground_belt,
				type="output",
				thing="belt",
				grid_x=shift_x-1,
				grid_y=y,
				direction=defines.direction[state.direction_choice],
			}
			create_entity{
				name=underground_belt,
				type="input",
				thing="belt",
				grid_x=shift_x+m.size+1,
				grid_y=y,
				direction=defines.direction[state.direction_choice],
			}
			local miner = g:get_tile(shift_x+m.size, y)
			if miner and miner.built_on == "miner" then
				power_poles[#power_poles+1] = {
					x = shift_x,
					y = y,
					built=true,
				}
			end
		end

		for x = belt_start, end_x, m.size * 2 do
			local miner1 = g:get_tile(x, y-1) --[[@as GridTile]]
			local miner2 = g:get_tile(x, y+1) --[[@as GridTile]]
			local miner3 = g:get_tile(x+3, y) --[[@as GridTile]]
			local built = miner1.built_on == "miner" or miner2.built_on == "miner"
			local capped = miner3.built_on == "miner"
			local pole_built = built or capped
			local last = x + m.size * 2 > end_x

			if last and not capped then
				-- last passtrough and no trailing miner
				create_entity{
					name=state.belt_choice,
					thing="belt",
					grid_x=x+1,
					grid_y=y,
					direction=defines.direction[state.direction_choice],
				}
			elseif capped or built then
				create_entity{
					name=underground_belt,
					type="output",
					thing="belt",
					grid_x=x+1,
					grid_y=y,
					direction=defines.direction[state.direction_choice],
				}
				create_entity{
					name=underground_belt,
					type="input",
					thing="belt",
					grid_x=x+m.size*2,
					grid_y=y,
					direction=defines.direction[state.direction_choice],
				}
			else
				for sx = 1, 6 do
					create_entity{
						name=state.belt_choice,
						thing="belt",
						grid_x=x+sx,
						grid_y=y,
						direction=defines.direction[state.direction_choice],
					}
				end
			end

			power_poles[#power_poles+1] = {
				x = x + 2,
				y = y,
				built=pole_built,
			}
		end
	end

	local stagger_shift = 1
	for i = 1, miner_lane_number do
		local lane = miner_lanes[i]
		if lane and lane.last_x then
			local y = m.size + shift_y - 1 + (m.size + 2) * (i-1)
			local x_start = stagger_shift % 2 == 0 and 3 or 0
			place_belts(x_start, lane.last_x, y)
			state.belt_count = state.belt_count + 1
		end
		stagger_shift = stagger_shift + 1
	end

	return "placement_pole"
end

---@param self SuperCompactLayout
---@param state SimpleState
function layout:placement_pole(state)
	local next_step = "placement_landfill"
	if state.pole_choice == "none" then
		return next_step
	end
	local create_entity = builder.create_entity_builder(state)
	for _, pole in ipairs(state.power_poles_all) do
		local x, y = pole.x, pole.y
		if pole.built then
			create_entity{
				name=state.pole_choice,
				thing="pole",
				grid_x=x,
				grid_y=y,
			}
		end
	end

	return next_step
end

return layout
