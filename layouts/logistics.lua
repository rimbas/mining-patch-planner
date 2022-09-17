local floor, ceil = math.floor, math.ceil
local min, max = math.min, math.max

local simple = require("layouts.simple")
local compact = require("layouts.compact")
local mpp_util = require("mpp_util")
local mpp_revert = mpp_util.revert
local pole_grid_mt = require("pole_grid_mt")

---@type SimpleLayout
local layout = table.deepcopy(simple)

layout.name = "logistics"
layout.translation = {"mpp.settings_layout_choice_logistics"}

layout.restrictions.belt_available = false
layout.restrictions.logistics_available = true

---@param self SimpleLayout
---@param state SimpleState
function layout:placement_belts(state)
	local c = state.coords
	local m = state.miner
	local g = state.grid
	local DIR = state.direction_choice
	local surface = state.surface
	local attempt = state.best_attempt

	local power_poles = {}
	state.power_poles_all = power_poles

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

	for _, lane in ipairs(miner_lanes) do
		table.sort(lane, function(a, b) return a.center.x < b.center.x end)
	end
	---@param lane MinerPlacement[]
	local function get_lane_length(lane) if lane then return lane[#lane].center.x end return 0 end
	---@param lane MinerPlacement[]
	local function get_lane_column(lane) if lane and #lane > 0 then return lane[#lane].column or 0 end return 0 end

	local belts = {}
	state.belts = belts

	for i = 1, miner_lane_number, 2 do
		local lane1 = miner_lanes[i]
		local lane2 = miner_lanes[i+1]

		local y = attempt.sy + (m.size + 1) * i
		local x0 = attempt.sx + 1
		
		local column_count = max(get_lane_column(lane1), get_lane_column(lane2))
		local indices = {}
		if lane1 then for _, v in ipairs(lane1) do indices[v.column] = v end end
		if lane2 then for _, v in ipairs(lane2) do indices[v.column] = v end end

		for j = 1, column_count do
			local x = x0 + m.near + m.size * (j-1)
			if indices[j] then
				g:get_tile(x, y).built_on = "belt"
				surface.create_entity{
					raise_built=true,
					name="entity-ghost",
					player=state.player,
					force=state.player.force,
					position=mpp_revert(c.gx, c.gy, DIR, x, y, c.tw, c.th),
					inner_name=state.logistics_choice,
				}
			end
		end
	end

	state.delegate = "placement_poles"
end

return layout
