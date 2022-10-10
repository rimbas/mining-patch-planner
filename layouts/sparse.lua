local floor, ceil = math.floor, math.ceil
local min, max = math.min, math.max

local base = require("layouts.base")
local simple = require("layouts.simple")
local mpp_util = require("mpp_util")
local coord_convert, coord_revert = mpp_util.coord_convert, mpp_util.coord_revert
local miner_direction, opposite = mpp_util.miner_direction, mpp_util.opposite
local belt_direction = mpp_util.belt_direction
local mpp_revert = mpp_util.revert


local layout = table.deepcopy(base) --[[@as Layout]]

layout.name = "sparse"
layout.translation = {"mpp.settings_layout_choice_sparse"}

layout.restrictions.miner_near_radius = {1, 10e3}
layout.restrictions.miner_far_radius = {2, 10e3}
layout.restrictions.pole_omittable = true
layout.restrictions.pole_width = {1, 1}
layout.restrictions.pole_length = {7.5, 10e3}
layout.restrictions.pole_supply_area = {2.5, 10e3}
layout.restrictions.lamp_available = true

layout.on_load = simple.on_load
layout.start = simple.start
layout.process_grid = simple.process_grid

---@param state SimpleState
---@return PlacementAttempt
local function placement_attempt(state, shift_x, shift_y)
	local grid = state.grid
	local size, near, far = state.miner.size, state.miner.near, state.miner.far
	local full_size = far * 2 + 1
	local miners = {}
	local miner_index = 1

	for y = 1 + shift_y, state.coords.th + near, full_size do
		local miner_column = 1
		for x = 1 + shift_x, state.coords.tw, full_size do
			local tile = grid:get_tile(x, y)
			local center = grid:get_tile(x+near, y+near)
			local miner = {
				tile = tile,
				line = miner_index,
				column = miner_column,
				center = center,
			}
			if center.far_neighbor_count > 0 then
				miners[#miners+1] = miner
			end
			miner_column = miner_column + 1
		end
		miner_index = miner_index + 1
	end
	return {
		sx=shift_x, sy=shift_y,
		miners=miners,
	}
end

---@param self SimpleLayout
---@param state SimpleState
function layout:init_first_pass(state)
	local c = state.coords
	local m = state.miner
	local attempts = {}
	state.attempts = attempts
	state.best_attempt_index = 1
	state.attempt_index = 2 -- first attempt is used up
	
	local function calc_slack(tw, near, far)
		local fullsize = far * 2 + 1
		local count = ceil(tw / fullsize)
		local overrun = count * fullsize - tw
		local slack = overrun % 2
		--local start = far-near-floor(overrun / 2) - slack
		local start = (far-near)-floor(overrun / 2) - slack
		return count, start, slack
	end

	local countx, slackw2, modx = calc_slack(c.tw, m.near, m.far)
	local county, slackh2, mody = calc_slack(c.th, m.near, m.far)
	
	for sy = slackh2, slackh2 + mody do
		for sx = slackw2, slackw2 + modx do
			attempts[#attempts+1] = {sx, sy, cx = countx, cy = county}
		end
	end

	state.best_attempt = placement_attempt(state, attempts[1][1], attempts[1][2])
	state.best_attempt_score = #state.best_attempt.miners

	if #attempts > 1 then
		state.delegate = "first_pass"
	else
		state.delegate = "simple_deconstruct"
	end
end

---Bruteforce the best solution
---@param self SimpleLayout
---@param state SimpleState
function layout:first_pass(state)
	local attempt_state = state.attempts[state.attempt_index]

	---@type PlacementAttempt
	local current_attempt = placement_attempt(state, attempt_state[1], attempt_state[2])
	local current_attempt_score = #current_attempt.miners

	if current_attempt_score < state.best_attempt_score  then
		state.best_attempt_index = state.attempt_index
		state.best_attempt = current_attempt
		state.best_attempt_score = current_attempt_score
	end

	if state.attempt_index >= #state.attempts then
		state.delegate = "simple_deconstruct"
	else
		state.attempt_index = state.attempt_index + 1
	end
end

layout.simple_deconstruct = simple.simple_deconstruct
layout.place_miners = simple.place_miners

---@param self SimpleLayout
---@param state SimpleState
function layout:placement_belts(state)
	local c = state.coords
	local m = state.miner
	local g = state.grid
	local surface = state.surface
	local attempt = state.best_attempt

	local miner_lanes = {{}}
	local miner_lane_number = 0 -- highest index of a lane, because using # won't do the job if a miner is missing
	local miner_column_max = 0
	
	for _, miner in ipairs(attempt.miners) do
		local index = miner.line
		miner_lane_number = max(miner_lane_number, index)
		miner_column_max = max(miner_column_max, miner.column)
		if not miner_lanes[index] then miner_lanes[index] = {} end
		local line = miner_lanes[index]
		line[#line+1] = miner
	end
	state.miner_column_max = miner_column_max

	for _, lane in ipairs(miner_lanes) do
		table.sort(lane, function(a, b) return a.center.x < b.center.x end)
	end

	local direction = belt_direction[state.direction_choice]

	local function get_lane_length(lane) if lane then return lane[#lane].center.x end return 0 end
	local belts = {}
	state.belts = belts
	local longest_belt = 0
	for i = 1, miner_lane_number, 2 do
		local lane1 = miner_lanes[i]
		local lane2 = miner_lanes[i+1]

		local y = attempt.sy + m.size + 1 + (m.far * 2 + 1) * (i-1)

		local belt = {x1=attempt.sx + 1, x2=attempt.sx + 1, y=y, built=false}
		belts[#belts+1] = belt

		if lane1 or lane2 then
			local x1 = attempt.sx + 1
			local x2 = max(get_lane_length(lane1), get_lane_length(lane2)) + m.near
			longest_belt = max(longest_belt, x2 - x1 + 1)
			belt.x1, belt.x2, belt.built = x1, x2, true

			for x = x1, x2 do
				g:get_tile(x, y).built_on = "belt"
				local tx, ty = coord_revert[state.direction_choice](x, y, c.tw, c.th)
				surface.create_entity{
					raise_built=true,
					name="entity-ghost",
					player=state.player,
					force=state.player.force,
					position={c.gx + tx, c.gy + ty},
					direction=defines.direction[state.direction_choice],
					inner_name=state.belt_choice,
				}
			end
		end

		if lane2 then
			for _, miner in ipairs(lane2) do
				local center = miner.center
				local mx, my = center.x, center.y

				for ny = y + 1, y + (m.far - m.near) * 2 - 1 do
					g:get_tile(mx, ny).built_on = "belt"
					local tx, ty = coord_revert[state.direction_choice](mx, ny, c.tw, c.th)
					surface.create_entity{
						raise_built=true,
						name="entity-ghost",
						player=state.player,
						force=state.player.force,
						position={c.gx + tx, c.gy + ty},
						direction=defines.direction[direction],
						inner_name=state.belt_choice,
					}
				end
			end
		end
	end
	
	state.delegate = "placement_poles"
end

---@param self SimpleLayout
---@param state SimpleState
function layout:placement_poles(state)
	local c = state.coords
	local DIR = state.direction_choice
	local m = state.miner
	local g = state.grid
	local surface = state.surface
	local attempt = state.best_attempt

	local pole_proto = game.entity_prototypes[state.pole_choice] or {supply_area_distance=3, max_wire_distance=9}
	local supply_area_distance, supply_radius, supply_area = 3.5, 3, 6
	if pole_proto then
		supply_area = pole_proto.supply_area_distance
		supply_area_distance = pole_proto.supply_area_distance
		supply_radius = floor(supply_area_distance)
		supply_area = floor(supply_area_distance * 2)
	end

	local power_poles_all = {}
	state.power_poles_all = power_poles_all

	local pole_step = min(floor(pole_proto.max_wire_distance), supply_area + 2)
	state.pole_step = pole_step

	local miner_lane_width = (state.miner_column_max-1)*m.far*2 + state.miner_column_max
	local slack = ceil(miner_lane_width / pole_step) * pole_step - c.tw
	local pole_start = supply_radius - floor(slack / 2) - 1

	local function get_covered_miners(ix, iy)
		for sy = -supply_radius, supply_radius do
			for sx = -supply_radius, supply_radius do
				local tile = g:get_tile(ix+sx, iy+sy)
				if tile and tile.built_on == "miner" then
					return true
				end
			end
		end
	end

	local function place_pole_lane(y, iy, no_light)
		local pole_lane = {}
		local ix = 1
		for x = attempt.sx + pole_start, c.tw + m.size, pole_step do
			local built = false
			if get_covered_miners(x, y) then
				built = true
			end
			local pole = {x=x, y=y, ix=ix, iy=iy, built=built, no_light=no_light}
			pole_lane[ix] = pole

			if built and ix > 1 and pole_lane[ix-1] then
				for bx = ix - 1, 1, -1 do
					local backtrack_pole = pole_lane[bx]
					if not backtrack_pole.built then
						backtrack_pole.built = true
					else
						break
					end

				end
			end

			power_poles_all[#power_poles_all+1] = pole
			ix = ix + 1
		end
		return pole_lane
	end

	local initial_y = attempt.sy
	local iy = 1
	for y = initial_y, c.th + m.full_size, m.full_size * 2 do
		if (m.far - m.near) * 2 + 2 > supply_area then -- single pole can't supply two lanes
			place_pole_lane(y, iy)
			if y ~= initial_y then
				iy = iy + 1
				place_pole_lane(y - (m.far - m.near) * 2 + 1, iy, true)
			end
		else
			local backstep = y == initial_y and 0 or m.near - m.far
			place_pole_lane(y + backstep)
		end
		iy = iy + 1
	end

	if state.pole_choice ~= "none" then
		for  _, pole in ipairs(power_poles_all) do
			if pole.built then
				local x, y = pole.x, pole.y
				g:get_tile(x, y).built_on = "pole"
				surface.create_entity{
					raise_built=true,
					name="entity-ghost",
					player=state.player,
					force=state.player.force,
					position=mpp_revert(c.gx, c.gy, DIR, x, y, c.tw, c.th),
					inner_name=state.pole_choice,
				}
			end
		end
	end

	state.delegate = "placement_lamp"
end

layout.placement_lamp = simple.placement_lamp
layout.placement_landfill = simple.placement_landfill
layout.finish = simple.finish

return layout
