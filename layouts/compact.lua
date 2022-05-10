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

layout.name = "compact"
layout.translation = {"mpp.settings_layout_choice_compact"}

layout.restrictions.miner_near_radius = {1, 1}
layout.restrictions.miner_far_radius = {2, 10e3}
layout.restrictions.uses_underground_belts = true
layout.restrictions.pole_omittable = true
layout.restrictions.pole_width = {1, 1}
layout.restrictions.pole_length = {7.5, 10e3}
layout.restrictions.pole_supply_area = {2.5, 10e3}
layout.restrictions.lamp_available = true

layout.on_load = simple.on_load
layout.start = simple.start
layout.process_grid = simple.process_grid

---@param miner MinerStruct
local function miner_heuristic(miner, variant)
	local near, far, size = miner.near, miner.far, miner.size

	local neighbor_cap = floor((size ^ 2) / far)
	local far_neighbor_cap = floor((far * 2 + 1) ^ 2 / far)

	if variant == "importance" then
		---@param center GridTile
		return function(center)
			if center.neighbor_count > neighbor_cap or (center.far_neighbor_count > far_neighbor_cap and center.neighbor_count > size) then
				return true
			end
		end
	end
	
	---@param center GridTile
	return function(center)
		if center.neighbor_count > neighbor_cap or (center.far_neighbor_count > far_neighbor_cap and center.neighbor_count > size) then
			return true
		end
	end
end

