local floor, ceil = math.floor, math.ceil
local min, max = math.min, math.max

local base = require("layouts.base")
local simple = require("layouts.simple")
local grid_mt = require("mpp.grid_mt")
local mpp_util = require("mpp.mpp_util")
local builder = require("mpp.builder")
local common   = require("layouts.common")
local drawing  = require("mpp.drawing")
local coord_convert, coord_revert = mpp_util.coord_convert, mpp_util.coord_revert
local bp_direction = mpp_util.bp_direction

local EAST, NORTH, SOUTH, WEST = mpp_util.directions()

---@class BlueprintLayout : Layout
local layout = table.deepcopy(base)

---@class BlueprintState : SimpleState
---@field bp_w number
---@field bp_h number
---@field bp_mining_drills BlueprintEntityEx[]
---@field bp_category_map table<string, string>
---@field attempts BpPlacementAttempt[]
---@field attempt_index number
---@field best_attempt BpPlacementAttempt
---@field best_attempt_score number Heuristic value
---@field best_attempt_index number
---@field beacons BpPlacementEnt[]
---@field builder_power_poles BpPlacementEnt[]
---@field lamps BpPlacementEnt[]
---
---@field collected_beacons BpPlacementEnt[]
---@field collected_power BpPlacementEnt[]
---@field collected_belts BpPlacementEnt[]
---@field collected_other BpPlacementEnt[]
---
---@field builder_all GhostSpecification[]

--- Coordinate space for the attempt
---@class BpPlacementAttempt : PlacementAttempt
---@field other_ents BpPlacementEnt[]
---@field s_ix number Current blueprint metatile x
---@field s_iy number Current blueprint metatile y
---@field s_ie number Current entity index
---@field sx number x start
---@field sy number y start
---@field cx number number of blueprint repetitions on x axis
---@field cy number number of blueprint repetitions on y axis

---@class BpPlacementEnt
---@field name string
---@field ent BlueprintEntityEx
---@field thing string
---@field tile GridTile Top-left tile
---@field x number Top-left tile coordinate
---@field y number Top-left tile coordinate
---@field origin_x number Grid-independent position for correct in-world placement
---@field origin_y number Grid-independent position for correct in-world placement
---@field direction defines.direction
---@field built boolean

layout.name = "blueprints"
layout.translation = {"", "[item=blueprint] ", {"mpp.settings_layout_choice_blueprints"}}

layout.restrictions.miner_available = false
layout.restrictions.belt_available = false
layout.restrictions.pole_available = false
layout.restrictions.lamp_available = false
layout.restrictions.coverage_tuning = true
layout.restrictions.landfill_omit_available = true
layout.restrictions.start_alignment_tuning = true

---Called from script.on_load
---@param self BlueprintLayout
---@param state BlueprintState
function layout:on_load(state)
	if state.grid then
		setmetatable(state.grid, grid_mt)
	end
end

---@param self BlueprintLayout
---@param state BlueprintState
function layout:validate(state)
	return base.validate(self, state)
end

---@param self BlueprintLayout
---@param state BlueprintState
function layout:initialize(state)
	state.miner = mpp_util.miner_struct(state.cache.miner_name)
	state.miner_choice = state.cache.miner_name
end

---@param self BlueprintLayout
---@param state BlueprintState
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

	state.collected_beacons = {}
	state.collected_power = {}
	state.collected_belts = {}

	state.builder_all = {}

	return "deconstruct_previous_ghosts"
end

layout.initialize_grid = simple.initialize_grid

-- ---@param self BlueprintLayout
-- ---@param state BlueprintState
-- function layout:process_grid(state)
-- 	simple.process_grid(self --[[@as SimpleLayout]], state)
-- 	return "prepare_layout_attempts"
-- end

layout.process_grid = simple.process_grid

