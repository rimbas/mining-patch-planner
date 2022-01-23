local floor, ceil = math.floor, math.ceil
local min, max = math.min, math.max

---@class Layout
local layout = {}

layout.name = "Base"
layout.translation = {"mpp.settings_layout_choice_base"}

layout.restrictions = {}
layout.restrictions.miner_near_radius = {1, 10e3}
layout.restrictions.miner_far_radius = {2, 10e3}
layout.restrictions.pole_omittable = true
layout.restrictions.pole_width = {1, 1}
layout.restrictions.pole_length = {7.5, 10e3}
layout.restrictions.pole_supply_area = {5, 10e3}
layout.restrictions.lamp_available = true

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

---@class MinerStruct
---@field name string
---@field size number Physical miner size
---@field w number Miner collision width
---@field h number Miner collision height
---@field far number Far radius
---@field near number Close radius
---@field resource_categories table<string, boolean>

---Layout-specific state initialisation
---@param self Layout
---@param state State
function layout:initialize(state)
	do -- miner setup
		local miner_proto = game.entity_prototypes[state.miner_choice]
		local miner = {}
		miner.far = floor(miner_proto.mining_drill_radius)
		local cbox = miner_proto.collision_box
		local cbox_tl, cbox_br = cbox.left_top, cbox.right_bottom
		local cw, ch = cbox_br.x - cbox_tl.x, cbox_br.y - cbox_tl.y
		miner.w, miner.h = ceil(cw), ceil(ch)
		miner.size = ceil(cw)
		miner.near =  floor(miner.size * 0.5)
		miner.resource_categories = miner_proto.resource_categories
		miner.name = miner_proto.name

		state.miner = miner
	end
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
