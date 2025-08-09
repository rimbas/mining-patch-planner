local floor, ceil = math.floor, math.ceil
local min, max = math.min, math.max

local common = require("layouts.common")
local base = require("layouts.super_compact")
local mpp_util = require("mpp.mpp_util")
local pole_grid_mt = require("mpp.pole_grid_mt")
local drawing      = require("mpp.drawing")
local EAST, NORTH, SOUTH, WEST = mpp_util.directions()
local table_insert = table.insert

---@class ThroughputLayout : SuperCompactLayout
local layout = table.deepcopy(base)

---@class ThroughputState : SuperCompactState

layout.name = "throughput_t1"
layout.translation = {"", "[item=productivity-module] ", {"mpp.settings_layout_choice_throughput_t1"}}

layout.restrictions.miner_size = {3, 5}
layout.restrictions.miner_radius = {1, 10e3}
layout.restrictions.uses_underground_belts = true
layout.restrictions.pole_omittable = true
layout.restrictions.pole_width = {1, 1}
layout.restrictions.pole_length = {7.5, 10e3}
layout.restrictions.pole_supply_area = {3.5, 10e3}
layout.restrictions.pole_zero_gap = false
layout.restrictions.coverage_tuning = true
layout.restrictions.module_available = true

-- function layout:prepare_layout_attempts(state)
-- 	state.attempts = {{1, 1}}
-- 	state.attempt_index = 1
-- 	state.best_attempt_index = 1

-- 	return "init_layout_attempt"
-- end

