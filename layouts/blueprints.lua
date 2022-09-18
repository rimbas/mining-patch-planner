local floor, ceil = math.floor, math.ceil
local min, max = math.min, math.max

local base = require("layouts.base")
local grid_mt = require("grid_mt")
local pole_grid_mt = require("pole_grid_mt")
local mpp_util = require("mpp_util")
local coord_convert, coord_revert = mpp_util.coord_convert, mpp_util.coord_revert
local miner_direction, opposite = mpp_util.miner_direction, mpp_util.opposite
local mpp_revert = mpp_util.revert

---@class BlueprintLayout : Layout
local layout = table.deepcopy(base)

---@class BlueprintState : SimpleState

layout.name = "blueprints"
layout.translation = {"mpp.settings_layout_choice_blueprints"}

layout.restrictions.miner_available = false
layout.restrictions.belt_available = false
layout.restrictions.pole_available = false
layout.restrictions.lamp_available = false
layout.restrictions.coverage_tuning = false
layout.restrictions.landfill_omit_available = false

---@param state BlueprintState
function layout:validate(state)
	return true
end

---@param state BlueprintState
function layout:start(state)
	local grid = {}

	state.finished = true
end

return layout
