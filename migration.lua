local conf = require("configuration")
local enums = require("enums")

local current_version = 010301 -- 1.3.0

---@param player LuaPlayer
local function reset_gui(player)
	local root = player.gui.left["mpp_settings_frame"] or player.gui.screen["mpp_settings_frame"]
	if root then
		root.destroy()
	end
	local cursor_stack = player.cursor_stack
	if cursor_stack and cursor_stack.valid and cursor_stack.valid_for_read and cursor_stack.name == "mining-patch-planner" then
		cursor_stack.clear()
	end
end

script.on_configuration_changed(function(config_changed_data)
	-- Fix selection defaults for players on mod changes
	if conf.default_config.miner_choice ~= enums.get_default_miner() then
		conf.default_config.miner_choice = enums.get_default_miner()
		local cached_miners, cached_resources = enums.get_available_miners()
		for player_index, data in ipairs(global.players) do
			if not cached_miners[data.miner_choice] then
				reset_gui(game.players[player_index])
				conf.initialize_global(player_index)
			end
		end
	end

	-- Native changes
	if config_changed_data.mod_changes["mining-patch-planner"] then
		local version = global.version or 0

		if version < current_version then
			global.tasks = global.tasks or {}
			conf.initialize_deconstruction_filter()
			for player_index, data in ipairs(global.players) do
				---@cast data PlayerData
				---@type LuaPlayer
				local player = game.players[player_index]
				reset_gui(player)
				conf.initialize_global(player_index, data)
			end
		end
		global.version = current_version
	else
		for player_index, data in ipairs(global.players) do
			reset_gui(game.players[player_index])
		end
    end
end)
