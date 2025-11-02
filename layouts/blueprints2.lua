local floor, ceil = math.floor, math.ceil
local min, max = math.min, math.max
local table_insert = table.insert

local base = require("layouts.base")
local simple = require("layouts.simple")
local grid_mt = require("mpp.grid_mt")
local mpp_util = require("mpp.mpp_util")
local color = require("mpp.color")
local builder = require("mpp.builder")
local common   = require("layouts.common")
local compatibility = require("mpp.compatibility")
local belt_planner  = require("mpp.belt_planner")
local is_buildable_in_space = compatibility.is_buildable_in_space
local direction_coord = mpp_util.direction_coord

local EAST, NORTH, SOUTH, WEST, ROTATION = mpp_util.directions()

---@param dir defines.direction
---@return defines.direction
local function opposing(dir) return (dir + SOUTH) % ROTATION end

---@class Blueprint2Layout : Layout
local layout = table.deepcopy(base)

---@class Blueprint2State : SimpleState
---@field bp_w number
---@field bp_h number
---@field bp_mining_drills BlueprintEntityEx[]
---@field bp_category_map table<string, GridBuilding>
---@field attempts BpPlacementAttempt[]
---@field attempt_index number
---@field best_attempt BpPlacementAttempt
---@field best_attempt_score number Heuristic value
---@field best_attempt_index number
---@field beacons BpPlacementEnt[]
---@field builder_power_poles BpPlacementEnt[]
---@field lamps BpPlacementEnt[]
---
---@field belt_grid Grid BpBeltPiece grid
---@field all_belts table<BpBeltPiece, true>
---@field belt_exits List<{ [1]: number, [2]: number, belt: BpBeltPiece }>
---@field group_tributaries table<number, number>
---@field entity_output_locations table<number, table<number, true>> Mining drill output locations
---@field drill_output_locations BpDrillOutputLocation
---@field entity_input_locations table<number, table<number, true>> Inserter pickup spots
---@field collected_beacons List<BpPlacementEnt>
---@field collected_containers List<BpPlacementEnt> Entities that can contain items (containers/assemblers)
---@field collected_inserters List<BpPlacementEnt> Entities that transfer items (inserters/loaders)
---@field collected_recyclers List<BpPlacementEnt> Entities that have output (like recyclers)
---@field collected_pipes List<BpPlacementEnt>
---@field collected_power List<BpPlacementEnt>
---@field collected_belts List<BpPlacementEnt>
---@field collected_other List<BpPlacementEnt>
---
---@field builder_all List<GhostSpecification>
---@field builder_index number Progress index of creating entities

layout.name = "blueprints"
layout.translation = {"", "[item=blueprint] ", {"mpp.settings_layout_choice_blueprints"}, "2"}

layout.restrictions.miner_available = false
layout.restrictions.belt_available = false
layout.restrictions.pole_available = false
layout.restrictions.lamp_available = false
layout.restrictions.coverage_tuning = true
layout.restrictions.landfill_omit_available = true
layout.restrictions.start_alignment_tuning = true
layout.restrictions.belt_planner_available = true
layout.restrictions.lane_filling_info_available = true

---Called from script.on_load
---@param self Blueprint2Layout
---@param state Blueprint2State
function layout:on_load(state)
	if state.grid then
		setmetatable(state.grid, grid_mt)
	end
end

---@param self Blueprint2Layout
---@param state Blueprint2State
function layout:validate(state)
	return base.validate(self, state)
end

---@param self Blueprint2Layout
---@param state Blueprint2State
function layout:initialize(state)
	state.miner = mpp_util.miner_struct(state.cache.miner_name, true)
	state.miner_choice = state.cache.miner_name
end

