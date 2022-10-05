local floor, ceil = math.floor, math.ceil
local min, max = math.min, math.max

local base = require("layouts.base")
local grid_mt = require("grid_mt")
local pole_grid_mt = require("pole_grid_mt")
local mpp_util = require("mpp_util")
local coord_convert, coord_revert = mpp_util.coord_convert, mpp_util.coord_revert
local bp_direction = mpp_util.bp_direction
local miner_direction, opposite = mpp_util.miner_direction, mpp_util.opposite
local mpp_revert = mpp_util.revert

---@class BlueprintLayout : Layout
local layout = table.deepcopy(base)

---@class BlueprintState : SimpleState
---@field bp_w number
---@field bp_h number
---@field s_ix number
---@field s_iy number

layout.name = "blueprints"
layout.translation = {"mpp.settings_layout_choice_blueprints"}

layout.restrictions.miner_available = false
layout.restrictions.belt_available = false
layout.restrictions.pole_available = false
layout.restrictions.lamp_available = false
layout.restrictions.coverage_tuning = false
layout.restrictions.landfill_omit_available = false

---Called from script.on_load
---@param self SimpleLayout
---@param state SimpleState
function layout:on_load(state)
	if state.grid then
		setmetatable(state.grid, grid_mt)
	end
end

---@param state BlueprintState
function layout:validate(state)
	return true
end

---@param state BlueprintState
function layout:start(state)
	local grid = {}
	local c = state.coords

	local bpw, bph = state.cache.w, state.cache.h
	local th, tw = c.h, c.w
	if state.direction_choice == "south" or state.direction_choice == "north" then
		th, tw = tw, th
		bpw, bph = bph, bpw
	end
	c.th, c.tw = th, tw

	for y = -bph, th+bph do
		local row = {}
		grid[y] = row
		for x = -bpw, tw+bpw do
			row[x] = {
				contains_resource = false,
				resources = 0,
				x = x, y = y,
				gx = c.x1 + x, gy = c.y1 + y,
				consumed = 0,
				built_on = false,
				neighbor_counts = {},
			}
		end
	end

	state.grid = setmetatable(grid, grid_mt)
	state.delegate = "process_grid"
end

