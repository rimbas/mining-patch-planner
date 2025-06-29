local mpp_util = require("mpp.mpp_util")

local common = {}

local floor, ceil = math.floor, math.ceil
local min, max = math.min, math.max
local sqrt, log = math.sqrt, math.log

---@alias HeuristicMinerPlacement fun(tile: GridTile): boolean

---@param miner MinerStruct
---@return HeuristicMinerPlacement
function common.simple_miner_placement(miner)
	local size, area = miner.size, miner.area
	local neighbor_cap = (size / 2) ^ 2

	return function(tile)
		return tile.neighbors_inner > neighbor_cap
		-- return tile.neighbor_count > neighbor_cap or tile.far_neighbor_count > leech
	end
end

---@param miner MinerStruct
---@return HeuristicMinerPlacement
function common.overfill_miner_placement(miner)
	local size, area = miner.size, miner.area
	local neighbor_cap = (size/ 2) ^ 2 - 1
	local leech = (area * 0.5) ^ 2 - 1

	return function(tile)
		return tile.neighbors_inner > 0 or tile.neighbors_outer > leech
	end
end

---@param heuristic HeuristicsBlock
---@param miner MinerStruct
function common.simple_layout_heuristic(heuristic, miner)
	local lane_mult = 1 + ceil(heuristic.lane_count / 2) * 0.05
	-- local unconsumed = 1 + log(max(1, heuristic.unconsumed), 10)
	local consumerism = 1 / log(heuristic.outer_neighbor_sum + 1, 10)
	local centricity = 1 + (heuristic.centricity / miner.size * 0.5)
	local value = 1
		-- (heuristic.inner_density + heuristic.empty_space / heuristic.drill_count)
		* heuristic.inner_sum_deviation
		* heuristic.outer_neighbor_sum
		* centricity
		* lane_mult
		-- * unconsumed
	return value
end

---@param heuristic HeuristicsBlock
---@param miner MinerStruct
function common.overfill_layout_heuristic(heuristic, miner)
	local lane_mult = 1 + ceil(heuristic.lane_count / 2) * 0.05
	-- local unconsumed = 1 + log(max(1, heuristic.unconsumed), 10)
	local empty_space = heuristic.empty_space / heuristic.drill_count
	local centricity = 1 + (heuristic.centricity / miner.size * 0.5)
	local value = 1
		* heuristic.outer_density
		* heuristic.resource_sum_deviation
		* centricity
		-- * empty_space
		* lane_mult
		-- * unconsumed
	return value
end

---@class HeuristicsBlock
--- Values counted per miner placement
---@field resource_sum number
---@field inner_neighbor_sum number Sum of resource tiles drills physically cover
---@field outer_neighbor_sum number Sum of all resource tiles drills physically cover
---@field empty_space number Sum of empty tiles drills physically cover
---@field leech_sum number Sum of resources only in the outer reach
---@field postponed_count number Number of postponed drills
---@field biggest_resource number Biggest resource tile found
---
--- Values calculated after completed layout placement
---@field drill_count number Total number of mining drills
---@field lane_count number Number of lanes
---@field inner_density number Density of tiles physically covered by drills
---@field outer_density number Pseudo (because of overlap) density of all tiles reached by drills
---@field centricity number Distance from center of mining drill bounds
---@field unconsumed number Unreachable resources count (usually insufficient drill reach)
---@field resource_sum_deviation number
---@field outer_sum_deviation number
---@field inner_sum_deviation number

---@return HeuristicsBlock
function common.init_heuristic_values()
	return {
		resource_sum = 0,
		biggest_resource = 0,
		inner_neighbor_sum = 0,
		outer_neighbor_sum = 0,
		empty_space = 0,
		leech_sum = 0,
		postponed_count = 0,

		drill_count = 1,
		lane_count = 1,
		inner_density = 1,
		outer_density = 1,
		centricity = 0,
		unconsumed = 0,
	}
end

---@param H HeuristicsBlock
---@param M MinerStruct
---@param tile GridTile
---@param postponed boolean?
function common.add_heuristic_values(H, M, tile, postponed)
	H.resource_sum = H.resource_sum + tile.neighbors_amount
	H.inner_neighbor_sum = H.inner_neighbor_sum + tile.neighbors_inner
	H.outer_neighbor_sum = H.outer_neighbor_sum + tile.neighbors_outer
	H.empty_space = H.empty_space + (M.size_sq - tile.neighbors_inner)
	H.leech_sum = H.leech_sum + max(0, tile.neighbors_outer - tile.neighbors_inner)
	H.biggest_resource = max(H.biggest_resource, tile.amount)

	if postponed then H.postponed_count = H.postponed_count + 1 end