---@param self Blueprint2Layout
---@param state Blueprint2State
function layout:start(state)
	local c = state.coords
	local bp = state.cache

	bp.tw, bp.th = bp.w, bp.h
	local th, tw = c.h, c.w
	if state.direction_choice == "south" or state.direction_choice == "north" then
		th, tw = tw, th
		bp.tw, bp.th = bp.h, bp.w
	end
	c.th, c.tw = th, tw

	state.bp_mining_drills = bp:get_mining_drills()
	state.bp_category_map = bp:get_entity_categories()

	state.entity_output_locations = {}
	state.drill_output_locations = {}
	state.entity_input_locations = {}
	state.collected_beacons = List()
	state.collected_power = List()
	state.collected_belts = List()
	state.collected_inserters = List()
	state.collected_containers = List()
	state.collected_recyclers = List()
	state.collected_pipes = List()
	state.collected_other = List()

	state.builder_all = List()

	return "deconstruct_previous_ghosts"
end

layout.initialize_grid = simple.initialize_grid
layout.preprocess_grid = simple.preprocess_grid
layout.process_grid = simple.process_grid
layout.process_grid_convolution = simple.process_grid_convolution

---@param self Blueprint2Layout
---@param state Blueprint2State
function layout:prepare_layout_attempts(state)
	local c = state.coords
	local bp = state.cache
	---@type BpPlacementAttempt[]
	local attempts = {}
	state.attempts = attempts
	state.best_attempt_index = 1
	state.attempt_index = 1

	local function calc_slack(tw, bw, offset)
		local count = ceil((tw-offset) / (bw))
		local overrun = count * bw - tw + offset
		local start = -ceil(overrun / 2)
		local slack = overrun % 2
		return count, start, slack
	end

	local count_x, start_x, slack_x = calc_slack(c.tw, bp.w, bp.ox)
	local count_y, start_y, slack_y = calc_slack(c.th, bp.h, bp.oy)

	if state.start_choice then
		start_x, slack_x = 0, 0
	end

	attempts[1] = {
		sx = start_x, sy = start_y,
		cx = count_x, cy = count_y,
		slack_x = slack_x, slack_y = slack_y,
		miners = {}, postponed = {},
		other_ents = {},
		s_ix = 0, s_iy = 0, s_ie = 1,
	}

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

	return "layout_attempts"
end

layout.layout_attempts = simple.layout_attempts
layout.layout_attempts_fallback = simple.layout_attempts_fallback


---Overridable CallbackState provider what step to continue after determining best attempt
---@param self SimpleLayout
---@param state SimpleState
---@return CallbackState
function layout:get_post_attempts_callback(state)
	return "collect_entities"
end

function layout:_get_layout_heuristic(state)
	if state.coverage_choice then
		return common.overfill_layout_heuristic
	else
		return common.simple_layout_heuristic
	end
end

