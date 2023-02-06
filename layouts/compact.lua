local floor, ceil = math.floor, math.ceil
local min, max = math.min, math.max

local common = require("layouts.common")
local base = require("layouts.base")
local simple = require("layouts.simple")
local mpp_util = require("mpp_util")
local builder = require("builder")
local coord_convert, coord_revert = mpp_util.coord_convert, mpp_util.coord_revert
local miner_direction, opposite = mpp_util.miner_direction, mpp_util.opposite
local mpp_revert = mpp_util.revert
local EAST, NORTH, SOUTH, WEST = mpp_util.directions()

---@class CompactLayout : SimpleLayout
local layout = table.deepcopy(base)

layout.name = "compact"
layout.translation = {"mpp.settings_layout_choice_compact"}

layout.restrictions.miner_near_radius = {1, 1}
layout.restrictions.miner_far_radius = {1, 10e3}
layout.restrictions.uses_underground_belts = true
layout.restrictions.pole_omittable = true
layout.restrictions.pole_width = {1, 1}
layout.restrictions.pole_length = {7.5, 10e3}
layout.restrictions.pole_supply_area = {2.5, 10e3}
layout.restrictions.coverage_tuning = true
layout.restrictions.lamp_available = true
layout.restrictions.module_available = true
layout.restrictions.pipe_available = true

layout.on_load = simple.on_load
layout.start = simple.start
layout.process_grid = simple.process_grid

---@param miner MinerStruct
local function miner_heuristic(miner, coverage)
	local near, far = miner.near, miner.far
	local full, size = miner.full_size, miner.size
	local neighbor_cap = ceil((size ^ 2) * 0.5)
	if coverage then
		---@param tile GridTile
		return function(tile)
			local nearc, farc = tile.neighbor_count, tile.far_neighbor_count
			return nearc and (nearc > 0 or
				(farc and farc > neighbor_cap and nearc > (size * near))
			)
		end
	end
	---@param tile GridTile
	return function(tile)
		local nearc, farc = tile.neighbor_count, tile.far_neighbor_count
		return nearc and (nearc > neighbor_cap or
			(farc and farc > neighbor_cap and nearc > (size * near))
		)
	end
end