end

---@param attempt PlacementAttempt
---@param block HeuristicsBlock
---@param coords Coords
function common.finalize_heuristic_values(attempt, block, coords)
	local count = block.drill_count
	local biggest = block.biggest_resource
	block.drill_count = #attempt.miners
	block.lane_count = #attempt.lane_layout
	block.inner_density = block.inner_neighbor_sum / block.drill_count
	block.outer_density = block.outer_neighbor_sum / block.drill_count
	
	local function centricity(m1, m2, size)
		local center = size / 2
		local drill = m1+(m2-m1-1)/2
		return center - drill
	end
	local x = centricity(attempt.sx, attempt.bx, coords.w)
	local y = centricity(attempt.sy, attempt.by, coords.h)
	block.centricity = (x * x + y * y) ^ 0.5

	local resource_sum_deviation, resource_sum_avg = 0, block.resource_sum / biggest / count
	local outer_sum_deviation, outer_sum_avg = 0, block.outer_neighbor_sum / biggest / count
	local inner_sum_deviation, inner_sum_avg = 0, block.inner_density / biggest / count
	
	for _, miner in ipairs(attempt.miners) do
		resource_sum_deviation = resource_sum_deviation + (miner.tile.neighbors_amount / biggest - resource_sum_avg) ^ 2
		outer_sum_deviation = outer_sum_deviation + (miner.tile.convolve_outer / biggest - outer_sum_avg) ^ 2
		inner_sum_deviation = inner_sum_deviation + (miner.tile.convolve_inner / biggest - inner_sum_avg) ^ 2
	end
	block.resource_sum_deviation = (resource_sum_deviation / count) ^ 0.5
	block.outer_sum_deviation = (outer_sum_deviation / count) ^ 0.5
	block.inner_sum_deviation = (inner_sum_deviation / count) ^ 0.5
end

