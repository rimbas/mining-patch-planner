local util = require("util")
local gui = require("gui")
local conf = require("configuration")
--require("control_old")
local algorithm = require("algorithm")

script.on_init(function()
	global.players = {}

	for _, player in pairs(game.players) do
		conf.initialize_global(player)
		--gui.build_interface(player)
	end
end)

script.on_event(defines.events.on_player_created, function(e)
	local player = game.get_player(e.player_index)
	conf.initialize_global(player)
end)

script.on_event(defines.events.on_player_cursor_stack_changed, function(e)
	local player = game.get_player(e.player_index)
	local cursor_stack = player.cursor_stack
	if cursor_stack and cursor_stack.valid and cursor_stack.valid_for_read and cursor_stack.name == "mining-patch-planner" then
		gui.build_interface(player)
	else
		gui.destroy_interface(player)
	end
end)

script.on_configuration_changed(function(config_changed_data)
    if config_changed_data.mod_changes["mining-patch-planner"] then
        for _, player in pairs(game.players) do
			local ply_global = global.players[player.index]

			global.players[player.index] = util.merge{conf.default_config, ply_global}

            local mpp_settings_frame = player.gui.left.mpp_settings_frame
            if mpp_settings_frame then
				gui.destroy_interface(player)
				gui.build_interface(player)
			end
        end
    end
end)

script.on_event(defines.events.on_gui_checked_state_changed, gui.on_gui_checked_state_changed)
script.on_event(defines.events.on_gui_click, gui.on_gui_click)

script.on_event(defines.events.on_player_removed, function(e)
	gui.on_player_removed(e)
end)

script.on_event(defines.events.on_player_selected_area, algorithm.on_player_selected_area)