---@param state SimpleState
---@return PlacementAttempt
local function placement_attempt(state, shift_x, shift_y)
	local grid = state.grid
	local size, near, far = state.miner.size, state.miner.near, state.miner.far
	local neighbor_sum = 0
	local far_neighbor_sum = 0
	local miners, postponed = {}, {}
	local miner_index = 1
	
	local heuristic = miner_heuristic(state.miner)
	
	for ry = 1 + shift_y, state.coords.th + near, size + 0.5 do
		local y = ceil(ry)
		local column_index = 1
		for x = 1 + shift_x, state.coords.tw, size do
			local tile = grid:get_tile(x, y)
			local center = grid:get_tile(x+near, y+near)
			local miner = {
				tile = tile,
				line = miner_index,
				column = column_index,
				center = center,
			}
			if heuristic(center) then
				miners[#miners+1] = miner
				neighbor_sum = neighbor_sum + center.neighbor_count
				far_neighbor_sum = far_neighbor_sum + center.far_neighbor_count
			elseif center.far_neighbor_count > 0 then
				postponed[#postponed+1] = miner
			end
			column_index = column_index + 1
		end
		miner_index = miner_index + 1
	end
	
	return {
		sx=shift_x, sy=shift_y,
		miners=miners,
		postponed=postponed,
		neighbor_sum=neighbor_sum,
		far_neighbor_sum=far_neighbor_sum,
		density=neighbor_sum / (#miners > 0 and #miners or #postponed),
		far_density=far_neighbor_sum / (#miners > 0 and #miners or #postponed),
	}
end

---@param attempt PlacementAttempt
---@param miner MinerStruct
local function attempt_score_heuristic(attempt, miner)
	local density_score = attempt.density
	local miner_score = #attempt.miners  + #attempt.postponed * 3
	local neighbor_score = attempt.neighbor_sum / (miner.size * miner.size) / 7
	local far_neighbor_score = attempt.far_neighbor_sum / ((miner.far * 2 + 1) ^ 2) / 2
	return miner_score - density_score - neighbor_score - far_neighbor_score
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
		--game.print(("Chose attempt #%i"):format(state.best_attempt_index))
		state.delegate = "second_pass"
	else
		state.attempt_index = state.attempt_index + 1
	end
end

---@param self CompactLayout
---@param state SimpleState
function layout:second_pass(state)
	local grid = state.grid
	local m = state.miner
	local attempt = state.best_attempt
	
	for _, miner in ipairs(attempt.miners) do
		grid:consume(miner.center.x, miner.center.y)
	end

	for _, miner in ipairs(attempt.postponed) do
		local center = miner.center
		miner.unconsumed = grid:get_unconsumed(center.x, center.y)
	end

	table.sort(attempt.postponed, function(a, b)
		if a.unconsumed == b.unconsumed then
			return a.center.far_neighbor_count > b.center.far_neighbor_count
		end
		return a.unconsumed > b.unconsumed
	end)

	local miners = attempt.miners
	for _, miner in ipairs(attempt.postponed) do
		local center = miner.center
		local unconsumed_count = grid:get_unconsumed(center.x, center.y)
		if unconsumed_count > 0 then
			grid:consume(center.x, center.y)
			miners[#miners+1] = miner
		end
	end

	--[[ debug visualisation - unconsumed tiles
	local c = state.coords
	for k, tile in pairs(state.resource_tiles) do
		if tile.consumed == 0 then
			rendering.draw_circle{
				surface = state.surface,
				filled = false,
				color = {1, 0, 0, 1},
				width = 4,
				target = {c.gx + tile.x, c.gy + tile.y},
				radius = 0.45,
				players={state.player},
			}
		end
	end
	--]]

	state.delegate = "simple_deconstruct"
end

layout.simple_deconstruct = simple.simple_deconstruct

---@param self CompactLayout
---@param state SimpleState
function layout:place_miners(state)
	simple.place_miners(self, state)

	local pole_proto = game.entity_prototypes[state.pole_choice] or {supply_area_distance=3, max_wire_distance=9}
	local supply_area, wire_reach = 3.5, 9
	if pole_proto then
		supply_area, wire_reach = pole_proto.supply_area_distance, pole_proto.max_wire_distance
	end

	if supply_area < 3 or wire_reach < 9 then
		state.pole_step = 6
		state.delegate = "placement_belts_small"
	else
		state.pole_step = 9
		state.delegate = "placement_belts_large"
	end
end

---@param self CompactLayout
---@param state SimpleState
function layout:placement_belts_small(state)
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
	local function get_lane_column(lane) if lane then return lane[#lane].column end return 0 end

	local belts = {}
	state.belts = belts

	for i = 1, miner_lane_number, 2 do
		local lane1 = miner_lanes[i]
		local lane2 = miner_lanes[i+1]

		local y = attempt.sy + m.size * i + ceil(i/2)
		local x0 = attempt.sx + 1
		
		local column_count = max(get_lane_column(lane1), get_lane_column(lane2))
		local indices = {}
		if lane1 then for _, v in ipairs(lane1) do indices[v.column] = v end end
		if lane2 then for _, v in ipairs(lane2) do indices[v.column] = v end end

		if column_count > 0 then
			for j = 1, column_count do
				local x1 = x0 + (j-1) * m.size
				if j % 2 == 1 then -- part one
					if indices[j] or indices[j+1] then
						g:get_tile(x1, y).built_on = "belt"
						surface.create_entity{
							raise_built=true,
							name="entity-ghost",
							player=state.player,
							force=state.player.force,
							position = mpp_revert(c.gx, c.gy, DIR, x1, y, c.tw, c.th),
							direction=defines.direction[DIR],
							inner_name=state.belt_choice,
						}
						g:get_tile(x1+1, y).built_on = "belt"
						local stopper = (j+1 > column_count) and state.belt_choice or underground_belt
						surface.create_entity{
							raise_built=true,
							name="entity-ghost",
							player=state.player,
							force=state.player.force,
							position = mpp_revert(c.gx, c.gy, DIR, x1+1, y, c.tw, c.th),
							direction=defines.direction[DIR],
							inner_name=stopper,
							type="output",
						}
						power_poles[#power_poles+1] = {
							x=x1+3, y=y,
							ix=1+floor(i/2), iy=1+floor(j/2),
							built = true,
						}
					else -- just a passthrough belt
						for x = x1, x1 + m.size - 1 do
							g:get_tile(x, y).built_on = "belt"
							surface.create_entity{
								raise_built=true,
								name="entity-ghost",
								player=state.player,
								force=state.player.force,
								position = mpp_revert(c.gx, c.gy, DIR, x, y, c.tw, c.th),
								direction=defines.direction[DIR],
								inner_name=state.belt_choice,
							}
						end
					end
				elseif j % 2 == 0 then -- part two
					if indices[j-1] or indices[j] then
						g:get_tile(x1+2, y).built_on = "belt"
						surface.create_entity{
							raise_built=true,
							name="entity-ghost",
							player=state.player,
							force=state.player.force,
							position = mpp_revert(c.gx, c.gy, DIR, x1+2, y, c.tw, c.th),
							direction=defines.direction[DIR],
							inner_name=state.belt_choice,
						}
						g:get_tile(x1+1, y).built_on = "belt"
						surface.create_entity{
							raise_built=true,
							name="entity-ghost",
							player=state.player,
							force=state.player.force,
							position = mpp_revert(c.gx, c.gy, DIR, x1+1, y, c.tw, c.th),
							direction=defines.direction[DIR],
							inner_name=underground_belt,
							type="input",
						}
					else -- just a passthrough belt
						for x = x1, x1 + m.size - 1 do
							local tx, ty = coord_revert[DIR](x, y, c.tw, c.th)
							g:get_tile(x, y).built_on = "belt"
							surface.create_entity{
								raise_built=true,
								name="entity-ghost",
								player=state.player,
								force=state.player.force,
								position={c.gx + tx, c.gy + ty},
								direction=defines.direction[DIR],
								inner_name=state.belt_choice,
							}
						end
					end
				end
			end
		end

	end

	state.delegate = "placement_pole"
end


---@param self CompactLayout
---@param state SimpleState
function layout:placement_belts_large(state)
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
	local function get_lane_length(lane) if lane then return lane[#lane].center.x end return 0 end
	---@param lane MinerPlacement[]
	local function get_lane_column(lane) if lane then return lane[#lane].column end return 0 end

	local belts = {}
	state.belts = belts

	for i = 1, miner_lane_number, 2 do
		local lane1 = miner_lanes[i]
		local lane2 = miner_lanes[i+1]

		local y = attempt.sy + m.size * i + ceil(i/2)
		local x0 = attempt.sx + 1
		
		local column_count = max(get_lane_column(lane1), get_lane_column(lane2))
		local indices = {}
		if lane1 then for _, v in ipairs(lane1) do indices[v.column] = v end end
		if lane2 then for _, v in ipairs(lane2) do indices[v.column] = v end end

		if column_count > 0 then
			for j = 1, column_count do
				local x1 = x0 + (j-1) * m.size
				if j % 3 == 1 then -- part one
					if indices[j] or indices[j+1] or indices[j+2] then
						g:get_tile(x1, y).built_on = "belt"
						surface.create_entity{
							raise_built=true,
							name="entity-ghost",
							player=state.player,
							force=state.player.force,
							position = mpp_revert(c.gx, c.gy, DIR, x1, y, c.tw, c.th),
							direction=defines.direction[DIR],
							inner_name=state.belt_choice,
						}
						g:get_tile(x1+1, y).built_on = "belt"
						local stopper = (j+1 > column_count) and state.belt_choice or underground_belt
						surface.create_entity{
							raise_built=true,
							name="entity-ghost",
							player=state.player,
							force=state.player.force,
							position = mpp_revert(c.gx, c.gy, DIR, x1+1, y, c.tw, c.th),
							direction=defines.direction[DIR],
							inner_name=stopper,
							type="output",
						}
						power_poles[#power_poles+1] = {
							x=x1+3, y=y,
							ix=1+floor(i/2), iy=1+floor(j/2),
							built = true,
						}
					else -- just a passthrough belt
						for x = x1, x1 + m.size - 1 do
							g:get_tile(x, y).built_on = "belt"
							surface.create_entity{
								raise_built=true,
								name="entity-ghost",
								player=state.player,
								force=state.player.force,
								position = mpp_revert(c.gx, c.gy, DIR, x, y, c.tw, c.th),
								direction=defines.direction[DIR],
								inner_name=state.belt_choice,
							}
						end
					end
				elseif j % 3 == 2 then -- part two
					if indices[j-1] or indices[j] or indices[j+1] then
						g:get_tile(x1+1, y).built_on = "belt"
						surface.create_entity{
							raise_built=true,
							name="entity-ghost",
							player=state.player,
							force=state.player.force,
							position = mpp_revert(c.gx, c.gy, DIR, x1+1, y, c.tw, c.th),
							direction=defines.direction[DIR],
							inner_name=underground_belt,
							type="input",
						}
						g:get_tile(x1+2, y).built_on = "belt"
						surface.create_entity{
							raise_built=true,
							name="entity-ghost",
							player=state.player,
							force=state.player.force,
							position = mpp_revert(c.gx, c.gy, DIR, x1+2, y, c.tw, c.th),
							direction=defines.direction[DIR],
							inner_name=state.belt_choice,
						}
					else -- just a passthrough belt
						for x = x1, x1 + m.size - 1 do
							local tx, ty = coord_revert[DIR](x, y, c.tw, c.th)
							g:get_tile(x, y).built_on = "belt"
							surface.create_entity{
								raise_built=true,
								name="entity-ghost",
								player=state.player,
								force=state.player.force,
								position={c.gx + tx, c.gy + ty},
								direction=defines.direction[DIR],
								inner_name=state.belt_choice,
							}
						end
					end
				elseif j % 3 == 0 then
					for x = x1, x1 + m.size - 1 do
						local tx, ty = coord_revert[DIR](x, y, c.tw, c.th)
						g:get_tile(x, y).built_on = "belt"
						surface.create_entity{
							raise_built=true,
							name="entity-ghost",
							player=state.player,
							force=state.player.force,
							position={c.gx + tx, c.gy + ty},
							direction=defines.direction[DIR],
							inner_name=state.belt_choice,
						}
					end
				end
			end
		end

	end

	state.delegate = "placement_pole"
end

---@param self CompactLayout
---@param state SimpleState
function layout:placement_pole(state)
	if state.pole_choice == "none" then
		state.delegate = "placement_lamp"
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

	state.delegate = "placement_lamp"
end

---@param self CompactLayout
---@param state SimpleState
function layout:placement_lamp(state)
	if not state.lamp_choice then
		state.delegate = "placement_landfill"
		return
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

	state.delegate = "placement_landfill"
end

layout.placement_landfill = simple.placement_landfill
layout.finish = simple.finish

return layout
