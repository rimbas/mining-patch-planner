local floor, ceil = math.floor, math.ceil
local min, max = math.min, math.max

local util = require("util")
local base = require("layouts.base")
local simple = require("layouts.simple")
local grid_mt = require("grid_mt")
local mpp_util = require("mpp_util")
local coord_convert, coord_revert = mpp_util.coord_convert, mpp_util.coord_revert
local miner_direction, opposite = mpp_util.miner_direction, mpp_util.opposite
local mpp_revert = mpp_util.revert

---@class CompactLayout : SimpleLayout
local layout = table.deepcopy(base)

layout.name = "super_compact"
layout.translation = {"mpp.settings_layout_choice_super_compact"}

layout.restrictions.miner_near_radius = {1, 1}
layout.restrictions.miner_far_radius = {2, 10e3}
layout.restrictions.pole_omittable = true
layout.restrictions.pole_width = {1, 1}
layout.restrictions.pole_length = {5, 10e3}
layout.restrictions.pole_supply_area = {2.5, 10e3}
layout.restrictions.lamp_available = false

layout.on_load = simple.on_load

-- Validate the selection
---@param self SimpleLayout
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

layout.start = simple.start
layout.process_grid = simple.process_grid

---@param state SimpleState
---@return PlacementAttempt
local function placement_attempt(state, shift_x, shift_y)
	local grid = state.grid
	local size, near, far = state.miner.size, state.miner.near, state.miner.far
	local neighbor_sum = 0
	local far_neighbor_sum = 0
	local miners, postponed = {}, {}
	local miner_score, postponed_score = 0, 0
	
	---@param tile GridTile
	local function heuristic(tile) return tile.neighbor_count > 2 end
	
	local function miner_stagger(start_x, start_y, direction, stagger_step)
		local miner_index = 1
		for y = 1 + shift_y + start_y, state.coords.th + 2, size * 3 + 1 do
			for x = 1 + shift_x + start_x, state.coords.tw + 2, size * 2 do
				local tile = grid:get_tile(x, y)
				local center = grid:get_tile(x+near, y+near)
				local miner = {
					tile = tile,
					center = center,
					direction = direction,
					stagger = stagger_step,
					lane = miner_index,
				}
				if center.far_neighbor_count > 0 then
					if heuristic(center) then
						miners[#miners+1] = miner
					else
						postponed[#postponed+1] = miner
					end
				end
			end
			miner_index = miner_index + 1
		end
	end

	miner_stagger(0, -2, "south", 1)
	miner_stagger(3, 0, "west", 1)
	miner_stagger(0, 2, "north", 1)

	-- the redundant calculation makes it easier to find the stagger offset
	miner_stagger(0+size, -2+size+2, "south", 2)
	miner_stagger(3-size, 0+size+2, "west", 2)
	miner_stagger(0+size, 2+size+2, "north", 2)

	return {
		sx=shift_x, sy=shift_y,
		miners = miners,
		postponed = postponed,
	}
end

---@param attempt PlacementAttempt
---@param miner MinerStruct
local function attempt_score_heuristic(attempt, miner)
	return #attempt.miners + #attempt.postponed * 3
end

---@param self CompactLayout
---@param state SimpleState
function layout:init_first_pass(state)
	local m = state.miner
	local attempts = {{-m.near, -m.near}}
	attempts[1] = {0, 0}
	state.attempts = attempts
	state.best_attempt_index = 1
	state.attempt_index = 2 -- first attempt is used up
	local ext_behind, ext_forward = -m.far, m.far-m.near
	
	for sy = ext_behind, ext_forward do
		for sx = ext_behind, ext_forward do
			if not (sx == -m.near and sy == -m.near) then
				attempts[#attempts+1] = {sx, sy}
			end
		end
	end

	state.best_attempt = placement_attempt(state, attempts[1][1], attempts[1][2])
	state.best_attempt_score = attempt_score_heuristic(state.best_attempt, state.miner)

	state.delegate = "first_pass"
end

---Bruteforce the best solution
---@param self CompactLayout
---@param state SimpleState
function layout:first_pass(state)
	local attempt_state = state.attempts[state.attempt_index]
	---@type PlacementAttempt
	local current_attempt = placement_attempt(state, attempt_state[1], attempt_state[2])
	local current_attempt_score = attempt_score_heuristic(current_attempt, state.miner)

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

---@param self CompactLayout
---@param state SimpleState
function layout:place_miners(state)
	local c = state.coords
	local g = state.grid
	local surface = state.surface
	local DIR = state.direction_choice

	for _, miner in ipairs(state.best_attempt.miners) do
		local center = miner.center
		g:build_miner(center.x, center.y)
		local tile = g:get_tile(center.x, center.y)
		local x, y = coord_revert[state.direction_choice](center.x, center.y, c.tw, c.th)

		local miner_dir = opposite[DIR]
		if miner.direction == "north" or miner.direction == "south" then
			miner_dir = miner_direction[state.direction_choice]
			if miner.direction == "north" then
				miner_dir = opposite[miner_dir]
			end
		end

		surface.create_entity{
			raise_built=true,
			name="entity-ghost",
			player=state.player,
			force = state.player.force,
			position = {c.gx + x, c.gy + y},
			direction = defines.direction[miner_dir],
			inner_name = state.miner_choice,
		}
		
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
			text=miner.lane * 2 + miner.stagger - 2,
			target={c.gx + tx, c.gy + ty},
			vertical_alignment = "bottom",
			alignment = "center",
		}

		--]]
	end

	state.delegate = "placement_belts"
