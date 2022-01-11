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

layout.name = "Simple"

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

-- "t" prefix next to coordinates means transposed coordinate
local coord_convert = {}
coord_convert.west = function(x, y, w, h) return x, y end
coord_convert.east = function(x, y, w, h) return w-x+1, h-y+1 end
coord_convert.north = function(x, y, w, h) return h-y+1, x end
coord_convert.south = function(x, y, w, h) return y, w-x+1 end

-- Validate the selection
---@param self Layout
---@param state State
function layout:validate(state)
	local c = state.coords

	if (state.direction_choice == "west" or state.direction_choice == "east") then
		if c.h < 7 then
			return nil, {"mpp.msg_miner_err_1_w", 7}
		end
	else
		if c.w < 7 then
			return nil, {"mpp.msg_miner_err_1_h", 7}
		end
	end
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
	local attempts = {{0, 0}}
	state.attempts = attempts
	state.best_attempt_index = 1
	state.attempt_index = 2 -- first attempt is used up
	local m = state.miner
	--local ext_behind, ext_forward = -m.far, m.far - m.near
	local ext_behind, ext_forward = -m.far, m.far-m.near
	
	for sy = ext_behind, ext_forward do
		for sx = ext_behind, ext_forward do
			if not (sx == 0 and sy == 0) then
				attempts[#attempts+1] = {sx, sy}
			end
		end
	end

	state.best_attempt = placement_attempt(state, attempts[1][1], attempts[1][2])
	state.best_attempt_score = attempt_score_heuristic(state.best_attempt, state.miner)

	local current_attempt = state.best_attempt
	--game.print(fmt_str:format(1, attempts[1][1], attempts[1][2], #current_attempt.miners, #current_attempt.postponed, current_attempt.neighbor_sum, current_attempt.density, state.best_attempt_score))

	state.delegate = "first_pass"
	--state.delegate = "second_pass"
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

	state.delegate = "miner_placement"
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
function layout:miner_placement(state)
	local c = state.coords
	local surface = state.surface
	for _, miner in ipairs(state.best_attempt.miners) do
		local center = miner.center
		local x, y = center.x, center.y
		local tx, ty = coord_revert[state.direction_choice](x, y, c.tw, c.th)
		x, y = tx, ty
		-- local can_place = surface.can_place_entity{
		-- 	name=state.miner.name,
		-- 	force = state.player.force,
		-- 	position={center.gx, center.gy},
		-- 	direction = defines.direction.north,
		-- 	build_check_type = 
		-- }

		--[[ debug visualisation - miner placement ]]
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

		-- surface.create_entity{
		-- 	name="entity-ghost",
		-- 	player=state.player,
		-- 	force = state.player.force,
		-- 	position = {c.x1 + tx, c.y1 + ty},
		-- 	inner_name = state.miner_choice,
		-- }
	end

	for _, miner in ipairs(state.best_attempt.postponed) do
		local center = miner.center
		local x, y = center.x, center.y
		local tx, ty = coord_revert[state.direction_choice](x, y, c.tw, c.th)
		x, y = tx, ty

		local off = state.miner.size / 2 - 0.1
		rendering.draw_rectangle{
			surface = state.surface,
			filled = false,
			color = {1, 0, 0},
			width = 3,
			--target = {c.x1 + x, c.y1 + y},
			left_top = {c.gx+x-off, c.gy + y - off},
			right_bottom = {c.gx+x+off, c.gy + y + off},
		}

	end

	state.delegate = "finish"
end

---@param self Layout
---@param state State
function layout:finish(state)
	state.finished = true
end

return layout

