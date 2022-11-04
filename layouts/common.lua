local common = {}

local floor, ceil = math.floor, math.ceil
local min, max = math.min, math.max

---Utility to fill in postponed miners on unconsumed resources
---@param state SimpleState
---@param heuristics PlacementAttempt
---@param miners MinerPlacement[]
---@param postponed MinerPlacement[]
function common.process_postponed(state, heuristics, miners, postponed)
	local grid = state.grid
	local size, near, far, fullsize = state.miner.size, state.miner.near, state.miner.far, state.miner.full_size

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

	for _, miner in ipairs(postponed) do
		local center = miner.center
		local unconsumed_count = grid:get_unconsumed(center.x, center.y)
		if unconsumed_count > 0 then
			heuristics.neighbor_sum = heuristics.neighbor_sum + center.neighbor_count
			heuristics.far_neighbor_sum = heuristics.far_neighbor_sum + center.far_neighbor_count
			heuristics.simple_density = heuristics.simple_density + center.neighbor_count / (size ^ 2)
			heuristics.real_density = heuristics.real_density + center.far_neighbor_count / (fullsize ^ 2)
			heuristics.leech_sum = heuristics.leech_sum + max(0, center.far_neighbor_count - center.neighbor_count)
			heuristics.postponed_count = heuristics.postponed_count + 1

			grid:consume(center.x, center.y)
			miners[#miners+1] = miner
			miner.postponed = true
		end
	end
	local unconsumed_sum = 0
	for _, tile in ipairs(state.resource_tiles) do
		if not tile.consumed then unconsumed_sum = unconsumed_sum + 1 end
	end
	heuristics.unconsumed_count = unconsumed_sum
	
	grid:clear_consumed(state.resource_tiles)
end

return common