---@param self BlueprintLayout
---@param state BlueprintState
function layout:prepare_layout_attempts(state)
	local c = state.coords
	local bp = state.cache
	---@type BpPlacementAttempt[]
	local attempts = {}
	state.attempts = attempts
	state.best_attempt_index = 1
	state.attempt_index = 1

	local function calc_slack(tw, bw, offset)
		local count = ceil(tw / bw)
		local overrun = count * bw - tw - offset
		local start = -ceil(overrun / 2)
		local slack = overrun % 2
		return count, start, slack
	end

	local count_x, start_x, slack_x = calc_slack(c.tw, bp.w, bp.ox)
	local count_y, start_y, slack_y = calc_slack(c.th, bp.h, bp.oy)

	if state.start_choice then
		start_x, slack_x = 0, 0
	end

	-- TODO: make attempts use 
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

	return "init_layout_attempt"
end

---@param self BlueprintLayout
---@param state BlueprintState
---@return BpPlacementAttempt
function layout:_placement_attempt(state, attempt)
	local grid = state.grid
	local bp = state.cache
	local M = state.miner
	local entities, num_ents = state.bp_mining_drills, #state.bp_mining_drills
	local sx, sy, countx, county = attempt.sx, attempt.sy, attempt.cx-1, attempt.cy-1
	local bpw, bph = bp.w, bp.h
	local heuristic = simple._get_miner_placement_heuristic(self --[[@as SimpleLayout]], state)
	local heuristic_values = common.init_heuristic_values()
	
	local debug_draw = drawing(state, true, false)

	-- debug_draw:draw_circle{
	-- 	x = 0,
	-- 	y = 0,
	-- 	color = {0, 0, 0},
	-- 	radius = 0.5,
	-- }

	local miners, postponed = attempt.miners, {}
	local other_ents = attempt.other_ents
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
				
				local struct = mpp_util.entity_struct(ent.name)
				local bpx = ceil(ent.position.x - struct.x)
				local bpy = ceil(ent.position.y - struct.y)
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
				if heuristic(tile) then
					miners[#miners+1] = struct
					common.add_heuristic_values(heuristic_values, M, tile)
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
		sx = sx, sy = sy,
		cx = attempt.cx, cy = attempt.cy,
		miners = miners,
		lane_layout = {},
		heuristics = heuristic_values,
		heuristic_score = -(0/0),
		unconsumed = 0,
	}

	common.process_postponed(state, result, miners, postponed)

	common.finalize_heuristic_values(result, heuristic_values, state.coords)

	return result
end

