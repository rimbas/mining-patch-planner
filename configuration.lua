local util = require("util")
local conf = {}

---@class PlayerData
---@field advanced boolean
---@field blueprint_add_mode boolean
---@field gui PlayerGui
---@field blueprint_items LuaInventory
---@field choices PlayerChoices
---@field blueprints PlayerGuiBlueprints

---@class PlayerChoices
---@field layout_choice string
---@field blueprint_choice LuaGuiElement Currently selected blueprint (flow)
---@field direction_choice string
---@field miner_choice string
---@field pole_choice string
---@field lamp_choice boolean
---@field belt_choice string
---@field logistics_choice string
---@field landfill_choice boolean
---@field coverage_choice boolean

---@class PlayerGui
---@field section table<string, LuaGuiElement>
---@field tables table<string, LuaGuiElement>
---@field selections table<string, LuaGuiElement>
---@field advanced_settings LuaGuiElement
---@field layout_dropdown LuaGuiElement
---@field blueprint_add_button LuaGuiElement

---@class PlayerGuiBlueprints All subtables are indexed by root flow index
---@field flow table<number, LuaGuiElement> Root blueprint element
---@field button table<number, LuaGuiElement> Blueprint button toggle
---@field delete table<number, LuaGuiElement> Blueprint delete button
---@field mapping table<number, LuaItemStack>

---@type PlayerData
conf.default_config = {
	advanced = false,
	blueprint_add_mode = false,
	--blueprint_items = nil,

	choices = {
		layout_choice = "simple",
		--blueprint_choice = nil,
		direction_choice = "north",
		miner_choice = "electric-mining-drill",
		pole_choice = "medium-electric-pole",
		belt_choice = "transport-belt",
		lamp_choice = false,
		logistics_choice = "logistic-chest-passive-provider",
		landfill_choice = false,
		coverage_choice = false,
	},

	gui = {
		section = {},
		tables = {},
		selections = {},
	},

	blueprints = {
		mapping = {},
		flow = {},
		button = {},
		delete = {},
	}
}

---@param player_index number
function conf.initialize_global(player_index)
	global.players[player_index] = table.deepcopy(conf.default_config)
	global.players[player_index].blueprint_items = game.create_inventory(1)
end

function conf.initialize_deconstruction_filter()
	if global.script_inventory then
		global.script_inventory.destroy()
	end

	---@type LuaInventory
	local inventory = game.create_inventory(1)
	---@type LuaItemStack
	inventory.insert("deconstruction-planner")
	local deconstruction_planner = inventory[1]
	deconstruction_planner.tile_selection_mode = defines.deconstruction_item.tile_selection_mode.never

	global.script_inventory = inventory
end

script.on_event(defines.events.on_player_created, function(e)
	---@cast e EventData.on_player_created
	conf.initialize_global(e.player_index)
end)

script.on_event(defines.events.on_player_removed, function(e)
	---@cast e EventData.on_player_removed
	if global.players[e.player_index].blueprint_items then
		global.players[e.player_index].blueprint_items.destroy()
	end
	global.players[e.player_index] = nil
end)

return conf
