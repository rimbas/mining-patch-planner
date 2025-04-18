local floor, ceil = math.floor, math.ceil
local min, max = math.min, math.max

local common = require("layouts.common")
local simple = require("layouts.simple")
local mpp_util = require("mpp.mpp_util")
local pole_grid_mt = require("mpp.pole_grid_mt")
local drawing      = require("mpp.drawing")
local EAST, NORTH, SOUTH, WEST = mpp_util.directions()
local table_insert = table.insert

---@class CompactLayout : SimpleLayout
local layout = table.deepcopy(simple)

---@class CompactState : SimpleState

layout.name = "compact"
layout.translation = {"", "[entity=underground-belt] ", {"mpp.settings_layout_choice_compact"}}

layout.restrictions.miner_size = {3, 10e3}
layout.restrictions.miner_radius = {1, 10e3}
layout.restrictions.uses_underground_belts = true
layout.restrictions.pole_omittable = true
layout.restrictions.pole_width = {1, 1}
layout.restrictions.pole_length = {7.5, 10e3}
layout.restrictions.pole_supply_area = {2.5, 10e3}
layout.restrictions.pole_zero_gap = false
layout.restrictions.coverage_tuning = true
layout.restrictions.lamp_available = true
layout.restrictions.module_available = true
layout.restrictions.pipe_available = true

