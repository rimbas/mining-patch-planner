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

---@class SimpleState : State
---@field first_pass any
---@field attempts any
---@field attempt_index number
---@field best_attempt PlacementAttempt
---@field resource_tiles GridTile
---@field longest_belt number For pole alignment information
---@field power_poles_all table
---@field pole_step number
---@field miner_lane_count number Miner lane count
---@field miner_max_column number Miner column span

layout.name = "blueprints"
layout.translation = {"mpp.settings_layout_choice_blueprints"}

layout.restrictions.miner_available = false
layout.restrictions.pole_available = false
layout.restrictions.lamp_available = false
layout.restrictions.coverage_tuning = true
layout.restrictions.landfill_omit_available = true

function layout:initialize(state)
	
end

return layout
