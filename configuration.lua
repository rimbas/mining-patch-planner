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
---@field blueprint_choice LuaItemStack Currently selected blueprint (flow)
---@field direction_choice string
---@field miner_choice string
---@field pole_choice string
---@field lamp_choice boolean
---@field belt_choice string
---@field logistics_choice string
---@field landfill_choice boolean
---@field coverage_choice boolean
---@field start_choice boolean
---@field deconstruction_choice boolean
---@field pipe_choice string
---@field module_choice string
---@field show_non_electric_miners_choice boolean

---@class PlayerGui
---@field section table<string, LuaGuiElement>
---@field tables table<string, LuaGuiElement>
---@field selections table<string, LuaGuiElement>
---@field advanced_settings LuaGuiElement
---@field layout_dropdown LuaGuiElement
---@field blueprint_add_button LuaGuiElement

---@class PlayerGuiBlueprints All subtables are indexed by blueprint's item number
---@field mapping table<number, LuaItemStack>
---@field flow table<number, LuaGuiElement> Root blueprint element
---@field button table<number, LuaGuiElement> Blueprint button toggle
---@field delete table<number, LuaGuiElement> Blueprint delete button
---@field cache table<number, EvaluatedBlueprint>
---@field original_id table<number, number> Inventory blueprint id to 

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
		start_choice = false,
		deconstruction_choice = false,
		pipe_choice = "none",
		module_choice = "none",

		-- non layout/convienence/advanced settings
		show_non_electric_miners_choice = false,
	},

	gui = {
		section = {},
		tables = {},
		selections = {},
	},

	blueprints = {
		mapping = {},
		cache = {},
		flow = {},
		button = {},
		delete = {},
		original_id = {},
	}
}

---@param player_index number
---@param old_data PlayerData|nil
function conf.initialize_global(player_index, old_data)
	global.players[player_index] = table.deepcopy(conf.default_config)
	if old_data and old_data.blueprint_items then
		global.players[player_index].blueprint_items = old_data.blueprint_items
	else
		global.players[player_index].blueprint_items = game.create_inventory(1)
	end
end

function conf.initialize_deconstruction_filter()
	if global.script_inventory then
		global.script_inventory.destroy()
	end

	---@type LuaInventory
	local inventory = game.create_inventory(2)
	do
		---@type LuaItemStack
		local basic = inventory[1]
		basic.set_stack("deconstruction-planner")
		basic.tile_selection_mode = defines.deconstruction_item.tile_selection_mode.never
	end

	do
		---@type LuaItemStack
		local ghosts = inventory[2]
		ghosts.set_stack("deconstruction-planner")
		ghosts.entity_filter_mode = defines.deconstruction_item.entity_filter_mode.whitelist
		ghosts.entity_filters = {"entity-ghost"}
	end

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
