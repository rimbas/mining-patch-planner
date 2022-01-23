local floor, ceil = math.floor, math.ceil
local min, max = math.min, math.max

local util = require("util")
local base = require("layouts.base")
local simple = require("layouts.simple")
local grid_mt = require("grid_mt")

---@type SimpleLayout
local layout = table.deepcopy(base)

layout.name = "sparse"
layout.translation = {"mpp.settings_layout_choice_sparse"}

layout.restrictions = {}
layout.restrictions.miner_near_radius = {1, 10e3}
layout.restrictions.miner_far_radius = {2, 10e3}
layout.restrictions.pole_omittable = true
layout.restrictions.pole_width = {1, 1}
layout.restrictions.pole_length = {7.5, 10e3}
layout.restrictions.pole_supply_area = {5, 10e3}
layout.restrictions.lamp = true

layout.on_load = simple.on_load
layout.start = simple.start
--layout.process_grid = simple.process_grid
---@param state SimpleState
function layout:process_grid(state)
	simple.process_grid(self, state)

	local size, near, far = state.miner.size, state.miner.near, state.miner.far
	local c = state.coords

	state.player.print(("%i,%i, size: %i, full size: %i"):format(c.w, c.h, size, far * 2 + 1))
	state.player.print(("near %i, far %i, size %i"):format(near, far, size))
end

---@param state SimpleState
---@return PlacementAttempt
local function placement_attempt(state, shift_x, shift_y)
	local grid = state.grid
	local size, near, far = state.miner.size, state.miner.near, state.miner.far
	local full_size = far * 2 + 1
	local miners = {}
	local miner_index = 1

	for y = 1 + shift_y, state.coords.th + size, full_size do
		for x = 1 + shift_x, state.coords.tw, full_size do
			local tile = grid:get_tile(x, y)
			local center = grid:get_tile(x+near, y+near)
			local miner = {
				tile = tile,
				line = miner_index,
				center = center,
			}
			if center.far_neighbor_count > 0 then
				miners[#miners+1] = miner
			end
		end
		miner_index = miner_index + 1
	end
	return {
		sx=shift_x, sy=shift_y,
		miners=miners,
	}
end

---@param self Layout
---@param state SimpleState
function layout:init_first_pass(state)
	local m = state.miner
	local attempts = {{0, 0}}
	state.attempts = attempts
	state.best_attempt_index = 1
	state.attempt_index = 2 -- first attempt is used up
	--local ext_behind, ext_forward = -m.far, m.far - m.near
	local ext_behind, ext_forward = -m.near, m.far - m.near
	
	for sy = ext_behind, ext_forward do
		for sx = ext_behind, ext_forward do
			if not (sx == -m.near and sy == -m.near) then
				attempts[#attempts+1] = {sx, sy}
			end
		end
	end

	state.best_attempt = placement_attempt(state, attempts[1][1], attempts[1][2])
	state.best_attempt_score = #state.best_attempt.miners

	local current_attempt = state.best_attempt
	--game.print(fmt_str:format(1, attempts[1][1], attempts[1][2], #current_attempt.miners, #current_attempt.postponed, current_attempt.neighbor_sum, current_attempt.density, state.best_attempt_score))

	state.delegate = "first_pass"
end

---Bruteforce the best solution
---@param self Layout
---@param state SimpleState
function layout:first_pass(state)
	local attempt_state = state.attempts[state.attempt_index]
	local best_attempt = state.best_attempt
	---@type PlacementAttempt
	local current_attempt = placement_attempt(state, attempt_state[1], attempt_state[2])
	local current_attempt_score = #current_attempt.miners

	--game.print(fmt_str:format(state.attempt_index, attempt_state[1], attempt_state[2], #current_attempt.miners, #current_attempt.postponed, current_attempt.neighbor_sum, current_attempt.density, current_attempt_score))

	if current_attempt_score < state.best_attempt_score  then
		state.best_attempt_index = state.attempt_index
		state.best_attempt = current_attempt
		state.best_attempt_score = current_attempt_score
	end

	if state.attempt_index >= #state.attempts then
		--game.print(("Chose attempt #%i"):format(state.best_attempt_index))
		state.delegate = "simple_deconstruct"
	else
		state.attempt_index = state.attempt_index + 1
	end
end

layout.simple_deconstruct = simple.simple_deconstruct
layout.place_miners = simple.place_miners

function layout:placement_belts(state)
	local c = state.coords
	local m = state.miner
	local g = state.grid
	local surface = state.surface
	local attempt = state.best_attempt

	
	state.delegate = "finish"
end

---@param self Layout
---@param state SimpleState
function layout:finish(state)
	state.finished = true
end


return layout