---@param self BlueprintLayout
---@param state BlueprintState
---@return CallbackState
function layout:init_layout_attempt(state)
	local attempt = state.attempts[state.attempt_index]

	state.best_attempt = self:_placement_attempt(state, attempt)
	state.best_attempt_score = simple._get_layout_heuristic(self --[[@as SimpleLayout]], state)(state.best_attempt.heuristics)
	state.best_attempt.heuristic_score = state.best_attempt_score

	if state.debug_dump then
		state.saved_attempts = {}
		state.saved_attempts[#state.saved_attempts+1] = state.best_attempt
	end

	state.attempt_index = state.attempt_index + 1
	return "layout_attempt"
end

---@param self BlueprintLayout
---@param state BlueprintState
---@return CallbackState
function layout:layout_attempt(state)
	return "collect_entities"
end

---@param self BlueprintLayout
---@param state BlueprintState
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
---@param state BlueprintState
---@return CallbackState
function layout:collect_entities(state)
	local grid = state.grid
	local bp = state.cache
	local category_map = state.bp_category_map
	local attempt = state.best_attempt
	local entities, num_ents = bp.entities, #bp.entities
	local sx, sy, countx, county = attempt.sx, attempt.sy, attempt.cx-1, attempt.cy-1
	local bpw, bph = bp.w, bp.h

	local debug_draw = drawing(state, true, false)

	local collected_beacons = state.collected_beacons
	local collected_power = state.collected_power
	local collected_belts = state.collected_belts
	local collected_other = state.collected_other
	
	local s_ix = attempt.s_ix or 0
	local s_iy = attempt.s_iy or 0
	local s_ie = attempt.s_ie or 1
	local progress, progress_cap = 0, 200
	--local ix, iy, ie = s_ix, s_iy, s_ie
	for iy = s_iy, county do
	--while iy <= county do
		local capstone_y = iy == county
		for ix = s_ix, countx do
		--while ix <= countx do
			--for _, ent in pairs(bp.entities) do
			for ie = s_ie, num_ents do
				local ent = entities[ie]
				local ent_category = category_map[ent.name]
				ie = ie + 1
				local capstone_x = ix == countx
				if
					ent_category == "mining-drill"
					or (ent.capstone_y and not capstone_y)
					or (ent.capstone_x and not capstone_x)
				then
					local asdf = "asdf"
					goto skip_ent
				end
				local entity_struct = mpp_util.entity_struct(ent.name)
				local bpx = ceil(ent.position.x - entity_struct.x)
				local bpy = ceil(ent.position.y - entity_struct.y)
				local x, y = sx + ix * bpw + bpx, sy + iy * bph + bpy
				local tile = grid:get_tile(x, y)
				if not tile then goto skip_ent end

				if ent_category == "beacon" then
					local beacon_struct = mpp_util.beacon_struct(ent.name)
					collected_beacons[#collected_beacons+1] = {
						ent = ent,
						name = ent.name,
						x = x,
						y = y,
						origin_x = x + beacon_struct.x,
						origin_y = y + beacon_struct.y,
						tile = tile,
						thing = "beacon",
						direction = ent.direction,
						built = false,
						extent_negative = beacon_struct.extent_negative,
						w = beacon_struct.w,
						h = beacon_struct.h,
						area = beacon_struct.area,
					}
					local t = true
				elseif ent_category == "transport-belt" then
					collected_belts[#collected_belts+1] = {
						ent = ent,
						thing = "belt",
						name = ent.name,
						x = x, y = y,
					}

				elseif ent_category == "electric-pole" then

				else
					
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

---@param self SimpleLayout
---@param state BlueprintState
---@return CallbackState
function layout:prepare_miner_layout(state)
	local C, M, G = state.coords, state.miner, state.grid

	local builder_miners = {}
	state.builder_miners = builder_miners

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

		--[[ debug visualisation - mining drill placement
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
		--]]

	end

	return "prepare_beacon_layout"
end

---@param self BlueprintLayout
---@param state BlueprintState
function layout:prepare_beacon_layout(state)
	local c = state.coords
	local surface = state.surface
	local grid = state.grid
	local builder_all = state.builder_all

	local debug_draw = drawing(state, true, false)

	for _, beacon in ipairs(state.collected_beacons) do
		local struct = mpp_util.beacon_struct(beacon.name)
		local x, y = beacon.x, beacon.y
		local ext = struct.extent_negative
		local found = grid:find_thing(x+ext, y+ext, "miner", struct.area)

		if found then
			grid:build_thing(x, y, "beacon", struct.w-1, struct.h-1)


			builder_all[#builder_all+1] = {
				thing = "beacon",
				name = struct.name,
				grid_x = beacon.origin_x,
				grid_y = beacon.origin_y,
				extent_w = struct.extent_w,
				extent_h = struct.extent_h,
			}
		end

		if false and grid:find_thing(center.x, center.y, "miner", range+even.near, even[1]) then
			local ex, ey = fix_offgrid(center, ent)
			local x, y = coord_revert[state.direction_choice](ex, ey, c.tw, c.th)
			local target = surface.create_entity{
				raise_built=true,
				name="entity-ghost",
				player=state.player,
				force=state.player.force,
				position= {c.gx + x, c.gy + y},
				direction = other_ent.direction,
				inner_name = ent.name,
				type=ent.type,
			}
			if ent.items then
				target.item_requests = ent.items
			end
			grid:build_thing(center.x, center.y, "beacon", even.near, even[1])
		end

		::continue::
	end

	return "expensive_deconstruct"
end

---@param self BlueprintLayout
---@param state BlueprintState
function layout:prepare_electricity(state)
	local c = state.coords
	local surface = state.surface
	local grid = state.grid

	for _, other_ent in ipairs(state.builder_power_poles) do
		---@type BlueprintEntity
		local ent = other_ent.ent
		local center = other_ent.center
		
		local even = mpp_util.entity_even_width(ent.name)
		local range = floor(game.entity_prototypes[ent.name].supply_area_distance)
		if grid:find_thing_in(center.x, center.y, {"miner", "beacon"}, range, even[1]) then
			local ex, ey = fix_offgrid(center, ent)
			local x, y = coord_revert[state.direction_choice](ex, ey, c.tw, c.th)
			local target = surface.create_entity{
				raise_built=true,
				name="entity-ghost",
				player=state.player,
				force=state.player.force,
				position= {c.gx + x, c.gy + y},
				direction = other_ent.direction,
				inner_name = ent.name,
				type=ent.type,
			}
			if ent.items then
				target.item_requests = ent.items
			end
			grid:build_thing(center.x, center.y, "electricity", even.near, even[1])
		end
	end
	return "finish"
end

---@param self BlueprintLayout
---@param state BlueprintState
function layout:prepare_other(state)
	local c = state.coords
	local grid = state.grid
	local surface = state.surface
	local beacons, power, lamps = {}, {}, {}
	state.beacons, state.builder_power_poles, state.lamps = beacons, power, lamps

	for _, other_ent in ipairs(state.best_attempt.other_ents) do
		break
		---@type BlueprintEntity
		local ent = other_ent.ent
		local ent_type = game.entity_prototypes[ent.name].type

		if ent_type == "beacon" then
			beacons[#beacons+1] = other_ent
			goto continue
		elseif ent_type == "electric-pole" then
			power[#power+1] = other_ent
			goto continue
		--elseif ent_type == "lamp" then
			--lamps[#lamps+1] = other_ent
			--goto continue
		end

		local ex, ey = fix_offgrid(center, ent)
		local x, y = coord_revert[state.direction_choice](ex, ey, c.tw, c.th)
		local target = surface.create_entity{
			raise_built=true,
			name="entity-ghost",
			player=state.player,
			force=state.player.force,
			position= {c.gx + x, c.gy + y},
			direction = other_ent.direction,
			inner_name = ent.name,
			type=ent.type,
			output_priority=ent.output_priority,
			input_priority=ent.input_priority,
			filter=ent.filter,
			filters=ent.filters,
			filter_mode=ent.filter_mode,
			override_stack_size=ent.override_stack_size,
		}

		if ent.items then
			target.item_requests = ent.items
		end

		--[[ debug rendering 
		rendering.draw_circle{
			surface = state.surface,
			player = state.player,
			filled = false,
			color = {0.5,0.5,1,1},
			width=3,
			radius= 0.4,
			target = {c.gx + center.x, c.gy + center.y},
		}
		--]]

		::continue::
	end

	return "prepare_beacons"
end

---@param self BlueprintLayout
---@param state BlueprintState
function layout:expensive_deconstruct(state)
	simple.expensive_deconstruct(self --[[@as SimpleLayout]], state)
	return "placement_miners"
end

---@param self BlueprintLayout
---@param state BlueprintState
---@return CallbackState
function layout:placement_miners(state)
	local create_entity = builder.create_entity_builder(state)
	local M = state.miner

	local module_inv_size = state.miner.module_inventory_size --[[@as uint]]
	local grid = state.grid

	for i, miner in ipairs(state.best_attempt.miners) do

		local ghost = create_entity{
			name = state.miner_choice,
			thing="miner",
			grid_x = miner.origin_x,
			grid_y = miner.origin_y,
			direction = miner.direction,
		}

		if state.module_choice ~= "none" then
			ghost.item_requests = miner.ent.items
		end
	end

	return "placement_all"
end

---@param self BlueprintLayout
---@param state BlueprintState
---@return CallbackState
function layout:placement_all(state)

	local create_entity = builder.create_entity_builder(state)

	for _, thing in pairs(state.builder_all) do

		create_entity(thing)

		::continue::
	end

	return "placement_landfill"
end

layout.placement_landfill = simple.placement_landfill

---@param self BlueprintLayout
---@param state BlueprintState
function layout:finish(state)
	return false
end

return layout
