local floor, ceil = math.floor, math.ceil
local min, max = math.min, math.max

local compact = require("layouts.super_compact")
local mpp_util = require("mpp_util")
local mpp_revert = mpp_util.revert

---@class CompactLayout
local layout = table.deepcopy(compact)

layout.name = "compact_logistics"
layout.translation = {"mpp.settings_layout_choice_compact_logistics"}

layout.restrictions.lamp_available = false
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

	for _, miner in ipairs(attempt.miners) do
		local index = miner.lane * 2 + miner.stagger - 2
		miner_lane_number = max(miner_lane_number, index)
		if not miner_lanes[index] then miner_lanes[index] = {} end
		local line = miner_lanes[index]
		if miner.center.x > (line.last_x or 0) then
			line.last_x = miner.center.x
			line.last_miner = miner
		end
		line[#line+1] = miner
	end

	local shift_x, shift_y = state.best_attempt.sx, state.best_attempt.sy


	local function place_belts(start_x, end_x, y)
		local belt_start = 1 + shift_x + start_x
		if start_x ~= 0 then
			local miner = g:get_tile(shift_x+m.size, y)
			if miner and miner.built_on == "miner" then
				g:get_tile(shift_x+m.size+1, y).built_on = "belt"
				surface.create_entity{
					raise_built=true,
					name="entity-ghost",
					player=state.player,
					force=state.player.force,
					position=mpp_revert(c.gx, c.gy, DIR, shift_x+m.size+1, y, c.tw, c.th),
					inner_name=state.logistics_choice,
				}
				power_poles[#power_poles+1] = {
					x = shift_x,
					y = y,
					built=true,
				}
			end
		end

		for x = belt_start, end_x, m.size * 2 do
			local miner1 = g:get_tile(x, y-1)
			local miner2 = g:get_tile(x, y+1)
			local miner3 = g:get_tile(x+3, y)
			local built = miner1.built_on == "miner" or miner2.built_on == "miner"
			local capped = miner3.built_on == "miner"
			local pole_built = built or capped

			if capped then
				g:get_tile(x+m.size*2, y).built_on = "belt"
				surface.create_entity{
					raise_built=true,
					name="entity-ghost",
					player=state.player,
					force=state.player.force,
					position=mpp_revert(c.gx, c.gy, DIR, x+m.size*2, y, c.tw, c.th),
					inner_name=state.logistics_choice,
				}
			end
			if built then
				g:get_tile(x+1, y).built_on = "belt"
				surface.create_entity{
					raise_built=true,
					name="entity-ghost",
					player=state.player,
					force=state.player.force,
					position=mpp_revert(c.gx, c.gy, DIR, x+1, y, c.tw, c.th),
					inner_name=state.logistics_choice,
				}
			end

			power_poles[#power_poles+1] = {
				x = x + 2,
				y = y,
				built=pole_built,
			}
		end
	end

	local stagger_shift = 1
	for i = 1, miner_lane_number do
		local lane = miner_lanes[i]
		if lane then
			local y = m.size + shift_y - 1 + (m.size + 2) * (i-1)
			local x_start = stagger_shift % 2 == 0 and 3 or 0
			place_belts(x_start, lane.last_x, y)
		end
		stagger_shift = stagger_shift + 1
	end
	state.delegate = "placement_pole"
end

return layout