---Utility to fill in postponed miners on unconsumed resources
---@param state SimpleState
---@param attempt PlacementAttempt
---@param miners MinerPlacement[]
---@param postponed MinerPlacement[]
---@return number #Cost of operation
function common.process_postponed(state, attempt, miners, postponed)
	local price = 0
	local grid = state.grid
	local M = state.miner
	local bx, by = attempt.bx, attempt.by

	local ext_negative, ext_positive = M.extent_negative, M.extent_positive
	local area, size = M.area, M.size
	local area_sq = M.area_sq
	
	local consume_cache = {}
	
	for _, miner in ipairs(miners) do
		-- grid:consume(miner.x+ext_negative, miner.y+ext_negative, area)
		grid:consume_separable_horizontal(miner.x+ext_negative, miner.y+ext_negative, area, consume_cache)
		-- bx, by = max(bx, miner.x + size - 1), max(by, miner.y + size - 1)
		price = price + area
	end

	for tile, _ in pairs(consume_cache) do
		grid:consume_separable_vertical(tile.x, tile.y, area)
	end
	
	for _, miner in ipairs(postponed) do
		miner.unconsumed = grid:get_unconsumed(miner.x+ext_negative, miner.y+ext_negative, area)
		-- bx, by = max(bx, miner.x + size -1), max(by, miner.y + size -1)
		price = price + area
	end

	table.sort(postponed, function(a, b)
		if a.unconsumed == b.unconsumed then
			local atile, btile = a.tile, b.tile
			if atile.neighbors_outer == btile.neighbors_outer then
				return atile.neighbors_inner > btile.neighbors_inner
			end
			return atile.neighbors_outer > btile.neighbors_outer
		end
		return a.unconsumed > b.unconsumed
	end)

	for _, miner in ipairs(postponed) do
		local tile = miner.tile
		local unconsumed_count = grid:get_unconsumed(miner.x+ext_negative, miner.y+ext_negative, area)
		if unconsumed_count > 0 then
			common.add_heuristic_values(attempt.heuristics, M, tile, true)

			grid:consume(tile.x+ext_negative, tile.y+ext_negative, area)
			price = price + area_sq
			miners[#miners+1] = miner
			miner.postponed = true
			-- bx, by = max(bx, miner.x + size - 1), max(by, miner.y + size - 1)
		end
	end
	local unconsumed_sum = 0
	for _, tile in ipairs(state.resource_tiles) do
		if not tile.consumed then unconsumed_sum = unconsumed_sum + 1 end
	end
	attempt.heuristics.unconsumed = unconsumed_sum
	-- attempt.bx, attempt.by = bx, by
	
	-- grid:clear_consumed(state.resource_tiles)
	
	return price + #state.resource_tiles
end

local seed
local function get_map_seed()
	if seed then return seed end
	
	local game_exchange_string = game.get_map_exchange_string()
	local map_data = helpers.parse_map_exchange_string(game_exchange_string)

	local seed_number = map_data.map_gen_settings.seed
	seed = string.format("%x", seed_number)
	return seed
end

---Dump state to json for inspection
---@param state SimpleState
function common.save_state_to_file(state, type_)

	local c = state.coords
	local gx, gy = floor(c.gx), floor(c.gy)
	local dir = state.direction_choice

	local coverage = state.coverage_choice and "t" or "f"
	local filename = string.format("layout_%s_%i;%i_%s_%i_%s_%s_%x.%s", get_map_seed(), gx, gy, state.miner_choice, #state.resources, dir, coverage, game.tick, type_)

	if type_ == "json" then
		state._previous_state = nil
		game.print(string.format("Dumped data to %s ", filename))
		helpers.write_file("mpp-inspect/"..filename, helpers.table_to_json(state), false, state.player.index)
	elseif type_ == "lua" then
		game.print(string.format("Dumped data to %s ", filename))
		helpers.write_file("mpp-inspect/"..filename, serpent.dump(state, {}), false, state.player.index)
	end
end

function common.calculate_patch_slack(state)

end

---Determines if mining drill is restricted by the layout
---@param miner MinerStruct
---@param restrictions Restrictions
---@return boolean
function common.is_miner_restricted(miner, restrictions)
	return false
		or miner.size < restrictions.miner_size[1]
		or restrictions.miner_size[2] < miner.size
		or miner.radius < restrictions.miner_radius[1]
		or restrictions.miner_radius[2] < miner.radius
end

---Determines if transport belt is restricted by the layout
---@param belt BeltStruct
---@param restrictions Restrictions
function common.is_belt_restricted(belt, restrictions)
	return false
		or (restrictions.uses_underground_belts and not belt.related_underground_belt)
end

---Determines if power pole is restricted by the layout
---@param pole PoleStruct
---@param restrictions Restrictions
function common.is_pole_restricted(pole, restrictions)
	return false
		or pole.size < restrictions.pole_width[1]
		or restrictions.pole_width[2] < pole.size
		or pole.supply_area_distance < restrictions.pole_supply_area[1]
		or restrictions.pole_supply_area[2] < pole.supply_area_distance
		or pole.wire < restrictions.pole_length[1]
		or restrictions.pole_length[2] < pole.wire
end


local triangles = {
	west={
		{{-.6, 0}, {.6, -0.6}, {.6, 0.6}},
		{{-.4, 0}, {.5, -0.45}, {.5, 0.45}},
	},
	east={
		{{.6, 0}, {-.6, -0.6}, {-.6, 0.6}},
		{{.4, 0}, {-.5, -0.45}, {-.5, 0.45}},
	},
	north={
		{{0, -.6}, {-.6, .6}, {.6, .6}},
		{{0, -.4}, {-.45, .5}, {.45, .5}},
	},
	south={
		{{0, .6}, {-.6, -.6}, {.6, -.6}},
		{{0, .4}, {-.45, -.5}, {.45, -.5}},
	},
}
local alignment = {
	west={"center", "center"},
	east={"center", "center"},
	north={"left", "right"},
	south={"right", "left"},
}

local bound_alignment = {
	west="right",
	east="left",
	north="center",
	south="center",
}

---Draws a belt lane overlay
---@param state State
---@param belt BeltSpecification
function common.draw_belt_lane(state, belt)
	local r = state._render_objects
	local c, ttl, player = state.coords, 0, {state.player}
	local x1, y1, x2, y2 = belt.x_start, belt.y, math.max(belt.x1+2, belt.x2), belt.y
	local function l2w(x, y) -- local to world
		return mpp_util.revert(c.gx, c.gy, state.direction_choice, x, y, c.tw, c.th)
	end
	local c1, c2, c3 = {.9, .9, .9}, {0, 0, 0}, {.4, .4, .4}
	local w1, w2 = 4, 10
	if not belt.lane1 and not belt.lane2 then c1 = c3 end
	
	r[#r+1] = rendering.draw_line{ -- background main line
		surface=state.surface, players=player, only_in_alt_mode=true,
		width=w2, color=c2, time_to_live=ttl or 1,
		from=l2w(x1, y1), to=l2w(x2+.5, y1),
	}
	r[#r+1] = rendering.draw_line{ -- background vertical cap
		surface=state.surface, players=player, only_in_alt_mode=true,
		width=w2, color=c2, time_to_live=ttl or 1,
		from=l2w(x2+.5, y1-.6), to=l2w(x2+.5, y2+.6),
	}
	r[#r+1] = rendering.draw_polygon{ -- background arrow
		surface=state.surface, players=player, only_in_alt_mode=true,
		width=w2, color=c2, time_to_live=ttl or 1,
		target=l2w(x1, y1),
		vertices=triangles[state.direction_choice][1],
	}
	r[#r+1] = rendering.draw_line{ -- main line
		surface=state.surface, players=player, only_in_alt_mode=true,
		width=w1, color=c1, time_to_live=ttl or 1,
		from=l2w(x1-.2, y1), to=l2w(x2+.5, y1),
	}
	r[#r+1] = rendering.draw_line{ -- vertical cap
		surface=state.surface, players=player, only_in_alt_mode=true,
		width=w1, color=c1, time_to_live=ttl or 1,
		from=l2w(x2+.5, y1-.5), to=l2w(x2+.5, y2+.5),
	}
	r[#r+1] = rendering.draw_polygon{ -- arrow
		surface=state.surface, players=player, only_in_alt_mode=true,
		width=0, color=c1, time_to_live=ttl or 1,
		target=l2w(x1, y1),
		vertices=triangles[state.direction_choice][2],
	}
end

---Draws a belt lane overlay
---@param state State
---@param belt BeltSpecification
function common.draw_belt_stats(state, belt, belt_speed, speed1, speed2)
	local r = state._render_objects
	local c, ttl, player = state.coords, 0, {state.player}
	local x1, y1, x2, y2 = belt.x_start, belt.y, belt.x2, belt.y
	local function l2w(x, y) -- local to world
		return mpp_util.revert(c.gx, c.gy, state.direction_choice, x, y, c.tw, c.th)
	end
	local c1, c2, c3, c4 = {.9, .9, .9}, {0, 0, 0}, {.9, 0, 0}, {.4, .4, .4}
	
	local ratio1 = speed1
	local ratio2 = speed2
	local function get_color(ratio)
		return ratio > 1.01 and c3 or ratio == 0 and c4 or c1
	end
	local function cap_prod(speed)
		return min(1, speed) * belt_speed, speed > 1 and  "+" or ""
	end
	
	r[#r+1] = rendering.draw_text{
		surface=state.surface, players=player, only_in_alt_mode=true,
		color=get_color(ratio1), time_to_live=ttl or 1,
		alignment=alignment[state.direction_choice][1], vertical_alignment="middle",
		target=l2w(x1-2, y1-.6), scale=1.6,
		text=string.format("%.2f%s /s", cap_prod(ratio1))
	}
	r[#r+1] = rendering.draw_text{
		surface=state.surface, players=player, only_in_alt_mode=true,
		color=get_color(ratio2), time_to_live=ttl or 1,
		alignment=alignment[state.direction_choice][2], vertical_alignment="middle",
		target=l2w(x1-2, y1+.6), scale=1.6,
		text=string.format("%.2f%s /s", cap_prod(ratio2))
	}
	local total_ratio = min(1, ratio1) + min(1, ratio2)
	local total_color = c1
	if ratio1 > 1 or ratio2 > 1 then
		total_color = c3
	end
	local accomodation = c.is_horizontal and -5.5 or -3.5
	r[#r+1] = rendering.draw_text{
		surface=state.surface, players=player, only_in_alt_mode=true,
		color=total_color, time_to_live=ttl or 1,
		alignment="center", vertical_alignment="middle",
		target=l2w(x1+accomodation, y1), scale=2,
		text=string.format("%.2f%s /s", min(2, total_ratio) * belt_speed, (ratio1>1 or ratio2>1) and  "+" or "")
	}
end

---Draws a belt lane overlay
---@param state State
---@param pos_x number
---@param pos_y number
---@param speed number Belt speed
---@param capped1 number
---@param capped2 number
---@param uncapped1 number
---@param uncapped2 number
function common.draw_belt_total(state, pos_x, pos_y, speed, capped1, capped2, uncapped1, uncapped2)
	local r = state._render_objects
	local c, ttl, player = state.coords, 0, {state.player}
	local function l2w(x, y, b) -- local to world
		if ({south=true, north=true})[state.direction_choice] then
			x = x + (b and -.5 or .5)
			y = y + (b and -.5 or .5)
		end
		return mpp_util.revert(c.gx, c.gy, state.direction_choice, x, y, c.tw, c.th)
	end
	local c1 = {0.7, 0.7, 1.0}

	local lower_bound = math.min(capped1, capped2)
	local upper_bound = math.max(capped1, capped2)
	local capped_total = capped1+capped2
	local uncapped_total = uncapped1 + uncapped2
	local unused_capacity = uncapped_total - capped_total

	r[#r+1] = rendering.draw_text{
		surface=state.surface, players=player, only_in_alt_mode=true,
		color=c1, time_to_live=ttl or 1,
		alignment="center", vertical_alignment="middle",
		target=l2w(pos_x-4, pos_y-.6, false), scale=2,
		-- text={"mpp.msg_print_info_lane_saturation_belts", string.format("%.2fx", upper_bound), },
		text = {"mpp.msg_print_info_lane_throuput_total", ("%.2f"):format(capped_total*speed), ceil(upper_bound)},
	}
	if unused_capacity > 0 then
		local color = unused_capacity > capped_total * .1 and {.9, 0, 0} or {1, 1, 1}
		r[#r+1] = rendering.draw_text{
			surface=state.surface, players=player, only_in_alt_mode=true,
			color=color, time_to_live=ttl or 1,
			alignment="center", vertical_alignment="middle",
			target=l2w(pos_x-4, pos_y+.6, true), scale=2,
			-- text={"mpp.msg_print_info_lane_saturation_bounds", string.format("%.2fx", lower_bound), string.format("%.2fx", upper_bound)},
			text = {"mpp.msg_print_info_lane_throuput_unused", ("%.2f"):format(unused_capacity*speed)},
		}
	end
end

---@param state SimpleState
---@return number
function common.get_mining_drill_production(state)
	local drill_speed = prototypes.entity[state.miner_choice].mining_speed
	local belt_speed = prototypes.entity[state.belt_choice].belt_speed * 60 * 4
	local dominant_resource = state.resource_counts[1].name
	local resource_hardness = prototypes.entity[dominant_resource].mineable_properties.mining_time or 1
	local drill_productivity, module_speed = 1, 1
	if state.miner.uses_force_mining_productivity_bonus then
		drill_productivity = drill_productivity + state.player.force.mining_drill_productivity_bonus
	end
	local function quality_clamp(val, level) return floor((val + val * .3 * level) * 100)/100 end
	if state.module_choice ~= "none" then
		local mod = prototypes.item[state.module_choice]
		local level = prototypes.quality[state.module_quality_choice].level
		local speed = mod.module_effects.speed and mod.module_effects.speed or 0
		local productivity = mod.module_effects.productivity and mod.module_effects.productivity or 0
		if mod.category == "speed" then
			speed = quality_clamp(speed, level)
		elseif mod.category == "productivity" then
			productivity = quality_clamp(productivity, level)
		end
		module_speed = module_speed + speed * state.miner.module_inventory_size
		drill_productivity = drill_productivity + productivity * state.miner.module_inventory_size
	end
	local multiplier = drill_speed / resource_hardness * module_speed * drill_productivity
	return multiplier
end

---@class BeltThroughput
---@field lane1 number
---@field lane2 number
---@field direction defines.direction

---@param state SimpleState
---@param belt BeltSpecification
---@return BeltThroughput
function common.get_belt_throughput(state, belt)
	
end

return common
