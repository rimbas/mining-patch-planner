local floor, ceil = math.floor, math.ceil
local min, max = math.min, math.max

local base = require("layouts.base")
local grid_mt = require("grid_mt")
local pole_grid_mt = require("pole_grid_mt")
local mpp_util = require("mpp_util")
local coord_convert, coord_revert = mpp_util.coord_convert, mpp_util.coord_revert
local miner_direction, opposite = mpp_util.miner_direction, mpp_util.opposite
local mpp_revert = mpp_util.revert

---@class SimpleLayout : Layout
local layout = table.deepcopy(base)

---@class SimpleState : State
---@field first_pass any
---@field attempts PlacementAttempt[]
---@field attempt_index number
---@field best_attempt PlacementAttempt
---@field resourcs LuaEntity[]
---@field resource_tiles GridTile
---@field longest_belt number For pole alignment information
---@field power_poles_all table
---@field pole_step number
---@field miner_lane_count number Miner lane count
---@field miner_max_column number Miner column span
---@field grid Grid

layout.name = "simple"
layout.translation = {"mpp.settings_layout_choice_simple"}

layout.restrictions.miner_near_radius = {1, 10e3}
layout.restrictions.miner_far_radius = {1, 10e3}
layout.restrictions.pole_omittable = true
layout.restrictions.pole_width = {1, 1}
layout.restrictions.pole_length = {5, 10e3}
layout.restrictions.pole_supply_area = {2.5, 10e3}
layout.restrictions.lamp_available = true
layout.restrictions.coverage_tuning = true

---Called from script.on_load
---@param self SimpleLayout
---@param state SimpleState
function layout:on_load(state)
	if state.grid then
		setmetatable(state.grid, grid_mt)
	end
end

-- Validate the selection
---@param self SimpleLayout
---@param state SimpleState
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

---@param self SimpleLayout
---@param state SimpleState
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

	for y = -1-miner.full_size, th + miner.full_size+1 do
		local row = {}
		grid[y] = row
		for x = -1-miner.full_size, tw + miner.full_size+1 do
			--local tx1, ty1 = conv(c.x1, c.y1, c.tw, c.th)
			row[x] = {
				contains_resource = false,
				resources = 0,
				neighbor_count = 0,
				far_neighbor_count = 0,
				x = x, y = y,
				gx = c.x1 + x, gy = c.y1 + y,
				consumed = false,
				built_on = false,
			}
		end
	end

	--[[ debug rendering - bounds
	rendering.draw_rectangle{
		surface=state.surface,
		left_top={state.coords.ix1, state.coords.iy1},
		right_bottom={state.coords.ix1 + c.tw, state.coords.iy1 + c.th},
		filled=false, width=4, color={0, 0, 1, 1},
		players={state.player},
	}

	rendering.draw_rectangle{
		surface=state.surface,
		left_top={state.coords.ix1-miner.full_size-1, state.coords.iy1-miner.full_size-1},
		right_bottom={state.coords.ix1+state.coords.tw+miner.full_size+1, state.coords.iy1+state.coords.th+miner.full_size+1},
		filled=false, width=4, color={0, 0.5, 1, 1},
		players={state.player},
	}
	--]]

	state.grid = setmetatable(grid, grid_mt)
	state.delegate = "process_grid"
end