---@param self ThroughputLayout
---@param state ThroughputState
---@return PlacementAttempt
function layout:_placement_attempt(state, shift_x, shift_y)
	local grid = state.grid
	local M, C = state.miner, state.coords
	local size, area = M.size, M.area
	local miners, postponed = {}, {}
	local heuristic_values = common.init_heuristic_values()
	local lane_layout = {}

	local heuristic = self:_get_miner_placement_heuristic(state)

	local function miner_stagger(start_x, start_y, direction, row_index)
		for y = shift_y + start_y, C.th + 2, size * 2 + 1 do
			if not lane_layout[row_index] then lane_layout[row_index] = {y=y, row_index=row_index} end
			local ix = 1

			for x = shift_x + start_x, C.tw + 2, size * 2 do
				local tile = grid:get_tile(x, y) --[[@as GridTile]]
				
				---@type MinerPlacementInit
				local miner = {
					x = x,
					y = y,
					origin_x = x + M.x,
					origin_y = y + M.y,
					tile = tile,
					direction = direction,
					line = row_index,
					column = ix,
				}
				if tile.forbidden then
					-- no op
				elseif tile.neighbors_outer > 0 and heuristic(tile) then
					table_insert(miners, miner)
					common.add_heuristic_values(heuristic_values, M, tile)
				elseif tile.neighbors_outer > 0 then
					postponed[#postponed+1] = miner
				end
				ix = ix + 1
			end
			row_index = row_index + 2
		end
	end

	miner_stagger(0, 0, "south", 2)
	miner_stagger(0, size+1, "north", 2)

	miner_stagger(size, -M.middle-1, "south", 1)
	miner_stagger(size, -M.middle+size, "north", 1)

	local result = {
		sx = shift_x,
		sy = shift_y,
		miners = miners,
		lane_layout = lane_layout,
		heuristics = heuristic_values,
		heuristic_score = -(0/0),
		unconsumed = 0,
	}

	common.process_postponed(state, result, miners, postponed)
	common.finalize_heuristic_values(result, heuristic_values, state.coords)

	for _, miner in pairs(miners) do
		---@cast miner MinerPlacement
		local current_lane = lane_layout[miner.line]
		if not current_lane then
			current_lane = {}
			lane_layout[miner.line] = current_lane
		end
		table_insert(current_lane, miner)
	end

	return result
end

---@param self ThroughputLayout
---@param state ThroughputState
function layout:prepare_belt_layout(state)
	local G, M, C, A = state.grid, state.miner, state.coords, state.best_attempt
	local size, area = M.size, M.area
	local underground_belt = state.belt.related_underground_belt

	local power_poles = {}
	state.builder_power_poles = power_poles

	local belt_lanes = A.lane_layout
	local miner_lane_number = 0 -- highest index of a lane, because using # won't do the job if a lane is missing

	local builder_belts = {}
	state.builder_belts = builder_belts
	local function que_entity(t) builder_belts[#builder_belts+1] = t end
	state.belt_count = 0

	for _, miner in pairs(A.miners) do
		local index = miner.line
		miner_lane_number = max(miner_lane_number, index)
		if not belt_lanes[index] then
			belt_lanes[index] = {y=miner.y, row_index=index}
		end
		local line = belt_lanes[index]
		local out_x = M.output_rotated[defines.direction[miner.direction]][1]
		if line.first_x == nil or (miner.x + out_x) < line.first_x then
			line.first_x = miner.x + out_x
		end
		if line.last_x == nil or (miner.x + out_x) > line.last_x then
			line.last_x = miner.x + out_x
			line.last_miner = miner
		end
		line[#line+1] = miner
	end

	local temp_belts = {}
	for _, lane in pairs(belt_lanes) do temp_belts[#temp_belts+1] = lane end
	table.sort(temp_belts, function(a, b) return a.row_index < b.row_index end)
	state.belts = temp_belts

	local shift_x, shift_y = A.sx, A.sy

	local function place_belts(start_x, end_x, y, poles)
		local belt_start, belt_end = M.out_x + shift_x + start_x, end_x
		local pre_miner = G:get_tile(shift_x + size, y)
		local built_miner = pre_miner and pre_miner.built_thing == "miner" or false

		rendering.draw_circle{
			surface = state.surface,
			radius = 0.45,
			filled = false,
			color = {1, 1, 1},
			width = 3,
			target = {
				C.gx + belt_start,
				C.gy + y,
			},
		}

		if start_x == 0 then
			--- straight runoff
			for x = belt_start - M.out_x - 1, belt_start-1 do
				que_entity{
					name = state.belt_choice,
					thing = "belt",
					grid_x = x,
					grid_y = y,
					direction = WEST,
				}
			end
		else
			-- underground exit
			que_entity{
				name = underground_belt,
				type = "output",
				thing = "belt",
				grid_x = belt_start - size - M.out_x - 1,
				grid_y = y,
				direction = WEST,
			}
			que_entity{
				name=underground_belt,
				type="input",
				thing="belt",
				grid_x=belt_start-M.out_x,
				grid_y=y,
				direction=WEST,
			}
		end

		for x = belt_start, end_x, size * 2 do
			local miner1 = G:get_tile(x, y-1) --[[@as GridTile]]
			local miner2 = G:get_tile(x, y+1) --[[@as GridTile]]
			local built = (miner1 and miner1.built_thing == "miner") or (miner2 and miner2.built_thing == "miner")
			local last = x + size * 2 > end_x

			if last then
				que_entity{
					name = state.belt_choice,
					thing = "belt",
					grid_x = x,
					grid_y = y,
					direction = WEST,
				}
			elseif built then
				que_entity{
					name = underground_belt,
					type = "output",
					thing = "belt",
					grid_x = x,
					grid_y = y,
					direction = WEST,
				}
				que_entity{
					name=underground_belt,
					type="input",
					thing="belt",
					grid_x=x+size+M.out_x+1,
					grid_y=y,
					direction=WEST,
				}
			end
		end

		return belt_start, belt_end
	end

	for i = 1, miner_lane_number do
		local belt = belt_lanes[i]
		if belt and belt.last_x then
			local y = belt.y + size
			local x_start = i % 2 == 0 and 0 or size
			local bx1, bx2 = place_belts(x_start, belt.last_x, y, belt.row_index % 2 == 1)
			belt.x1, belt.x2, belt.y = bx1-size, bx2, y
			state.belt_count = state.belt_count + 1
			local lane1, lane2 = {}, {}
			for _, miner in ipairs(belt) do
				if miner.direction == "north" then
					lane2[#lane2+1] = miner
				else
					lane1[#lane1+1] = miner
				end
			end
			if #lane1 > 0 then belt.lane1 = lane1 end
			if #lane2 > 0 then belt.lane2 = lane2 end
		end
	end

	return "expensive_deconstruct"
end

return layout
