local enums = require("enums")
local resource_categories = enums.resource_categories

local floor, ceil = math.floor, math.ceil
local min, max = math.min, math.max

local algorithm = {}

---@type table<string, Layout>
local layouts = {}
algorithm.layouts = layouts
local function require_layout(layout) 
	layouts[layout] = require("layouts."..layout)
	layouts[#layouts+1] = layouts[layout]
end
require_layout("simple")
require_layout("compact")
require_layout("sparse")
--require_layout("logistics")

---@class State
---@field delegate string
---@field finished boolean
---@field tick number
---@field surface LuaSurface
---@field player LuaPlayer
---@field resources LuaEntity[] Filtered resources
---@field found_resources LuaEntity[] Found resource types
---@field layout_choice string
---@field direction_choice string
---@field miner_choice string
---@field pole_choice string
---@field belt_choice string Belt name
---@field lamp_choice boolean Lamp placement
---@field coverage_choice boolean
---@field coords Coords
---@field grid Grid
---@field miner MinerStruct

---@param event EventDataPlayerSelectedArea
---@return State
local function create_state(event)
	---@type State
	local state = {}
	state.delegate = "start"
	state.finished = false
	state.tick = 0
	---@type PlayerData
	local player_data = global.players[event.player_index]

	-- game state properties
	state.surface = event.surface
	state.player = game.get_player(event.player_index)

	-- player option properties
	state.layout_choice = player_data.layout_choice
	state.direction_choice = player_data.direction_choice
	state.miner_choice = player_data.miner_choice
	state.belt_choice = player_data.belt_choice
	state.pole_choice = player_data.pole_choice
	state.lamp_choice = player_data.lamp_choice
	state.coverage_choice = player_data.coverage_choice

	return state
end

---Filters resource entity list and returns patch coordinates and size
---@param entities LuaEntity[]
---@return Coords, LuaEntity[]
---@return table<string, string> @key:resource name; value:resource category
local function process_entities(entities)
	local filtered = {}
	local found_resources = {} -- resource.name: resource_category
	local x1, y1 = math.huge, math.huge
	local x2, y2 = -math.huge, -math.huge
	for _, entity in pairs(entities) do
		---@type LuaResourceCategoryPrototype
		local category = entity.prototype.resource_category
		if resource_categories[category] then
			found_resources[entity.name] = category
			filtered[#filtered+1] = entity
			local x, y = entity.position.x, entity.position.y
			if x < x1 then x1 = x end
			if y < y1 then y1 = y end
			if x2 < x then x2 = x end
			if y2 < y then y2 = y end
		end
	end
	local coords = {
		x1 = x1, y1 = y1, x2 = x2, y2 = y2,
		ix1 = floor(x1), iy1 = floor(y1),
		ix2 = ceil(x2), iy2 = ceil(y2),
		gx = x1 - 1, gy = y1 - 1,
	}
	coords.w, coords.h = coords.ix2 - coords.ix1, coords.iy2 - coords.iy1
	return coords, filtered, found_resources
end

--- Algorithm hook
--- Returns nil if it fails
---@param event EventDataPlayerSelectedArea
function algorithm.on_player_selected_area(event)
	---@type PlayerData
	local player_data = global.players[event.player_index]
	local state = create_state(event)
	local layout = layouts[player_data.layout_choice]

	local coords, filtered, found_resources = process_entities(event.entities)
	state.coords = coords
	state.resources = filtered
	state.found_resources = found_resources

	if #filtered == 0 then
		return nil, {"mpp.msg_miner_err_0"}
	end

	
	local validation_result, error = layout:validate(state)
	if validation_result then
		layout:initialize(state)
		return state
	else
		return nil, error
	end
end

return algorithm