---@param self SimpleLayout
---@param state SimpleState
function layout:process_grid(state)
	local grid = state.grid
	local DIR = state.direction_choice
	local c = state.coords
	local conv = coord_convert[state.direction_choice]
	local gx, gy = state.coords.gx, state.coords.gy
	local resources = state.resources

	state.resource_tiles = state.resource_tiles or {}
	local resource_tiles = state.resource_tiles

	local convolve_size = state.miner.full_size ^ 2
	local budget, cost = 12000, 0

	local i = state.resource_iter or 1
	while i <= #resources and cost < budget do
		local ent = resources[i]
		local x, y = ent.position.x, ent.position.y
		local tx, ty = conv(x-gx, y-gy, c.w, c.h)
		local tile = grid:get_tile(tx, ty)
		tile.contains_resource = true
		tile.amount = ent.amount
		grid:convolve(tx, ty)
		resource_tiles[#resource_tiles+1] = tile
		cost = cost + convolve_size
		i = i + 1
	end
	state.resource_iter = i

	-- for _, ent in ipairs(resources) do
	-- 	local x, y = ent.position.x, ent.position.y
	-- 	local tx, ty = conv(x-gx, y-gy, c.w, c.h)
	-- 	local tile = grid:get_tile(tx, ty)
	-- 	tile.contains_resource = true
	-- 	tile.amount = ent.amount
	-- 	grid:convolve(tx, ty)
	-- 	resource_tiles[#resource_tiles+1] = tile
	-- end

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
	
	if state.resource_iter >= #state.resources then
		state.delegate = "init_first_pass"
	end
end

---@class MinerPlacement
---@field tile GridTile
---@field center GridTile
---@field line number lane index
---@field column number column index
---@field ent BlueprintEntity|nil

---@class PlacementAttempt
---@field sx number x shift
---@field sy number y shift
---@field miners MinerPlacement[]
---@field postponed MinerPlacement[]
---@field neighbor_sum number
---@field far_neighbor_sum number
---@field density number
---@field unconsumed_count number
---@field simple_density number
---@field real_density number
---@field leech_sum number

---@param miner MinerStruct
local function miner_heuristic(miner, variant)
	local near, far, size, fullsize = miner.near, miner.far, miner.size, miner.full_size

	if variant == "coverage" then
		local neighbor_cap = floor((size ^ 2) * 0.8)
		local leech = (far - near) * fullsize
		---@param center GridTile
		return function(center)
			if center.neighbor_count >= neighbor_cap then return true end
			if center.far_neighbor_count >= leech and center.neighbor_count >= (size * near) then return true end
		end
	elseif variant == "coverage2" then
		local neighbor_cap = floor((size ^ 2) * 0.5)
		local leech = fullsize ^ 2 * 0.5
		---@param center GridTile
		return function(center)
			if center.neighbor_count > 1 then return true end
			--if center.neighbor_count >= neighbor_cap then return true end
			--if center.far_neighbor_count >= leech then return true end
		end
	elseif variant == "coverage3" then
		local neighbor_mult = size ^ 2
		local leech_mult = (fullsize ^ 2 - size ^ 2)
		---@param center GridTile
		return function(center)
			return center.neighbor_count / neighbor_mult >= center.far_neighbor_count / leech_mult
		end
	else
		local neighbor_cap = ceil((size ^ 2) * 0.5)
		local leech = (far - near) * fullsize
		---@param center GridTile
		return function(center)
			if center.neighbor_count > neighbor_cap then return true end
			--if center.far_neighbor_count > leech then return true end
			if center.far_neighbor_count > leech and center.neighbor_count > (size * near) then
				return true
			end
		end
	end
end

---@param state SimpleState
---@return PlacementAttempt
local function placement_attempt(state, shift_x, shift_y)
	local c = state.coords
	local grid = state.grid
	local size, near, far, fullsize = state.miner.size, state.miner.near, state.miner.far, state.miner.full_size
	local neighbor_sum = 0
	local far_neighbor_sum = 0
	local miners, postponed = {}, {}
	local miner_index = 1
	local simple_density = 0
	local real_density = 0
	local leech_sum = 0

	local heuristic
	if state.coverage_choice then
		heuristic = miner_heuristic(state.miner, "coverage2")
	else
		heuristic = miner_heuristic(state.miner)
	end

	for y = 1 + shift_y, state.coords.th + near, size + 1 do
		local column_index = 1
		for x = 1 + shift_x, state.coords.tw + near, size do
			local tile = grid:get_tile(x, y)
			local center = grid:get_tile(x+near, y+near)
			local miner = {
				tile = tile,
				line = miner_index,
				center = center,
				column=column_index,
			}
			if center.far_neighbor_count > 0 and heuristic(center) then
				miners[#miners+1] = miner
				neighbor_sum = neighbor_sum + center.neighbor_count
				far_neighbor_sum = far_neighbor_sum + center.far_neighbor_count
				simple_density = simple_density + center.neighbor_count / (size ^ 2)
				real_density = real_density + center.far_neighbor_count / (fullsize ^ 2)
				leech_sum = max(0, center.far_neighbor_count - center.neighbor_count)
			elseif center.far_neighbor_count > 0 then
				postponed[#postponed+1] = miner
			end
			column_index = column_index + 1
		end
		miner_index = miner_index + 1
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
			leech_sum = leech_sum + max(0, center.far_neighbor_count - center.neighbor_count)

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
		--postponed=postponed,
		postponed={},
		neighbor_sum=neighbor_sum,
		far_neighbor_sum=far_neighbor_sum,
		leech_sum=leech_sum,
		density=neighbor_sum / #miners,
		simple_density=simple_density,
		real_density=real_density,
		far_density=far_neighbor_sum / #miners,
		unconsumed_count=unconsumed_sum,
		postponed_count=postponed_count,
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
	return miner_count - simple_density + attempt.postponed_count
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
	local leech_score = attempt.leech_sum / (miner.full_size ^ 2 - miner.size ^ 2)
	--return real_density - miner_count
	return simple_density - miner_count + real_density
end

local fmt_str = "Attempt #%i (%i,%i) - miners:%i, density %.3f, score %.3f, unc %i"

---@param self SimpleLayout
---@param state SimpleState
function layout:init_first_pass(state)
	local m = state.miner
	local attempts = {{-m.near, -m.near}}
	state.attempts = attempts
	state.best_attempt_index = 1
	state.attempt_index = 2 -- first attempt is used up
	--local ext_behind, ext_forward = -m.far, m.far - m.near
	local ext_behind, ext_forward = -m.far, m.far-m.near
	
	--for sy = ext_behind, ext_forward do
	--	for sx = ext_behind, ext_forward do
	for sy = ext_forward, ext_behind, -1 do
		for sx = ext_forward, ext_behind, -1 do
			if not (sx == -m.near and sy == -m.near) then
				attempts[#attempts+1] = {sx, sy}
			end
		end
	end

	local attempt_heuristic = state.coverage_choice and attempt_heuristic_coverage or attempt_heuristic_economic

	state.best_attempt = placement_attempt(state, attempts[1][1], attempts[1][2])
	state.best_attempt_score = attempt_heuristic(state.best_attempt, state.miner)

	--game.print(fmt_str:format(1, state.best_attempt.sx, state.best_attempt.sy, #state.best_attempt.miners, state.best_attempt.real_density, state.best_attempt_score, state.best_attempt.unconsumed_count))

	state.delegate = "first_pass"
end

---Bruteforce the best solution
---@param self SimpleLayout
---@param state SimpleState
function layout:first_pass(state)
	local attempt_state = state.attempts[state.attempt_index]
	---@type PlacementAttempt
	local current_attempt = placement_attempt(state, attempt_state[1], attempt_state[2])
	local attempt_heuristic = state.coverage_choice and attempt_heuristic_coverage or attempt_heuristic_economic
	local current_attempt_score = attempt_heuristic(current_attempt, state.miner)

	--game.print(fmt_str:format(state.attempt_index, attempt_state[1], attempt_state[2], #current_attempt.miners, current_attempt.real_density, current_attempt_score, current_attempt.unconsumed_count))

	if current_attempt.unconsumed_count == 0 and current_attempt_score < state.best_attempt_score  then
		state.best_attempt_index = state.attempt_index
		state.best_attempt = current_attempt
		state.best_attempt_score = current_attempt_score
	end

	if state.attempt_index >= #state.attempts then
		--game.print(("Chose attempt #%i, %i miners"):format(state.best_attempt_index, #state.best_attempt.miners))
		state.delegate = "simple_deconstruct"
	else
		state.attempt_index = state.attempt_index + 1
	end
end

---@param self SimpleLayout
---@param state SimpleState
function layout:simple_deconstruct(state)
	local c = state.coords
	local m = state.miner
	local player = state.player
	local surface = state.surface

	local deconstructor = global.script_inventory[state.deconstruction_choice and 2 or 1]
	surface.deconstruct_area{
		force=player.force,
		player=player.index,
		area={
			left_top={c.x1-m.size-1, c.y1-m.size-1},
			right_bottom={c.x2+m.size+1, c.y2+m.size+1}
		},
		item=deconstructor,
	}
	state.delegate = "place_miners"
end

---@param self SimpleLayout
---@param state SimpleState
function layout:place_miners(state)
	local c = state.coords
	local g = state.grid
	local surface = state.surface
	for _, miner in ipairs(state.best_attempt.miners) do
		local center = miner.center
		g:build_miner(center.x, center.y)
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
			color = miner.postponed and {1, 0, 0} or {0, 1, 0},
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
			raise_built=true,
			name="entity-ghost",
			player=state.player,
			force = state.player.force,
			position = {c.gx + x, c.gy + y},
			direction = defines.direction[direction],
			inner_name = state.miner_choice,
		}
	end

	state.delegate = "placement_belts"
end

---@param self SimpleLayout
---@param state SimpleState
function layout:placement_belts(state)
	local c = state.coords
	local m = state.miner
	local g = state.grid
	local surface = state.surface
	local attempt = state.best_attempt

	---@type table<number, MinerPlacement[]>
	local miner_lanes = {{}}
	local miner_lane_number = 0 -- highest index of a lane, because using # won't do the job if a lane is missing
	local miner_max_column = 0

	for _, miner in ipairs(attempt.miners) do
		local index = miner.line
		miner_lane_number = max(miner_lane_number, index)
		if not miner_lanes[index] then miner_lanes[index] = {} end
		local line = miner_lanes[index]
		line[#line+1] = miner
		miner_max_column = max(miner_max_column, miner.column)
	end
	state.miner_lane_count = miner_lane_number
	state.miner_max_column = miner_max_column

	for _, lane in pairs(miner_lanes) do
		table.sort(lane, function(a, b) return a.center.x < b.center.x end)
	end

	---@param lane MinerPlacement[]
	local function get_lane_length(lane) if lane and lane[#lane] then return lane[#lane].center.x end return 0 end

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
	end
	state.longest_belt = longest_belt

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
	local supply_area, wire_reach = 3, 9
	if pole_proto then
		supply_area, wire_reach = floor(pole_proto.supply_area_distance), pole_proto.max_wire_distance
	end

	--TODO: figure out double lane coverage with insane supply areas
	local function get_covered_miners(ix, iy)
		--for sy = -supply_radius, supply_radius do
		for sy = -supply_area, supply_area, 1 do
			for sx = -supply_area, supply_area, 1 do
				local tile = g:get_tile(ix+sx, iy+sy)
				if tile and tile.built_on == "miner" then
					return true
				end
			end
		end
	end

	---@type PowerPoleGrid
	local power_poles_grid = setmetatable({}, pole_grid_mt)
	local power_poles_all = {}
	state.power_poles_all = power_poles_all

	local coverage = mpp_util.calculate_pole_coverage(state, state.miner_max_column, state.miner_lane_count)

	-- rendering.draw_circle{
	-- 	surface = state.surface,
	-- 	player = state.player,
	-- 	filled = true,
	-- 	color = {1, 1, 1},
	-- 	radius = 0.5,
	-- 	target = mpp_revert(c.gx, c.gy, DIR, attempt.sx, attempt.sy, c.tw, c.th),
	-- }

	local iy = 1
	for y = attempt.sy + coverage.lane_start, c.th + m.size, coverage.lane_step do
		local ix, pole_lane = 1, {}
		for x = 1 + attempt.sx + coverage.pole_start, attempt.sx + coverage.full_miner_width + 1, coverage.pole_step do
			local built = false
			---@type LuaEntity
			local ghost
			if get_covered_miners(x, y) then
				built = true
				g:get_tile(x, y).built_on = "pole"
			end
			local pole = {x=x, y=y, ix=ix, iy=iy, built=built, ghost=ghost}
			power_poles_grid:set_pole(ix, iy, pole)
			power_poles_all[#power_poles_all+1] = pole
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

			ix = ix + 1
		end
		iy = iy + 1
	end

	if state.pole_choice ~= "none" then
		for  _, pole in ipairs(power_poles_all) do
			if pole.built then
				local x, y = pole.x, pole.y
				g:get_tile(x, y).built_on = "pole"
				local ghost = surface.create_entity{
					raise_built=true,
					name="entity-ghost",
					player=state.player,
					force=state.player.force,
					position=mpp_revert(c.gx, c.gy, DIR, x, y, c.tw, c.th),
					inner_name=state.pole_choice,
				}
				--ghost.disconnect_neighbour()
				pole.ghost = ghost
			end
		end
	end

	state.delegate = "placement_lamp"
end

---@param self SimpleLayout
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
	if state.pole_choice == "none" then sx = 0 end

	for _, pole in ipairs(state.power_poles_all) do
		local x, y = pole.x, pole.y
		local ix, iy = pole.ix, pole.iy
		local tile = grid:get_tile(x+sx, y+sy)
		if tile and pole.built and not pole.no_light then
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

---@param self SimpleLayout
---@param state SimpleState
function layout:placement_landfill(state)
	local c = state.coords
	local m = state.miner
	local grid = state.grid
	local surface = state.surface

	if state.landfill_choice then
		state.delegate = "finish"
		return
	end

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
				raise_built=true,
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

---@param self SimpleLayout
---@param state SimpleState
function layout:finish(state)
	state.finished = true
end

return layout
