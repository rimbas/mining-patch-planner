local util = require("util")
local conf = {}

---@class PlayerData
---@field advanced boolean
---@field layout_choice string
---@field direction_choice string
---@field belt_choice string
---@field miner_choice string
---@field pole_choice string
---@field lamp_choice boolean
---@field coverage_choice boolean
---@field logistics_choice string
---@field gui PlayerGui

---@class PlayerGui
---@field section table<string, LuaGuiElement>
---@field tables table<string, LuaGuiElement>
---@field selections table<string, LuaGuiElement>
---@field advanced_settings LuaGuiElement
---@field layout_dropdown LuaGuiElement

conf.default_config = {
	advanced = false,
	layout_choice = "simple",
	direction_choice = "north",
	belt_choice = "transport-belt",
	miner_choice = "electric-mining-drill",
	pole_choice = "medium-electric-pole",
	lamp_choice = false,
	coverage_choice = false,
	logistics_choice = "logistic-chest-passive-provider",

	gui = {
		section = {},
		tables = {},
		selections = {},
	},
}

---@param player_index number
function conf.initialize_global(player_index)
	global.players[player_index] = table.deepcopy(conf.default_config)
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
	conf.initialize_global(e.player_index)
end)

script.on_event(defines.events.on_player_removed, function(e)
	global.players[e.player_index] = nil
end)

return conf
