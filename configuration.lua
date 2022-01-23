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
---@field gui PlayerGui

---@class PlayerGui
---@field section table<string, LuaGuiElement>
---@field tables table<string, LuaGuiElement>
---@field selections table<string, LuaGuiElement>
--@field section.miner LuaGuiElement Root Miner section element

conf.default_config = {
	advanced = false,
	layout_choice = "simple",
	direction_choice = "north",
	belt_choice = "transport-belt",
	miner_choice = "electric-mining-drill",
	pole_choice = "medium-electric-pole",
	lamp_choice = false,

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

script.on_event(defines.events.on_player_created, function(e)
	conf.initialize_global(e.player_index)
end)

script.on_event(defines.events.on_player_removed, function(e)
	global.players[e.player_index] = nil
end)

return conf
