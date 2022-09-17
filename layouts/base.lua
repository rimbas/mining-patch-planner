local floor, ceil = math.floor, math.ceil
local min, max = math.min, math.max

local mpp_util = require("mpp_util")

---@type Layout
local layout = {}

layout.name = "Base"
layout.translation = {"mpp.settings_layout_choice_base"}

layout.defaults = {}
layout.defaults.miner = "electric-mining-drill"
layout.defaults.belt = "transport-belt"
layout.defaults.pole = "medium-electric-pole"
layout.defaults.logistics = "logistic-chest-passive-provider"

layout.restrictions = {}
layout.restrictions.miner_available = true
layout.restrictions.miner_near_radius = {1, 10e3}
layout.restrictions.miner_far_radius = {1, 10e3}
layout.restrictions.belt_available = true
layout.restrictions.uses_underground_belts = false
layout.restrictions.pole_available = true
layout.restrictions.pole_omittable = true
layout.restrictions.pole_width = {1, 1}
layout.restrictions.pole_length = {5, 10e3}
layout.restrictions.pole_supply_area = {2.5, 10e3}
layout.restrictions.lamp_available = true
layout.restrictions.coverage_tuning = false
layout.restrictions.logistics_available = false
layout.restrictions.landfill_omit_available = true

---Called from script.on_load
---@param self Layout
---@param state State
function layout:on_load(state) end

-- Validate the selection
---@param self Layout
---@param state State
function layout:validate(state)
	local r = self.restrictions
	return true
end

---Layout-specific state initialisation
---@param self Layout
---@param state State
function layout:initialize(state)
	local miner_proto = game.entity_prototypes[state.miner_choice]
	state.miner = mpp_util.miner_struct(miner_proto)
end

---Starting step
---@param self Layout
---@param state State
function layout:start(state)
	state.finished = true
end

---Probably too much indirection at this point
---@param self Layout
---@param state State
function layout:tick(state)
	self[state.delegate](self, state)
	state.tick = state.tick + 1
end

return layout