---@param state SimpleState
---@return PlacementAttempt
local function placement_attempt(state, shift_x, shift_y)
	local grid = state.grid
	local size, near, far = state.miner.size, state.miner.near, state.miner.far
	local fullsize = state.miner.full_size
	local neighbor_sum = 0
	local far_neighbor_sum = 0
	local simple_density = 0
	local real_density = 0
	local miners, postponed = {}, {}
	local row_index = 1
	local lane_layout = {}
	
	local heuristic = miner_heuristic(state.miner, state.coverage_choice)
	
	for ry = 1 + shift_y, state.coords.th + near, size + 0.5 do
		local y = ceil(ry)
		local column_index = 1
		lane_layout[#lane_layout+1] = {y = y+near, row_index = row_index}
		for x = 1 + shift_x, state.coords.tw, size do
			local tile = grid:get_tile(x, y)
			local center = grid:get_tile(x+near, y+near)
			local miner = {
				tile = tile,
				line = row_index,
				column = column_index,
				center = center,
			}
			if heuristic(center) then
				miners[#miners+1] = miner
				neighbor_sum = neighbor_sum + center.neighbor_count
				far_neighbor_sum = far_neighbor_sum + center.far_neighbor_count
				real_density = real_density + center.far_neighbor_count / (fullsize ^ 2)
				simple_density = simple_density + center.neighbor_count / (size ^ 2)
			elseif center.far_neighbor_count > 0 then
				postponed[#postponed+1] = miner
			end
			column_index = column_index + 1
		end
		row_index = row_index + 1
	end
	
	-- second pass
	for _, miner in ipairs(miners) do
		grid:consume(miner.center.x, miner.center.y)
	end

	for _, miner in ipairs(postponed) do
		local center = miner.center
		miner.unconsumed = grid:get_unconsumed(center.x, center.y)
	end

	table.sort(postponed, function(a, b)
		if a.unconsumed == b.unconsumed then
			return a.center.far_neighbor_count > b.center.far_neighbor_count
		end
		return a.unconsumed > b.unconsumed
	end)
	
	local postponed_count = 0
	for _, miner in ipairs(postponed) do
		local center = miner.center
		local unconsumed_count = grid:get_unconsumed(center.x, center.y)
		if unconsumed_count > 0 then
			neighbor_sum = neighbor_sum + center.neighbor_count
			far_neighbor_sum = far_neighbor_sum + center.far_neighbor_count
			simple_density = simple_density + center.neighbor_count / (size ^ 2)
			real_density = real_density + center.far_neighbor_count / (fullsize ^ 2)

			grid:consume(center.x, center.y)
			miners[#miners+1] = miner
			miner.postponed = true
			postponed_count = postponed_count + 1
		end
	end
	local unconsumed_sum = 0
	for _, tile in ipairs(state.resource_tiles) do
		if not tile.consumed then unconsumed_sum = unconsumed_sum + 1 end
	end
	
	grid:clear_consumed(state.resource_tiles)

	return {
		sx=shift_x, sy=shift_y,
		miners=miners,
		lane_layout=lane_layout,
		postponed=postponed,
		postponed_count=postponed_count,
		neighbor_sum=neighbor_sum,
		far_neighbor_sum=far_neighbor_sum,
		real_density=real_density,
		simple_density=simple_density,
		density=neighbor_sum / (#miners > 0 and #miners or #postponed),
		far_density=far_neighbor_sum / (#miners > 0 and #miners or #postponed),
	}
end

---@param attempt PlacementAttempt
---@param miner MinerStruct
local function attempt_heuristic_economic(attempt, miner)
	local miner_count = #attempt.miners
	local simple_density = attempt.simple_density
	local real_density = attempt.real_density
	local density_score = attempt.density
	local neighbor_score = attempt.neighbor_sum / (miner.size ^ 2) / 7
	local far_neighbor_score = attempt.far_neighbor_sum / (miner.full_size ^ 2) / 7
	return miner_count - simple_density
end

---@param attempt PlacementAttempt
---@param miner MinerStruct
local function attempt_heuristic_coverage(attempt, miner)
	local miner_count = #attempt.miners
	local simple_density = attempt.simple_density
	local real_density = attempt.real_density
	local density_score = attempt.density
	local neighbor_score = attempt.neighbor_sum / (miner.size ^ 2)
	local far_neighbor_score = attempt.far_neighbor_sum / (miner.full_size ^ 2)
	--local leech_score = attempt.leech_sum / (miner.full_size ^ 2 - miner.size ^ 2)
	--return real_density - miner_count
	--return simple_density + real_density - miner_count
	return simple_density - miner_count
end

local function attempt_score_heuristic(state, miner, coverage)
	if coverage then
		return attempt_heuristic_coverage(state, miner)
	end
	return attempt_heuristic_economic(state, miner)
end

---@param self CompactLayout
---@param state SimpleState
function layout:init_first_pass(state)
	local m = state.miner
	local attempts = {{-m.near, -m.near}}
	state.attempts = attempts
	state.best_attempt_index = 1
	state.attempt_index = 2 -- first attempt is used up
	local ext_behind, ext_forward = -m.far, m.far-m.near
	
	for sy = ext_forward, ext_behind, -1 do
		for sx = ext_forward, ext_behind, -1 do
			if not (sx == -m.near and sy == -m.near) then
				attempts[#attempts+1] = {sx, sy}
			end
		end
	end

	state.best_attempt = placement_attempt(state, attempts[1][1], attempts[1][2])
	state.best_attempt_score = attempt_score_heuristic(state.best_attempt, state.miner, state.coverage_choice)

	return "first_pass"
end

---Bruteforce the best solution
---@param self CompactLayout
---@param state SimpleState
function layout:first_pass(state)
	local attempt_state = state.attempts[state.attempt_index]
	---@type PlacementAttempt
	local current_attempt = placement_attempt(state, attempt_state[1], attempt_state[2])
	local current_attempt_score = attempt_score_heuristic(current_attempt, state.miner, state.coverage_choice)

	if current_attempt_score < state.best_attempt_score  then
		state.best_attempt_index = state.attempt_index
		state.best_attempt = current_attempt
		state.best_attempt_score = current_attempt_score
	end

	if state.attempt_index >= #state.attempts then
		--game.print(("Chose attempt #%i"):format(state.best_attempt_index))
		return "simple_deconstruct"
	end
	state.attempt_index = state.attempt_index + 1
	return true
end

layout.simple_deconstruct = simple.simple_deconstruct
layout.place_miners = simple.place_miners
layout.prepare_pipe_layout = simple.prepare_pipe_layout
layout.place_pipes = simple.place_pipes

---@param self CompactLayout
---@param state SimpleState
function layout:placement_belts(state)
	local pole_proto = game.entity_prototypes[state.pole_choice] or {supply_area_distance=3, max_wire_distance=9}
	local supply_area, wire_reach = 3.5, 9
	if pole_proto then
		supply_area, wire_reach = pole_proto.supply_area_distance, pole_proto.max_wire_distance
	end

	if supply_area < 3 or wire_reach < 9 then
		state.pole_step = 6
		return "placement_belts_small"
	else
		state.pole_step = 9
		return "placement_belts_large"
	end
end

---@param self CompactLayout
---@param state SimpleState
function layout:placement_belts_small(state)
	local c = state.coords
	local m = state.miner
	local g = state.grid
	local create_entity = builder.create_entity_builder(state)
	local DIR = state.direction_choice
	local surface = state.surface
	local attempt = state.best_attempt
	local belt_choice = state.belt_choice
	local underground_belt = game.entity_prototypes[belt_choice].related_underground_belt.name

	local power_poles = {}
	state.power_poles_all = power_poles

	---@type table<number, MinerPlacement[]>
	local miner_lanes = {}
	local miner_lane_number = 0 -- highest index of a lane, because using # won't do the job if a lane is missing

	for _, miner in ipairs(attempt.miners) do
		local index = miner.line
		miner_lane_number = max(miner_lane_number, index)
		if not miner_lanes[index] then miner_lanes[index] = {} end
		local line = miner_lanes[index]
		line[#line+1] = miner
	end

	for _, lane in ipairs(miner_lanes) do
		table.sort(lane, function(a, b) return a.center.x < b.center.x end)
	end

	---@param lane MinerPlacement[]
	local function get_lane_length(lane) if lane then return lane[#lane].center.x end return 0 end
	---@param lane MinerPlacement[]
	local function get_lane_column(lane) if lane and #lane > 0 then return lane[#lane].column end return 0 end

	local belts = {}
	state.belts = belts

	local function belts_filled(x1, y, w)
		for x = x1, x1 + w do
			create_entity{name=belt_choice, direction=WEST, grid_x=x, grid_y=y, things="belt"}
		end
	end

	for i = 1, miner_lane_number, 2 do
		local lane1 = miner_lanes[i]
		local lane2 = miner_lanes[i+1]

		local y = attempt.sy + m.size * i + ceil(i/2)
		local x0 = attempt.sx + 1
		
		local column_count = max(get_lane_column(lane1), get_lane_column(lane2))
		if column_count == 0 then goto continue_lane end

		local indices = {}
		if lane1 then for _, v in ipairs(lane1) do indices[v.column] = v end end
		if lane2 then for _, v in ipairs(lane2) do indices[v.column] = v end end

		for j = 1, column_count do
			local x1 = x0 + (j-1) * m.size
			if j % 2 == 1 then -- part one
				if indices[j] or indices[j+1] then
					create_entity{
						name=state.belt_choice, thing="belt", grid_x=x1, grid_y=y, direction=WEST,
					}
					local stopper = (j+1 > column_count) and state.belt_choice or underground_belt
					create_entity{
						name=stopper, thing="belt", grid_x=x1+1, grid_y=y, direction=WEST, type="output",
					}
					power_poles[#power_poles+1] = {
						x=x1+3, y=y,
						ix=1+floor(i/2), iy=1+floor(j/2),
						built = true,
					}
				else -- just a passthrough belt
					belts_filled(x1, y, m.size - 1)
				end
			elseif j % 2 == 0 then -- part two
				if indices[j-1] or indices[j] then
					create_entity{
						name=belt_choice, thing="belt", grid_x=x1+2, grid_y=y, direction=WEST,
					}
					create_entity{
						name=underground_belt, thing="belt", grid_x=x1+1, grid_y=y, direction=WEST,
					}
				else -- just a passthrough belt
					belts_filled(x1, y, m.size - 1)
				end
			end
		end
		
		::continue_lane::
	end

	return "placement_pole"
end


---@param self CompactLayout
---@param state SimpleState
function layout:placement_belts_large(state)
	local c = state.coords
	local m = state.miner
	local g = state.grid
	local create_entity = builder.create_entity_builder(state)
	local DIR = state.direction_choice
	local surface = state.surface
	local attempt = state.best_attempt
	local belt_choice = state.belt_choice
	local underground_belt = game.entity_prototypes[belt_choice].related_underground_belt.name

	local power_poles = {}
	state.power_poles_all = power_poles

	---@type table<number, MinerPlacement[]>
	local miner_lanes = {{}}
	local miner_lane_number = 0 -- highest index of a lane, because using # won't do the job if a lane is missing

	for _, miner in ipairs(attempt.miners) do
		local index = miner.line
		miner_lane_number = max(miner_lane_number, index)
		if not miner_lanes[index] then miner_lanes[index] = {} end
		local line = miner_lanes[index]
		line[#line+1] = miner
	end

	for _, lane in pairs(miner_lanes) do
		table.sort(lane, function(a, b) return a.center.x < b.center.x end)
	end

	---@param lane MinerPlacement[]
	local function get_lane_length(lane) if lane and #lane > 0 then return lane[#lane].center.x or 0 end return 0 end
	---@param lane MinerPlacement[]
	local function get_lane_column(lane) if lane and #lane > 0 then return lane[#lane].column or 0 end return 0 end

	local belts = {}
	state.belts = belts

	local function belts_filled(x1, y, w)
		for x = x1, x1 + w do
			create_entity{name=belt_choice, direction=WEST, grid_x=x, grid_y=y, things="belt"}
		end
	end

	for i = 1, miner_lane_number, 2 do
		local lane1 = miner_lanes[i]
		local lane2 = miner_lanes[i+1]

		local y = attempt.sy + m.size * i + ceil(i/2)
		local x0 = attempt.sx + 1
		
		local column_count = max(get_lane_column(lane1), get_lane_column(lane2))
		if column_count == 0 then goto continue_lane end

		local indices = {}
		if lane1 then for _, v in ipairs(lane1) do indices[v.column] = v end end
		if lane2 then for _, v in ipairs(lane2) do indices[v.column] = v end end

		for j = 1, column_count do
			local x1 = x0 + (j-1) * m.size
			if j % 3 == 1 then -- part one
				if indices[j] or indices[j+1] or indices[j+2] then
					create_entity{
						name=belt_choice, grid_x=x1, grid_y=y, things="belt", direction=WEST,
					}

					local stopper = (j+1 > column_count) and state.belt_choice or underground_belt
					create_entity{
						name=stopper, grid_x=x1+1, grid_y=y, things="belt", direction=WEST,
						type="output",
					}
					power_poles[#power_poles+1] = {
						x=x1+3, y=y,
						ix=1+floor(i/2), iy=1+floor(j/2),
						built = true,
					}
				else -- just a passthrough belt
					belts_filled(x1, y, m.size - 1)
				end
			elseif j % 3 == 2 then -- part two
				if indices[j-1] or indices[j] or indices[j+1] then
					create_entity{
						name=underground_belt, grid_x=x1+1, grid_y=y, things="belt", direction=WEST,
						type="input",
					}
					create_entity{
						name=belt_choice, grid_x=x1+2, grid_y=y, things="belt", direction=WEST,
					}
				else -- just a passthrough belt
					belts_filled(x1, y, m.size - 1)
				end
			elseif j % 3 == 0 then
				belts_filled(x1, y, m.size - 1)
			end
		end
		
		::continue_lane::
	end

	return "placement_pole"
end

---@param self CompactLayout
---@param state SimpleState
function layout:placement_pole(state)
	local _next_step = "placement_lamp"
	if state.pole_choice == "none" then
		return _next_step
	end
	local c = state.coords
	local m = state.miner
	local g = state.grid
	local DIR = state.direction_choice
	local surface = state.surface
	local attempt = state.best_attempt
	for _, pole in ipairs(state.power_poles_all) do
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

	return _next_step
end

---@param self CompactLayout
---@param state SimpleState
function layout:placement_lamp(state)
	local _next_step = "placement_landfill"
	if not state.lamp_choice then
		return _next_step
	end

	local c = state.coords
	local grid = state.grid
	local surface = state.surface

	local sx, sy = -1, 0
	local lamp_spacing = true
	if state.pole_step > 7 then lamp_spacing = false end

	for _, pole in ipairs(state.power_poles_all) do
		local x, y = pole.x, pole.y
		local ix, iy = pole.ix, pole.iy
		local tile = grid:get_tile(x+sx, y+sy)
		local skippable_lamp = iy % 2 == 1 and ix % 2 == 1
		if tile and pole.built and (not lamp_spacing or skippable_lamp) then
			tile.built_on = "lamp"
			local tx, ty = coord_revert[state.direction_choice](x + sx, y + sy, c.tw, c.th)
			surface.create_entity{
				raise_built=true,
				name="entity-ghost",
				player=state.player,
				force=state.player.force,
				position={c.gx + tx, c.gy + ty},
				inner_name="small-lamp",
			}
		end
	end

	return _next_step
end

layout.placement_landfill = simple.placement_landfill
layout.finish = simple.finish

return layout
