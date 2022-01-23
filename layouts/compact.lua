local floor, ceil = math.floor, math.ceil
local min, max = math.min, math.max

local util = require("util")
local base = require("layouts.base")
local grid_mt = require("grid_mt")

---@type SimpleLayout
local layout = table.deepcopy(base)

layout.name = "compact"
layout.translation = {"mpp.settings_layout_choice_compact"}

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

return layout
