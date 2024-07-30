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
layout.translation = {"", "[entity=productivity-module] ", {"mpp.settings_layout_choice_throughput_t1"}}

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

function layout:prepare_layout_attempts(state)
	state.attempts = {{1, 1}}
	state.attempt_index = 1
	state.best_attempt_index = 1

	return "init_layout_attempt"
end

---@param self SuperCompactLayout
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
				if tile.neighbors_outer > 0 and heuristic(tile) then
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

	miner_stagger(size, M.middle, "south", 1)
	miner_stagger(size, M.middle+size+1, "north", 1)

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

function layout.prepare_belt_layout(state)
	return "expensive_deconstruct"
end

return layout