---@param state CompactState
---@return PlacementAttempt
function layout:_placement_attempt(state, shift_x, shift_y)
	local grid = state.grid
	local M = state.miner
	local size = M.size
	local miners, postponed = {}, {}
	local heuristic_values = common.init_heuristic_values()
	local lane_layout = {}
	local bx, by = shift_x + M.size - 1, shift_y + M.size - 1

	local heuristic = self:_get_miner_placement_heuristic(state)

	local row_index = 1
	for y_float = shift_y, state.coords.th + size, size + 0.5 do
		local y = ceil(y_float)
		local column_index = 1
		lane_layout[#lane_layout+1] = {y = y, row_index = row_index}
		for x = shift_x, state.coords.tw, size do
			local tile = grid:get_tile(x, y) --[[@as GridTile]]
			local miner = {
				x = x,
				y = y,
				origin_x = x + M.x,
				origin_y = y + M.y,
				tile = tile,
				line = row_index,
				column = column_index,
			}
			if tile.forbidden then
				-- no op
			elseif tile.neighbors_outer > 0 and heuristic(tile) then
				miners[#miners+1] = miner
				common.add_heuristic_values(heuristic_values, M, tile)
			elseif tile.neighbors_outer > 0 then
				postponed[#postponed+1] = miner
			end
			column_index = column_index + 1
		end
		row_index = row_index + 1
	end
	
	local result = {
		sx = shift_x,
		sy = shift_y,
		bx = bx,
		by = by,
		miners = miners,
		lane_layout = lane_layout,
		heuristics = heuristic_values,
		heuristic_score = -(0/0),
		unconsumed = 0,
	}

	common.process_postponed(state, result, miners, postponed)

	common.finalize_heuristic_values(result, heuristic_values, state.coords)

	return result
end

---@param self CompactLayout
---@param state CompactState
function layout:prepare_belt_layout(state)
	local belts = {}
	state.belts = belts
	state.builder_belts = {}

	local coverage = mpp_util.calculate_pole_spacing(state, state.miner_max_column, state.miner_lane_count, true)
	state.builder_power_poles = {}

	if coverage.capable_span then
		self:_placement_capable(state)
	else
		self:_placement_incapable(state)
	end

	return "prepare_belts"
end

---Placement of belts+poles when they tile nicely (enough reach/supply area)
---@param self CompactLayout
---@param state CompactState
function layout:_placement_capable(state)
	local M, C, P, G = state.miner, state.coords, state.pole, state.grid
	local attempt = state.best_attempt
	local miner_lane_count = state.miner_lane_count
	local coverage = mpp_util.calculate_pole_spacing(state, state.miner_max_column, state.miner_lane_count, true)

	local steps = {}
	for i = coverage.pole_start, coverage.full_miner_width, coverage.pole_step do
		table.insert(steps, i)
	end

	local power_grid = pole_grid_mt.new()
	state.power_grid = power_grid
	
	--local transport_layout = {}
	--state.transport_layout = transport_layout

	local iy = 1
	for i = 1, miner_lane_count, 2 do
		y = attempt.sy + floor((M.size + 0.5) * i)

		--local transport_layout_lane = {}
		--transport_layout[ceil(i / 2)] = transport_layout_lane
		local backtrack_build = false
		for step_i = #steps, 1, -1 do
			local x = attempt.sx + steps[step_i]

			local has_consumers = G:needs_power(x, y, P)
			if backtrack_build or step_i == 1 or has_consumers then

				backtrack_build = true

				power_grid:add_pole{
					grid_x = x, grid_y = y,
					ix = step_i, iy = iy,
					backtracked = backtrack_build,
					has_consumers = has_consumers,
					built = has_consumers,
					connections = {},
				}
				--transport_layout_lane[step_i] = {x=x, y=y, built=true}
				-- table_insert(builder_power_poles, {
				-- 	name=P.name,
				-- 	thing="pole",
				-- 	grid_x=x,
				-- 	grid_y=y,
				-- 	ix = step_i,
				-- 	iy = iy,
				-- })
			else
				power_grid:add_pole{
					grid_x = x, grid_y = y,
					ix = step_i, iy = iy,
					backtracked = false,
					has_consumers = has_consumers,
					built = false,
					connections = {},
				}
			end
		end
		iy = iy + 1
	end

	local connectivity = power_grid:find_connectivity(state.pole)
	state.power_connectivity = connectivity
end

---@param self CompactLayout
---@param state CompactState
function layout:prepare_belts(state)
	local M, C, P, G = state.miner, state.coords, state.pole, state.grid

	local attempt = state.best_attempt
	local miner_lanes = state.miner_lanes
	local miner_lane_count = state.miner_lane_count

	local builder_power_poles = state.builder_power_poles
	local connectivity = state.power_connectivity
	local power_grid = state.power_grid

	--local debug_draw = drawing(state, false, false)

	if power_grid and #power_grid == 0 then
		return "expensive_deconstruct"
	elseif power_grid then
		local connected = power_grid:ensure_connectivity(connectivity)

		for _, pole in pairs(connected) do
			table_insert(builder_power_poles, {
				name = P.name,
				quality = state.pole_quality_choice,
				thing = "pole",
				grid_x = pole.grid_x,
				grid_y = pole.grid_y,
				ix = pole.ix,
				iy = pole.iy,
			})
		end
	end

	local builder_belts = state.builder_belts
	local belt_name = state.belt.name
	local underground_name = state.belt.related_underground_belt --[[@as string]]
	local belts = {}
	state.belts = belts
	state.belt_count = 0

	local pipe_adjust = state.place_pipes and -1 or 0

	for i_lane = 1, miner_lane_count, 2 do
		local iy = ceil(i_lane / 2)
		local lane1 = miner_lanes[i_lane]
		local lane2 = miner_lanes[i_lane+1]
		--local transport_layout_lane = transport_layout[ceil(i_lane / 2)]

		local function get_lane_length(lane, out_x) if lane and lane[#lane] then return lane[#lane].x+out_x end return 0 end
		local y = attempt.sy + floor((M.size + 0.5) * i_lane)
		
		local x1 = attempt.sx + pipe_adjust
		local belt = {x1=x1, x2=attempt.sx, y=y, built=false, lane1=lane1, lane2=lane2}
		belts[#belts+1] = belt

		if not lane1 and not lane2 then goto continue_lane end

		local x2 = max(get_lane_length(lane1, M.output_rotated[SOUTH].x), get_lane_length(lane2, M.output_rotated[NORTH].x))
		state.belt_count = state.belt_count + 1

		belt.x2, belt.built = x2, true

		-- debug_draw:draw_circle{x = x1, y = y, width = 7}
		-- debug_draw:draw_circle{x = x2, y = y, width = 7}

		if not power_grid then goto continue_lane end

		local previous_start, first_interval = x1, true
		local power_poles, pole_count, belt_intervals = power_grid[iy], #power_grid[iy], {}
		for i, pole in pairs(power_poles) do
			if not pole.built then goto continue_poles end

			local next_x = pole.grid_x
			table_insert(belt_intervals, {
				x1 = previous_start, x2 = min(x2, next_x - 1),
				is_first = first_interval,
			})
			previous_start = next_x + 2
			first_interval = false

			if x2 < next_x then
				--debug_draw:draw_circle{x = x2, y = y, color = {1, 0, 0}}
				break
			end

			::continue_poles::
		end
		
		if previous_start <= x2 then
			--debug_draw:draw_circle{x = x2, y = y, color = {0, 1, 0}}
			table_insert(belt_intervals, {
				x1 = previous_start, x2 = x2, is_last = true,
			})
		end

		for i, interval in pairs(belt_intervals) do
			local bx1, bx2 = interval.x1, interval.x2
			builder_belts[#builder_belts+1] = {
				name = interval.is_first and belt_name or underground_name,
				quality = state.belt_quality_choice,
				thing = "belt", direction=WEST,
				grid_x = bx1, grid_y = y,
				type = not interval.is_first and "input" or nil
			}
			for x = bx1 + 1, bx2 - 1 do
				builder_belts[#builder_belts+1] = {
					name = belt_name,
					quality = state.belt_quality_choice,
					thing = "belt", direction=WEST,
					grid_x = x, grid_y = y,
				}
			end
			builder_belts[#builder_belts+1] = {
				name = i == #belt_intervals and belt_name or underground_name,
				quality = state.belt_quality_choice,
				thing = "belt", direction=WEST,
				grid_x = bx2, grid_y = y,
				type = not interval.is_last and "output" or nil
			}
		end

		::continue_lane::
	end
	
	return "prepare_pole_layout"
end

---Placement of belts+poles when they don't tile nicely (not enough reach/supply area)
---@param self CompactLayout
---@param state CompactState
function layout:_placement_incapable(state)

end

---@param self CompactLayout
---@param state CompactState
function layout:prepare_pole_layout(state)
	return "prepare_lamp_layout"
end

---@param self CompactLayout
---@param state CompactState
function layout:prepare_lamp_layout(state)
	local next_step = "expensive_deconstruct"

	if state.lamp_choice ~= true then return next_step end

	local lamps = {}
	state.builder_lamps = lamps

	local grid = state.grid

	local sx, sy = state.pole.size, 0
	local lamp_spacing = true
	if state.pole.wire > 7 then lamp_spacing = false end

	for _, pole in ipairs(state.builder_power_poles) do
		local x, y = pole.grid_x + sx, pole.grid_y + sy
		local ix, iy = pole.ix, pole.iy
		local tile = grid:get_tile(x, y)
		local skippable_lamp = iy % 2 == 1 and ix % 2 == 1
		if tile and (not lamp_spacing or skippable_lamp) then
			lamps[#lamps+1] = {
				name="small-lamp",
				thing="lamp",
				grid_x = x,
				grid_y = y,
			}
		end
	end

	return next_step
end

return layout
