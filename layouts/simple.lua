local floor, ceil = math.floor, math.ceil
local min, max = math.min, math.max

local util = require("util")
local base = require("layouts.base")
local grid_mt = require("grid_mt")

---@class SimpleLayout : Layout
local layout = table.deepcopy(base)

---@class SimpleState : State
---@field first_pass any
---@field attempts any
---@field attempt_index number
---@field best_attempt PlacementAttempt
---@field resource_tiles GridTile
---@field longest_belt number For pole alignment information
---@field power_poles_all table

layout.name = "simple"
layout.translation = {"mpp.settings_layout_choice_simple"}

layout.restrictions = {}
layout.restrictions.miner_near_radius = {1, 10e3}
layout.restrictions.miner_far_radius = {2, 10e3}
layout.restrictions.pole_omittable = true
layout.restrictions.pole_width = {1, 1}
layout.restrictions.pole_length = {7.5, 10e3}
layout.restrictions.pole_supply_area = {5, 10e3}
layout.restrictions.lamp = true

---Called from script.on_load
---@param self Layout
---@param state State
function layout:on_load(state)
	if state.grid then
		setmetatable(state.grid, grid_mt)
	end
end

local coord_convert = {}
coord_convert.west = function(x, y, w, h) return x, y end
coord_convert.east = function(x, y, w, h) return w-x+1, h-y+1 end
coord_convert.south = function(x, y, w, h) return h-y+1, x end
coord_convert.north = function(x, y, w, h) return y, w-x+1 end

-- Validate the selection
---@param self Layout
---@param state State
function layout:validate(state)
	local c = state.coords
	-- if (state.direction_choice == "west" or state.direction_choice == "east") then
	-- 	if c.h < 7 then
	-- 		return nil, {"mpp.msg_miner_err_1_w", 7}
	-- 	end
	-- else
	-- 	if c.w < 7 then
	-- 		return nil, {"mpp.msg_miner_err_1_h", 7}
	-- 	end
	-- end
	return true
end

---@param self Layout
---@param state State
function layout:start(state)
	local grid = {}
	local miner = state.miner
	local c = state.coords

	grid.miner = miner

	local th, tw = c.h, c.w
	if state.direction_choice == "south" or state.direction_choice == "north" then
		th, tw = tw, th
	end
	c.th, c.tw = th, tw
	local conv = coord_convert[state.direction_choice]

	-- TODO: Rewrite (for performance?) with shift, so table indices starts at 1 instead of less than 1
	for y = -1-miner.size, th + miner.size + miner.far do
		local row = {}
		grid[y] = row
		for x = -1-miner.size, tw + miner.size * 2 do
			--local tx1, ty1 = conv(c.x1, c.y1, c.tw, c.th)
			row[x] = {
				contains_resource = false,
				resources = 0,
				neighbor_count = 0,
				far_neighbor_count = 0,
				x = x, y = y,
				gx = c.x1 + x, gy = c.y1 + y,
				consumed = 0,
				built_on = false,
			}

			--[[ debug visualisation
			rendering.draw_circle{
				surface = state.surface,
				filled = false,
				color = {1, 1, 1},
				width = 1,
				target = {c.gx + x, c.gy + y},
				radius = 0.5,
			}
			rendering.draw_text{
				text=string.format("%i,%i", x, y),
				surface = state.surface,
				color={1,1,1},
				target={c.gx + x, c.gy + y},
				alignment = "center",
			}
			-- ]]
		end
	end

	--[[ debug rendering - bounds ]]
	rendering.draw_rectangle{
		surface=state.surface,
		left_top={state.coords.ix1, state.coords.iy1},
		right_bottom={state.coords.ix1 + c.tw, state.coords.iy1 + c.th},
		filled=false, width=4, color={0, 0, 1, 1},
		players={state.player},
	}

	rendering.draw_rectangle{
		surface=state.surface,
		left_top={state.coords.ix1-miner.size-1, state.coords.iy1-miner.size-1},
		right_bottom={state.coords.ix1+state.coords.tw+miner.size+1, state.coords.iy1+state.coords.th+miner.size+1},
		filled=false, width=4, color={0, 0.5, 1, 1},
		players={state.player},
	}
	--]]

	state.grid = setmetatable(grid, grid_mt)
	state.delegate = "process_grid"
