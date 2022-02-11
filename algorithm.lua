local enums = require("enums")

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
require_layout("super_compact")
require_layout("sparse")
require_layout("logistics")
require_layout("compact_logistics")

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
---@field logistics_choice string
---@field coords Coords
---@field grid Grid
---@field miner MinerStruct
---@field preview_rectangle uint64 -- LuaRendering.draw_rectangle

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
	state.logistics_choice = player_data.logistics_choice
	state.coverage_choice = player_data.coverage_choice
	state.preview_rectangle = nil

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
		local _, cached_resources = enums.get_available_miners()
		if cached_resources[category] then
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

	local cats = game.entity_prototypes[state.miner_choice].resource_categories

	for k, v in pairs(found_resources) do
		if not cats[v] then
			local miner_name = game.entity_prototypes[state.miner_choice].localised_name
			local resource_name = game.entity_prototypes[k].localised_name
			--player.print(("Can't build on this resource patch with selected miner \"%s\" because it can't mine resource \"%s\""):format())
			state.player.print{"", {"mpp.msg_miner_err_2_1"}, " \"", miner_name, "\" ", {"mpp.msg_miner_err_2_2"}, " \"", resource_name, "\""}
			return
		end
	end
	
	local validation_result, error = layout:validate(state)
	if validation_result then
		layout:initialize(state)

		-- "Progress" bar
		local c = state.coords
		state.preview_rectangle = rendering.draw_rectangle{
			surface=state.surface,
			left_top={state.coords.ix1, state.coords.iy1},
			right_bottom={state.coords.ix1 + c.w, state.coords.iy1 + c.h},
			filled=false, color={0, 0.8, 0.3, 1},
			width = 8,
			draw_on_ground = true,
			time_to_live = 60*5,
			players={state.player},
		}

		return state
	else
		return nil, error
	end
end

return algorithm
