local v = require("lib.semver") -- a 10 ton hammer for some migration calculation
local conf = require("configuration")

local migrations = {}

local function add_migration(t)
	local v_from, v_to, f
	if #t == 2 then
		migrations[#migrations+1] = {
			from = t[1],
			migration = t[2],
		}
	elseif #t == 3 then
		migrations[#migrations+1] = {
			from = t[1],
			to = t[2],
			migration = t[3],
		}
	end
end

add_migration{"1.1", function(mod_changes)
	global.tasks = {}

	for player_index, data in ipairs(global.players) do
		---@type LuaPlayer
		local player = game.players[player_index]
		if player.gui.left["mpp_settings_frame"] then
			
			local cursor_stack = player.cursor_stack
			if cursor_stack and cursor_stack.valid and cursor_stack.valid_for_read and cursor_stack.name == "mining-patch-planner" then
				cursor_stack.clear()
			end
			player.gui.left["mpp_settings_frame"].destroy()
		end
		conf.initialize_global(player.index)
	end
end}

---@param mod_changes ModChangeData
local function apply_migrations(mod_changes)
	local old_version, new_version = v(mod_changes.old_version), v(mod_changes.new_version)

	for i, migration_struct in ipairs(migrations) do
		local from, to = v(migration_struct.from), migration_struct.to and v(migration_struct.to) or new_version
		local migration = migration_struct.migration
		if old_version < from and to <= new_version then
			migration(mod_changes)
		end
	end
end

script.on_configuration_changed(function(config_changed_data)
    if config_changed_data.mod_changes["mining-patch-planner"] then
		apply_migrations(config_changed_data.mod_changes["mining-patch-planner"])
		--[[
        for _, player in pairs(game.players) do
			local ply_global = global.players[player.index]

			global.players[player.index] = util.merge{conf.default_config, ply_global}

            local mpp_settings_frame = player.gui.left.mpp_settings_frame
            if mpp_settings_frame then
				gui.destroy_interface(player)
				gui.build_interface(player)
			end
        end
		]]
    end
end)