end

---@param self Layout
---@param state State
function layout:process_grid(state)
	local grid = state.grid
	local c = state.coords
	local conv = coord_convert[state.direction_choice]
	local gx, gy = state.coords.gx, state.coords.gy
	local resources = state.resources

	local resource_tiles = {}
	state.resource_tiles = resource_tiles

	for _, ent in ipairs(resources) do
		local x, y = ent.position.x, ent.position.y
		local tx, ty = conv(x-gx, y-gy, c.w, c.h)
		local tile = grid:get_tile(tx, ty)
		tile.contains_resource = true
		tile.amount = ent.amount
		grid:convolve(tx, ty)
		resource_tiles[#resource_tiles+1] = tile
	end

	--[[ debug visualisation - resource and coord
	for _, ent in ipairs(resource_tiles) do
		rendering.draw_circle{
			surface = state.surface,
			filled = false,
			color = {0.3, 0.3, 1},
			width = 1,
			target = {c.gx + ent.x, c.gy + ent.y},
			radius = 0.5,
		}
		rendering.draw_text{
			text=string.format("%i,%i", ent.x, ent.y),
			surface = state.surface,
			color={1,1,1},
			target={c.gx + ent.x, c.gy + ent.y},
			alignment = "center",
		}
	end --]]
	
	state.delegate = "init_first_pass"
end

---@class MinerPlacement
---@field tile GridTile
---@field center GridTile
---@field line number lane index

---@class PlacementAttempt
---@field sx number x shift
---@field sy number y shift
---@field miners MinerPlacement[]
---@field postponed MinerPlacement[]
---@field neighbor_sum number
---@field far_neighbor_sum number
---@field density number

---comment
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

	for y = 1 + shift_y, state.coords.th + size, size + 1 do
		for x = 1 + shift_x, state.coords.tw, size do
			local tile = grid:get_tile(x, y)
			local center = grid:get_tile(x+near, y+near)
			local miner = {
				tile = tile,
				line = miner_index,
				center = center,
			}
			if heuristic(center) then
				miners[#miners+1] = miner
				neighbor_sum = neighbor_sum + center.neighbor_count
				far_neighbor_sum = far_neighbor_sum + center.far_neighbor_count
			elseif center.far_neighbor_count > 0 then
				postponed[#postponed+1] = miner
			end
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


local attempt_score_heuristic

---@param attempt PlacementAttempt
---@param miner MinerStruct
attempt_score_heuristic = function(attempt, miner)
	local density_score = attempt.density
	local miner_score = #attempt.miners  + #attempt.postponed * 3
	local neighbor_score = attempt.neighbor_sum / (miner.size * miner.size) / 7
	local far_neighbor_score = attempt.far_neighbor_sum / ((miner.far * 2 + 1) ^ 2) / 2
	return miner_score - density_score - neighbor_score - far_neighbor_score
end

local fmt_str = "Attempt #%i (%i,%i) - miners:%i (%i), sum %i, density %.3f, score %.3f"

---@param self Layout
---@param state SimpleState
function layout:init_first_pass(state)
	local m = state.miner
	local attempts = {{-m.near, -m.near}}
	state.attempts = attempts
	state.best_attempt_index = 1
	state.attempt_index = 2 -- first attempt is used up
	--local ext_behind, ext_forward = -m.far, m.far - m.near
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
	local current_attempt_score = attempt_score_heuristic(current_attempt, state.miner)

	--game.print(fmt_str:format(state.attempt_index, attempt_state[1], attempt_state[2], #current_attempt.miners, #current_attempt.postponed, current_attempt.neighbor_sum, current_attempt.density, current_attempt_score))

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

---@param self Layout
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

	--[[ debug visualisation - unconsumed tiles ]]
	local grid, c = state.grid, state.coords
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

---@param self Layout
---@param state SimpleState
function layout:simple_deconstruct(state)
	local c = state.coords
	local m = state.miner
	local player = state.player
	local surface = state.surface

	surface.deconstruct_area{
		force=player.force,
		player=player.index,
		area={
			left_top={c.x1-m.size, c.y1-m.size},
			right_bottom={c.x2+m.size, c.y2+m.far}
		},
	}

	state.delegate = "place_miners"
end

local miner_direction = {west="south",east="north",north="west",south="east"}
local opposite = {west="east",east="west",north="south",south="north"}

local coord_revert = {}
coord_revert.west = coord_convert.west
coord_revert.east = coord_convert.east
coord_revert.north = coord_convert.south
coord_revert.south = coord_convert.north

---@param self Layout
---@param state SimpleState
function layout:place_miners(state)
	local c = state.coords
	local g = state.grid
	local surface = state.surface
	for _, miner in ipairs(state.best_attempt.miners) do
		local center = miner.center
		local tile = g:get_tile(center.x, center.y)
		local x, y = coord_revert[state.direction_choice](center.x, center.y, c.tw, c.th)
		-- local can_place = surface.can_place_entity{
		-- 	name=state.miner.name,
		-- 	force = state.player.force,
		-- 	position={center.gx, center.gy},
		-- 	direction = defines.direction.north,
		-- 	build_check_type = 
		-- }

		--[[ debug visualisation - miner placement
		local off = state.miner.size / 2
		rendering.draw_rectangle{
			surface = state.surface,
			filled = false,
			color = {0, 1, 1},
			width = 3,
			--target = {c.x1 + x, c.y1 + y},
			left_top = {c.gx+x-off, c.gy + y - off},
			right_bottom = {c.gx+x+off, c.gy + y + off},
		}
		--]]

		local flip_lane = miner.line % 2 ~= 1
		local direction = miner_direction[state.direction_choice]
		if flip_lane then direction = opposite[direction] end

		surface.create_entity{
			name="entity-ghost",
			player=state.player,
			force = state.player.force,
			position = {c.gx + x, c.gy + y},
			direction = defines.direction[direction],
			inner_name = state.miner_choice,
		}
	end

	-- for _, miner in ipairs(state.best_attempt.postponed) do
	-- 	local center = miner.center
	-- 	local x, y = center.x, center.y
	-- 	local tx, ty = coord_revert[state.direction_choice](x, y, c.tw, c.th)
	-- 	x, y = tx, ty

	-- 	local off = state.miner.size / 2 - 0.1
	-- 	rendering.draw_rectangle{
	-- 		surface = state.surface,
	-- 		filled = false,
	-- 		color = {1, 0, 0},
	-- 		width = 3,
	-- 		--target = {c.x1 + x, c.y1 + y},
	-- 		left_top = {c.gx+x-off, c.gy + y - off},
	-- 		right_bottom = {c.gx+x+off, c.gy + y + off},
	-- 	}

	-- end

	state.delegate = "placement_belts"
end

---@param self Layout
---@param state SimpleState
function layout:placement_belts(state)
	local c = state.coords
	local m = state.miner
	local g = state.grid
	local surface = state.surface
	local attempt = state.best_attempt

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

	local belts = {}
	state.belts = belts
	local longest_belt = 0
	for i = 1, miner_lane_number, 2 do
		local lane1 = miner_lanes[i]
		local lane2 = miner_lanes[i+1]

		local y = attempt.sy + (m.size + 1) * i

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
					name="entity-ghost",
					player=state.player,
					force=state.player.force,
					position={c.gx + tx, c.gy + ty},
					direction=defines.direction[state.direction_choice],
					inner_name=state.belt_choice,
				}
			end
		end
	end
	state.longest_belt = longest_belt

	--local center = miner.center
	--local x, y = coord_revert[state.direction_choice](center.x, center.y, c.tw, c.th)

	state.delegate = "placement_poles"
end

---@param self Layout
---@param state SimpleState
function layout:placement_poles(state)
	local c = state.coords
	local m = state.miner
	local g = state.grid
	local surface = state.surface
	local attempt = state.best_attempt

	local placeholder_pole = state.pole_choice == "none" and "medium-electric-pole" or state.pole_choice
	local pole_proto = game.entity_prototypes[placeholder_pole]
	local supply_area = pole_proto.supply_area_distance
	local supply_radius = floor(supply_area)
	local wire_reach = pole_proto.max_wire_distance

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

	local power_poles_all = {}
	state.power_poles_all = power_poles_all

	local pole_start, pole_step
	if supply_area < 3 or wire_reach < 9 then
		pole_start = 3
		pole_step = 6
	else
		pole_start = (floor(state.longest_belt / 3) % 3 == 0 and 3 or 0) + 2
		pole_step = 9
	end
	state.pole_step = pole_step

	local ix, iy = 1, 1
	for y = attempt.sy, c.th + m.size, m.size * 2 + 2 do
		for x = attempt.sx + pole_start, c.tw + m.near, pole_step do
			local built = false
			if get_covered_miners(x, y) then
				if state.pole_choice ~= "none" then
					g:get_tile(x, y).built_on = "pole"
					built = true
					local tx, ty = coord_revert[state.direction_choice](x, y, c.tw, c.th)
					surface.create_entity{
						name="entity-ghost",
						player=state.player,
						force=state.player.force,
						position={c.gx + tx, c.gy + ty},
						inner_name=state.pole_choice,
					}
				end
			end
			power_poles_all[#power_poles_all+1] = {x=x, y=y, ix=ix, iy=iy, built=built}
			ix = ix + 1
		end
		iy = iy + 1
	end

	state.delegate = "placement_lamp"
end

---@param self Layout
---@param state SimpleState
function layout:placement_lamp(state)
	if not state.lamp_choice or state.lamp_choice == "none" then
		state.delegate = "placement_landfill"
		return
	end

	local c = state.coords
	local grid = state.grid
	local surface = state.surface

	local sx, sy = -1, 0
	if state.pole_choice == "none" then sx = 0 end

	for _, pole in ipairs(state.power_poles_all) do
		local x, y = pole.x, pole.y
		local ix, iy = pole.ix, pole.iy
		local tile = grid:get_tile(x+sx, y+sy)
		if tile and pole.built then
			tile.built_on = "lamp"
			local tx, ty = coord_revert[state.direction_choice](x + sx, y + sy, c.tw, c.th)
			surface.create_entity{
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

---@param self Layout
---@param state SimpleState
function layout:placement_landfill(state)
	local c = state.coords
	local m = state.miner
	local grid = state.grid
	local surface = state.surface

	local conv = coord_convert[state.direction_choice]
	local gx, gy = state.coords.ix1 - 1, state.coords.iy1 - 1

	local resource_tiles = {}
	state.resource_tiles = resource_tiles

	local water_tiles = surface.find_tiles_filtered{
		area={
			left_top={c.x1-m.w-1, c.y1-m.h-1},
			right_bottom={c.x2+m.w+1, c.y2+m.h+1}
		},
		collision_mask="water-tile"
	}

	for _, water in ipairs(water_tiles) do
		local x, y = water.position.x, water.position.y
		x, y = conv(x-gx, y-gy, c.w, c.h)
		local tile = grid:get_tile(x, y)

		if tile and tile.built_on then
			surface.create_entity{
				name="tile-ghost",
				player=state.player,
				force=state.player.force,
				position=water.position,
				inner_name="landfill",
			}
		end
	end

	state.delegate = "finish"
end

---@param self Layout
---@param state SimpleState
function layout:finish(state)
	state.finished = true
end

return layout

