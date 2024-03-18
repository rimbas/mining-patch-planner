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
function common.simple_layout_heuristic(heuristic)
	local lane_mult = 1 + ceil(heuristic.lane_count / 2) * 0.05
	local unconsumed = 1 + log(max(1, heuristic.unconsumed), 10)
	local value =
		(heuristic.inner_density + heuristic.empty_space / heuristic.drill_count)
		--* heuristic.centricity
		* lane_mult
		* unconsumed
	return value
end

---@param heuristic HeuristicsBlock
function common.overfill_layout_heuristic(heuristic)
	local lane_mult = 1 + ceil(heuristic.lane_count / 2) * 0.05
	local unconsumed = 1 + log(max(1, heuristic.unconsumed), 10)
	local value =
		heuristic.outer_density
		--* heuristic.centricity
		* lane_mult
		* unconsumed
	return value
end

---@class HeuristicsBlock
--- Values counted per miner placement
---@field inner_neighbor_sum number Sum of resource tiles drills physically cover
---@field outer_neighbor_sum number Sum of all resource tiles drills physically cover
---@field empty_space number Sum of empty tiles drills physically cover
---@field leech_sum number Sum of resources only in the outer reach
---@field postponed_count number Number of postponed drills
---
--- Values calculated after completed layout placement
---@field drill_count number Total number of mining drills
---@field lane_count number Number of lanes
---@field inner_density number Density of tiles physically covered by drills
---@field outer_density number Pseudo (because of overlap) density of all tiles reached by drills
---@field centricity number How centered is the layout in respect to patch bounds, 1 to inf
---@field unconsumed number Unreachable resources count (usually insufficient drill reach)

---@return HeuristicsBlock
function common.init_heuristic_values()
	return {
		inner_neighbor_sum = 0,
		outer_neighbor_sum = 0,
		empty_space = 0,
		leech_sum = 0,
		postponed_count = 0,

		drill_count = 1,
		lane_count = 1,
		inner_density = 1,
		outer_density = 1,
		centricity = -(0/0),
		unconsumed = 0,
	}
end

---@param H HeuristicsBlock
---@param M MinerStruct
---@param tile GridTile
---@param postponed boolean?
function common.add_heuristic_values(H, M, tile, postponed)
	H.inner_neighbor_sum = H.inner_neighbor_sum + tile.neighbors_inner
	H.outer_neighbor_sum = H.outer_neighbor_sum + tile.neighbors_outer
	H.empty_space = H.empty_space + (M.size_sq - tile.neighbors_inner)
	H.leech_sum = H.leech_sum + max(0, tile.neighbors_outer - tile.neighbors_inner)

	if postponed then H.postponed_count = H.postponed_count + 1 end
end

---@param attempt PlacementAttempt
---@param block HeuristicsBlock
---@param coords Coords
function common.finalize_heuristic_values(attempt, block, coords)
	block.drill_count = #attempt.miners
	block.lane_count = #attempt.lane_layout
	block.inner_density = block.inner_neighbor_sum / block.drill_count
	block.outer_density = block.outer_neighbor_sum / block.drill_count
	
	local function centricity(m1, m2, size)
		local center = size / 2
		local drill = m1 + (m2-m1)/2
		return center - drill
	end
	local x = centricity(attempt.sx-1, attempt.bx, coords.w)
	local y = centricity(attempt.sy-1, attempt.by, coords.h)
	block.centricity = 1 + (x * x + y * y) ^ 0.5

	block.unconsumed = attempt.unconsumed
end

---Utility to fill in postponed miners on unconsumed resources
---@param state SimpleState
---@param attempt PlacementAttempt
---@param miners MinerPlacement[]
---@param postponed MinerPlacement[]
function common.process_postponed(state, attempt, miners, postponed)
	local grid = state.grid
	local M = state.miner
	local bx, by = attempt.sx + M.size - 1, attempt.sy + M.size - 1

	for _, miner in ipairs(miners) do
		grid:consume(miner.x+M.extent_negative, miner.y+M.extent_negative, M.area)
		bx, by = max(bx, miner.x + M.size -1), max(by, miner.y + M.size -1)
	end

	for _, miner in ipairs(postponed) do
		miner.unconsumed = grid:get_unconsumed(miner.x+M.extent_negative, miner.y+M.extent_negative, M.area)
		bx, by = max(bx, miner.x + M.size -1), max(by, miner.y + M.size -1)
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
		local unconsumed_count = grid:get_unconsumed(miner.x+M.extent_negative, miner.y+M.extent_negative, M.area)
		if unconsumed_count > 0 then
			common.add_heuristic_values(attempt.heuristics, M, tile, true)

			grid:consume(tile.x+M.extent_negative, tile.y+M.extent_negative, M.area)
			miners[#miners+1] = miner
			miner.postponed = true
			bx, by = max(bx, miner.x + M.size - 1), max(by, miner.y + M.size - 1)
		end
	end
	local unconsumed_sum = 0
	for _, tile in ipairs(state.resource_tiles) do
		if not tile.consumed then unconsumed_sum = unconsumed_sum + 1 end
	end
	attempt.unconsumed = unconsumed_sum
	attempt.bx, attempt.by = bx, by
	
	grid:clear_consumed(state.resource_tiles)
end

local seed
local function get_map_seed()
	if seed then return seed end
	
	local game_exchange_string = game.get_map_exchange_string()
	local map_data = game.parse_map_exchange_string(game_exchange_string)

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
		game.print(string.format("Dumped data to %s ", filename))
		game.write_file("mpp-inspect/"..filename, game.table_to_json(state), false, state.player.index)
	elseif type_ == "lua" then
		game.print(string.format("Dumped data to %s ", filename))
		game.write_file("mpp-inspect/"..filename, serpent.dump(state, {}), false, state.player.index)
	end
end

function common.calculate_patch_slack(state)

end

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

---@param belt BeltStruct
---@param restrictions Restrictions
function common.is_belt_restricted(belt, restrictions)
	return false
		or (restrictions.uses_underground_belts and not belt.related_underground_belt)
end

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

return common