end

---@param self CompactLayout
---@param state SimpleState
function layout:placement_belts(state)
	local c = state.coords
	local m = state.miner
	local g = state.grid
	local DIR = state.direction_choice
	local surface = state.surface
	local attempt = state.best_attempt
	local underground_belt = game.entity_prototypes[state.belt_choice].related_underground_belt.name

	local power_poles = {}
	state.power_poles_all = power_poles
	
	---@type table<number, MinerPlacement[]>
	local miner_lanes = {{}}
	local miner_lane_number = 0 -- highest index of a lane, because using # won't do the job if a lane is missing

	for _, miner in ipairs(attempt.miners) do
		local index = miner.lane * 2 + miner.stagger - 2
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
				g:get_tile(belt_start-sx, y).built_on = "belt"
				surface.create_entity{
					raise_built=true,
					name="entity-ghost",
					player=state.player,
					force=state.player.force,
					position=mpp_revert(c.gx, c.gy, DIR, belt_start-sx, y, c.tw, c.th),
					direction=defines.direction[state.direction_choice],
					inner_name=state.belt_choice,
				}
			end
		else
			-- underground exit
			g:get_tile(shift_x-1, y).built_on = "belt"
			surface.create_entity{
				raise_built=true,
				name="entity-ghost",
				player=state.player,
				force=state.player.force,
				position=mpp_revert(c.gx, c.gy, DIR, shift_x-1, y, c.tw, c.th),
				direction=defines.direction[state.direction_choice],
				inner_name=underground_belt,
				type="output",
			}
			g:get_tile(shift_x+m.size+1, y).built_on = "belt"
			surface.create_entity{
				raise_built=true,
				name="entity-ghost",
				player=state.player,
				force=state.player.force,
				position=mpp_revert(c.gx, c.gy, DIR, shift_x+m.size+1, y, c.tw, c.th),
				direction=defines.direction[state.direction_choice],
				inner_name=underground_belt,
				type="input",
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
			local miner1 = g:get_tile(x, y-1)
			local miner2 = g:get_tile(x, y+1)
			local miner3 = g:get_tile(x+3, y)
			local built = miner1.built_on == "miner" or miner2.built_on == "miner"
			local capped = miner3.built_on == "miner"
			local pole_built = built or capped
			local last = x + m.size * 2 > end_x

			if last and not capped then
				-- last passtrough and no trailing miner
				g:get_tile(x+1, y).built_on = "belt"
				surface.create_entity{
					raise_built=true,
					name="entity-ghost",
					player=state.player,
					force=state.player.force,
					position=mpp_revert(c.gx, c.gy, DIR, x+1, y, c.tw, c.th),
					direction=defines.direction[state.direction_choice],
					inner_name=state.belt_choice,
				}
			elseif capped or built then
				g:get_tile(x+1, y).built_on = "belt"
				surface.create_entity{
					raise_built=true,
					name="entity-ghost",
					player=state.player,
					force=state.player.force,
					position=mpp_revert(c.gx, c.gy, DIR, x+1, y, c.tw, c.th),
					direction=defines.direction[state.direction_choice],
					inner_name=underground_belt,
					type="output",
				}
				g:get_tile(x+m.size*2, y).built_on = "belt"
				surface.create_entity{
					raise_built=true,
					name="entity-ghost",
					player=state.player,
					force=state.player.force,
					position=mpp_revert(c.gx, c.gy, DIR, x+m.size*2, y, c.tw, c.th),
					direction=defines.direction[state.direction_choice],
					inner_name=underground_belt,
					type="input",
				}
			else
				for sx = 1, 6 do
					g:get_tile(x+sx, y).built_on = "belt"
					surface.create_entity{
						raise_built=true,
						name="entity-ghost",
						player=state.player,
						force=state.player.force,
						position=mpp_revert(c.gx, c.gy, DIR, x+sx, y, c.tw, c.th),
						direction=defines.direction[state.direction_choice],
						inner_name=state.belt_choice,
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
		if lane then
			local y = m.size + shift_y - 1 + (m.size + 2) * (i-1)
			local x_start = stagger_shift % 2 == 0 and 3 or 0
			place_belts(x_start, lane.last_x, y)
		end
		stagger_shift = stagger_shift + 1
	end

	state.delegate = "placement_pole"
end

---@param self CompactLayout
---@param state SimpleState
function layout:placement_pole(state)
	if state.pole_choice == "none" then
		state.delegate = "placement_landfill"
		return
	end
	local c = state.coords
	local m = state.miner
	local g = state.grid
	local DIR = state.direction_choice
	local surface = state.surface
	local attempt = state.best_attempt
	for _, pole in ipairs(state.power_poles_all) do
		local x, y = pole.x, pole.y
		if pole.built then
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

	state.delegate = "placement_landfill"
end

layout.placement_landfill = simple.placement_landfill
layout.finish = simple.finish

return layout