---Called from script.on_load
---@param self SimpleLayout
---@param state BlueprintState
function layout:process_grid(state)
	local grid = state.grid
	local resources = state.resources
	local conv = coord_convert[state.direction_choice]
	local gx, gy = state.coords.gx, state.coords.gy
	local gw, gh = state.coords.w, state.coords.h
	local resources = state.resources

	state.resource_tiles = state.resource_tiles or {}
	local resource_tiles = state.resource_tiles

	local convolve_size = 0
	local convolve_steps = {}
	for _, miner in pairs(state.cache.miners) do
		---@cast miner MinerStruct
		convolve_size = miner.far ^ 2 + miner.near ^ 2
		convolve_steps[miner.far] = true
		convolve_steps[miner.near] = true
	end
	local budget, cost = 12000, 0

	local i = state.resource_iter or 1
	while i <= #resources and cost < budget do
	--for i, r in pairs(resources) do
		local r = resources[i]
		local x, y = r.position.x, r.position.y
		local tx, ty = conv(x-gx, y-gy, gw, gh)
		local tile = grid:get_tile(tx, ty)
		tile.contains_resource = true
		tile.amount = r.amount
		for width, _ in pairs(convolve_steps) do
			grid:convolve_custom(tx, ty, width)
		end
		resource_tiles[#resource_tiles+1] = tile
		cost = cost + convolve_size
		i = i + 1
	end
	state.resource_iter = i

	state.delegate = "init_first_pass"
end

---@param self SimpleLayout
---@param state BlueprintState
function layout:init_first_pass(state)
	local c = state.coords
	local bp = state.cache
	local attempts = {}
	state.attempts = attempts
	state.best_attempt_index = 1
	state.attempt_index = 1

	--local slackw = ceil(c.tw / bp.w) * bp.w - c.tw
	local function calc_slack(tw, bw)
		local count = ceil(tw / bw)
		local overrun = count * bw - tw
		local start = -floor(overrun / 2)
		local slack = overrun % 2
		return count, start, slack
	end

	local count_x, start_x, slack_x = calc_slack(c.tw, bp.w)
	local count_y, start_y, slack_y = calc_slack(c.th, bp.h)

	attempts[1] = {
		x = start_x, y = start_y,
		cx = count_x, cy = count_y,
		slack_x = slack_x, slack_y = slack_y,
	}

	state.bp_grid = {}
	for iy = 0, start_y - 1 do
		local row = state.bp_grid[iy]
		for ix = 0, start_x - 1 do
			row[ix] = {completed = false}
		end
	end

	--[[ debug rendering
	rendering.draw_rectangle{
		surface=state.surface,
		left_top={state.coords.ix1, state.coords.iy1},
		right_bottom={state.coords.ix1 + c.tw, state.coords.iy1 + c.th},
		filled=false, width=8, color={0, 0, 1, 1},
		players={state.player},
	}

	for iy = 0, count_y-1 do
		for ix = 0, count_x-1 do
			rendering.draw_rectangle{
				surface=state.surface,
				left_top={
					c.ix1 + start_x + bp.w * ix,
					c.iy1 + start_y + bp.h * iy,
				},
				right_bottom={
					c.ix1 + start_x + bp.w * (ix+1),
					c.iy1 + start_y + bp.h * (iy+1),
				},
				filled=false, width=2, color={0, 0.5, 1, 1},
				players={state.player},
			}
		end
	end
	--]]

	state.delegate = "first_pass"
end

---@param self SimpleLayout
---@param state BlueprintState
function layout:first_pass(state)
	local c = state.coords
	local grid = state.grid
	local bp = state.cache
	local attempt = state.attempts[1]
	local sx, sy, countx, county = attempt.x, attempt.y, attempt.cx, attempt.cy
	local conv = coord_convert[state.direction_choice]
	local rev = coord_revert[state.direction_choice]
	local bpconv = bp_direction[state.direction_choice]
	local bpw, bph = bp.w, bp.h
	if state.direction_choice == "south" or state.direction_choice == "north" then
		bpw, bph = bph, bpw
	end
	
	local miners, postponed = {}, {}
	local other_ents = {}
	state.best_attempt = {
		miners = miners,
		other_ents = other_ents,
	}
	local s_ix = state.s_ix or 0
	local s_iy = state.s_iy or 0
	for iy = s_iy, county-1 do
		local capstone = iy == (county-1)
		for ix = s_ix, countx-1 do
			for _, ent in pairs(bp.entities) do
				if ent.capstone and not capstone then goto skip_ent end
				local bpx, bpy = ceil(ent.position.x), ceil(ent.position.y)
				local x, y = attempt.x + ix * bpw + bpx, attempt.y + iy * bph + bpy
				local tile = grid:get_tile(x, y)
				if not tile then goto skip_ent end
				local bptr = bpconv[ent.direction or defines.direction.north]

				local miner = state.cache.miners[ent.name]
				if state.cache.miners[ent.name] then
					local struct = {
						ent = ent,
						line = s_iy,
						center = tile,
						column = s_ix,
						direction = bptr,
						name = ent.name,
						near = miner.near,
						far = miner.far,
					}
					local count_near = tile.neighbor_counts[miner.near]
					local count_far = tile.neighbor_counts[miner.far]
					if count_near and count_near > 3 then
						miners[#miners+1] = struct
						grid:consume_custom(x, y, miner.far)
					elseif count_far and count_far > 1 then
						postponed[#postponed+1] = struct
					end
				else
					other_ents[#other_ents+1] = {
						ent = ent,
						center = tile,
						x = x, y = y,
						direction = bptr,
					}
				end

				--[[ debug rendering
				rendering.draw_circle{
					surface = state.surface,
					player = state.player,
					filled = false,
					color = {1,1,1,1},
					radius= 0.5,
					target = {c.gx + rx, c.gy + ry},
				}
				--]]
				::skip_ent::
			end
		end
	end

	-- second pass
	for _, miner in ipairs(miners) do
		grid:consume_custom(miner.center.x, miner.center.y, miner.far)
	end

	for _, miner in ipairs(postponed) do
		local center = miner.center
		miner.unconsumed = grid:get_unconsumed_custom(center.x, center.y, miner.far)
	end

	table.sort(postponed, function(a, b)
		if a.unconsumed == b.unconsumed then
			local sizes = mpp_util.keys_to_set(a.center.neighbor_counts, b.center.neighbor_counts)
			for i = #sizes, 1, -1 do
				local size = sizes[i]
				local left, right = a.center.neighbor_counts[size], b.center.neighbor_counts[size]
				if left ~= nil and right ~= nil then
					return left > right
				elseif left ~= nil then
					return true
				end
			end
			return false
		end
		return a.unconsumed > b.unconsumed
	end)

	for _, miner in ipairs(postponed) do
		local center = miner.center
		local unconsumed_count = grid:get_unconsumed_custom(center.x, center.y, miner.far)
		if unconsumed_count > 0 then
			grid:consume_custom(center.x, center.y, miner.near)
			miners[#miners+1] = miner
		end
	end

	state.delegate = "simple_deconstruct"
end

---@param self SimpleLayout
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
			left_top={c.x1-m.size-1, c.y1-m.size-1},
			right_bottom={c.x2+m.size+1, c.y2+m.size+1}
		},
		item=global.script_inventory[1],
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
		g:build_miner_custom(center.x, center.y, miner.near)
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

		surface.create_entity{
			raise_built=true,
			name="entity-ghost",
			player=state.player,
			force = state.player.force,
			position = {c.gx + x, c.gy + y},
			direction = miner.direction,
			inner_name = state.miner_choice,
		}
	end

	state.delegate = "place_other"
end

---@param tile GridTile
---@param ent BlueprintEntity
---@return number
---@return number
local function fix_offgrid(tile, ent)
	local ex, ey = ent.position.x, ent.position.y
	local ox, oy = 0, 0
	if ex == ceil(ex) then ox = 0.5 end
	if ey == ceil(ey) then oy = 0.5 end
	return tile.x + ox, tile.y + oy
end

---@param self SimpleLayout
---@param state SimpleState
function layout:place_other(state)
	local c = state.coords
	local g = state.grid
	local surface = state.surface

	for _, other_ent in ipairs(state.best_attempt.other_ents) do
		---@type BlueprintEntity
		local ent = other_ent.ent
		local center = other_ent.center

		local ex, ey = fix_offgrid(center, ent)
		local x, y = coord_revert[state.direction_choice](ex, ey, c.tw, c.th)
		surface.create_entity{
			raise_built=true,
			name="entity-ghost",
			player=state.player,
			force=state.player.force,
			position= {c.gx + x, c.gy + y},
			direction = other_ent.direction,
			inner_name = ent.name,
		}
	end

	state.delegate = "finish"
end

function layout:finish(state)
	state.finished = true
end

return layout