---@param self Blueprint2Layout
---@param state Blueprint2State
---@param attempt BpPlacementCoords
---@return BpPlacementAttempt
function layout:_placement_attempt(state, attempt)
	local grid = state.grid
	local bp = state.cache
	local M = state.miner
	local size, area = M.size, M.area
	local entities, num_ents = state.bp_mining_drills, #state.bp_mining_drills
	local sx, sy, countx, county = attempt.sx, attempt.sy, attempt.cx-1, attempt.cy-1
	local bx, by = state.coords.extent_x2 + sx, state.coords.extent_y2 + sx
	local b2x, b2y = state.coords.extent_x1 + sy, state.coords.extent_y1 + sy
	local bpw, bph = bp.w, bp.h
	local heuristic = simple._get_miner_placement_heuristic(self --[[@as SimpleLayout]], state)
	local heuristic_values = common.init_heuristic_values()

	--local debug_draw = drawing(state, true, false)

	-- debug_draw:draw_circle{
	-- 	x = 0,
	-- 	y = 0,
	-- 	color = {0, 0, 0},
	-- 	radius = 0.5,
	-- }
	
	local miners, postponed = attempt.miners, {}
	local s_ix = attempt.s_ix or 0
	local s_iy = attempt.s_iy or 0
	local s_ie = attempt.s_ie or 1
	local progress, progress_cap = 0, 100
	--local ix, iy, ie = s_ix, s_iy, s_ie
	for iy = s_iy, county do
	--while iy <= county do
		local capstone_y = iy == county
		for ix = s_ix, countx do
			--while ix <= countx do
			--for _, ent in pairs(bp.entities) do
			for ie = s_ie, num_ents do
			--while ie <= #entities do
				local ent = entities[ie]
				ie = ie + 1
				local capstone_x = ix == countx
				if (ent.capstone_y and not capstone_y) or (ent.capstone_x and not capstone_x) then
					goto skip_ent
				end

				local ent_struct = mpp_util.entity_struct(ent.name)
				local bpx = ceil(ent.position.x - ent_struct.x)
				local bpy = ceil(ent.position.y - ent_struct.y)
				local x, y = sx + ix * bpw + bpx, sy + iy * bph + bpy
				local tile = grid:get_tile(x, y)

				if not tile or M.name ~= ent.name then goto skip_ent end

				local struct = {
					ent = ent,
					tile = tile,
					x = x, y = y,
					origin_x = x + M.x,
					origin_y = y + M.y,
					line = s_iy,
					column = s_ix,
					direction = ent.direction,
					name = ent.name,
				}
				if tile.forbidden then
					-- no op
				elseif heuristic(tile) then
					miners[#miners+1] = struct
					common.add_heuristic_values(heuristic_values, M, tile)
					bx, by = min(bx, x-1), min(by, y-1)
					b2x, b2y = max(b2x, x + size - 1), max(b2y, y + size - 1)
				else
					postponed[#postponed+1] = struct
				end

				::skip_ent::
			end
			s_ie = 1
		end
		s_ix = 0
	end

	local result = {
		sx = sx,
		sy = sy,
		cx = attempt.cx,
		cy = attempt.cy,
		bx = bx,
		by = by,
		b2x = b2x,
		b2y = b2y,
		miners = miners,
		postponed = postponed,
		lane_layout = {},
		heuristics = heuristic_values,
		heuristic_score = -(0/0),
		price = 0,
	}

	common.finalize_heuristic_values(result, heuristic_values, state.coords)

	return result
end

---@param self Blueprint2Layout
---@param state Blueprint2State
function layout:_get_deconstruction_objects(state)
	return {
		state.builder_miners,
		state.builder_all,
		--state.builder_pipes,
		--state.builder_belts,
		--state.builder_power_poles,
		--state.builder_lamps,
	}
end

---@param self SimpleLayout
---@param state Blueprint2State
---@return CallbackState
function layout:collect_entities(state)
	local grid = state.grid
	local C = state.coords
	local bp = state.cache
	local category_map = state.bp_category_map
	local attempt = state.best_attempt
	local entities, num_ents = bp.entities, #bp.entities
	local sx, sy, countx, county = attempt.sx, attempt.sy, attempt.cx-1, attempt.cy-1
	local bpw, bph = bp.w, bp.h
	local is_space = state.is_space

	--local debug_draw = drawing(state, true, false)

	local collected_beacons = state.collected_beacons
	local collected_inserters = state.collected_inserters
	local collected_power = state.collected_power
	local collected_belts = state.collected_belts
	local collected_other = state.collected_other
	local collected_containers = state.collected_containers
	local collected_recyclers = state.collected_recyclers
	local collected_pipes = state.collected_pipes

	local s_ix = attempt.s_ix or 0
	local s_iy = attempt.s_iy or 0
	local s_ie = attempt.s_ie or 1
	local progress, progress_cap = 0, 1000 * state.performance_scaling
	--local ix, iy, ie = s_ix, s_iy, s_ie
	for iy = s_iy, county do
	--while iy <= county do
		local capstone_y = iy == county
		for ix = s_ix, countx do
		--while ix <= countx do
			--for _, ent in pairs(bp.entities) do
			for ie = s_ie, num_ents do
				local ent = entities[ie]
				local ent_name = ent.name
				if is_space and not is_buildable_in_space(ent_name) then goto skip_ent end
				local ent_category = category_map[ent_name]
				ie = ie + 1
				local capstone_x = ix == countx
				if
					ent_category == "miner"
					or (ent.capstone_y and not capstone_y)
					or (ent.capstone_x and not capstone_x)
				then
					goto skip_ent
				end
				local entity_struct = mpp_util.entity_struct(ent_name)
				local rx, ry, rw, rh = mpp_util.transpose_struct(entity_struct, ent.direction)
				local bpx = ceil(ent.position.x - rx)
				local bpy = ceil(ent.position.y - ry)
				local x, y = sx + ix * bpw + bpx, sy + iy * bph + bpy
				local tile = grid:get_tile(x, y)
				if not tile then goto skip_ent end

				---@type BpPlacementEnt
				local base_collected = {
					tile = tile,
					ent = ent,
					name = ent_name,
					type = entity_struct.type,
					x = x,
					y = y,
					origin_x = x + rx,
					origin_y = y + ry,
					w = rw, h = rh,
					direction = ent.direction,
					quality = ent.quality,
				}

				if ent_category == "beacon" then
					collected_beacons:push(base_collected)
				elseif ent_category == "inserter" then
					collected_inserters:push(base_collected)
				elseif ent_category == "pole" then
					collected_power:push(base_collected)
				elseif ent_category == "belt" then
					collected_belts:push(base_collected)
				elseif ent_category == "container" then
					collected_containers:push(base_collected)
				elseif ent_category == "pipe" then
					collected_pipes:push(base_collected)
				elseif ent_category == "assembler" then
					collected_recyclers:push(base_collected)
				else
					collected_other:push(base_collected)
				end

				progress = progress + 1
				if progress > progress_cap then
					attempt.s_ix, attempt.s_iy, attempt.s_ie = ix, iy, ie
					return true
				end

				::skip_ent::
			end
			s_ie = 1
		end
		s_ix = 0
	end

	return "prepare_miner_layout"
end

local function append_transfer_location(locations, x, y)
	local output_row = locations[y]
	if output_row then
		output_row[x] = true
	else
		locations[y] = {[x] = true}
	end
end

local function append_drill_output_location(locations, x, y, direction)
	local output_row = locations[y]
	if output_row then
		local struct = output_row[x]
		if struct then
			struct[direction] = 1
		else
			output_row[x] = {[direction] = 1}
		end
	else
		locations[y] = {[x] = {[direction] = 1}}
	end
end

---@param self SimpleLayout
---@param state Blueprint2State
---@return CallbackState
function layout:prepare_miner_layout(state)
	local C, M, G = state.coords, state.miner, state.grid

	local builder_miners = {}
	state.builder_miners = builder_miners

	local output_locations = state.entity_output_locations
	local drill_output_locations = state.drill_output_locations

	for _, miner in ipairs(state.best_attempt.miners) do

		G:build_miner(miner.x, miner.y, M.size-1)

		builder_miners[#builder_miners+1] = {
			thing = "miner",
			name = miner.ent.name,
			direction = miner.direction,
			grid_x = miner.origin_x,
			grid_y = miner.origin_y,
			extent_w = M.extent_w,
			extent_h = M.extent_h,
		}

		local output = M.output_rotated[miner.direction]
		-- local output = M.output_rotated[mpp_util.clamped_rotation(miner.direction, M.rotation_bump)]
		local pos_x, pos_y = miner.x + output.x, miner.y + output.y
		append_transfer_location(output_locations, pos_x, pos_y)
		append_drill_output_location(drill_output_locations, pos_x, pos_y, miner.direction)
		
		--[[ debug visualisation - mining drill placement ]]
		local converter = mpp_util.reverter_delegate(state.coords, state.direction_choice)
		local x, y = miner.origin_x, miner.origin_y
		local off = state.miner.size / 2
		rendering.draw_rectangle{
			surface = state.surface,
			filled = false,
			color = miner.postponed and {1, 0, 0} or {0, 1, 0},
			width = 3,
			--target = {c.x1 + x, c.y1 + y},
			left_top = {C.gx+x-off, C.gy + y - off},
			right_bottom = {C.gx+x+off, C.gy + y + off},
		}
		rendering.draw_circle{
			surface = state.surface,
			target = {converter(pos_x+.5, pos_y+.5)},
			filled = false,
			color = {1, 1, 1},
			radius = 0.4, width = 6,
		}
		--]]

	end

	do return false end
	return "prepare_beacon_layout"
end

return layout
