local gui = {}

---@class GuiSettings
---@field layout_choice string The layout direction
---@field miner_choice string The miner choice

local function build_belt_table(player)
	local ply_global = global.players[player.index]
	ply_global.gui.belt_table.clear()
	local belts = game.get_filtered_entity_prototypes{{filter="type", type="transport-belt"}}
	for _, belt in pairs(belts) do
		local button_style = ply_global.belt_choice == belt.name and "yellow_slot_button" or "recipe_slot_button"
		ply_global.gui.belt_table.add{
			type="sprite-button", sprite=("item/"..belt.name), style=button_style, tags={action="mpp_belt_choice", belt=belt.name},
			tooltip={"entity-name."..belt.name},
		}
	end
end

local function build_miner_table(player)
	local ply_global = global.players[player.index]
	ply_global.gui.miner_table.clear()
	local miners = game.get_filtered_entity_prototypes{{filter="type", type="mining-drill"}}
	for _, miner in pairs(miners) do
		local cbox_tl, cbox_br = miner.collision_box.left_top, miner.collision_box.right_bottom
		local w, h = math.ceil(cbox_br.x - cbox_tl.x), math.ceil(cbox_br.y - cbox_tl.y) -- Algorithm doesn't support even size miners
		if miner.resource_categories["basic-solid"] and miner.electric_energy_source_prototype and w % 2 == 1 then
			local button_style = ply_global.miner_choice == miner.name and "yellow_slot_button" or "recipe_slot_button"
			ply_global.gui.miner_table.add{
				type="sprite-button", sprite=("item/"..miner.name), style=button_style, tags={action="mpp_miner_choice", miner=miner.name},
				tooltip={"entity-name."..miner.name},
			}
		end
	end
end

---@param player LuaPlayer
function gui.build_interface(player)
	local ply_global = global.players[player.index]

	local screen_element = player.gui.left
	if screen_element.mpp_settings_frame then return end
	local settings_frame = screen_element.add{type="frame", name="mpp_settings_frame", caption={"mpp.settings_frame"}, direction = "vertical"}

	local settings_layout_label = settings_frame.add{type="label", name="mpp_layout_label", style="subheader_caption_label", caption={"mpp.settings_layout_label"}}
	local radiobutton_dir_up = settings_frame.add{
		type="radiobutton", name="mpp_radiobutton_up", caption={"mpp.settings_radio_up"}, state=ply_global.layout_choice == "vertical" and ply_global.vertical_direction == "up", tags={action="mpp_direction", layout="vertical", direction="up"}
	}
	local radiobutton_dir_right = settings_frame.add{
		type="radiobutton", name="mpp_radiobutton_right", caption={"mpp.settings_radio_right"}, state=ply_global.layout_choice == "horizontal" and ply_global.horizontal_direction == "right", tags={action="mpp_direction", layout="horizontal", direction="right"}
	}
	local radiobutton_dir_down = settings_frame.add{
		type="radiobutton", name="mpp_radiobutton_down", caption={"mpp.settings_radio_down"}, state=ply_global.layout_choice == "vertical" and ply_global.vertical_direction == "down", tags={action="mpp_direction", layout="vertical", direction="down"}
	}
	local radiobutton_dir_left = settings_frame.add{
		type="radiobutton", name="mpp_radiobutton_left", caption={"mpp.settings_radio_left"}, state=ply_global.layout_choice == "horizontal" and ply_global.horizontal_direction == "left", tags={action="mpp_direction", layout="horizontal", direction="left"}
	}
	ply_global.gui.layout_radio_dir = {
		[radiobutton_dir_right.name] = radiobutton_dir_right,
		[radiobutton_dir_left.name] = radiobutton_dir_left,
		[radiobutton_dir_up.name] = radiobutton_dir_up,
		[radiobutton_dir_down.name] = radiobutton_dir_down,
	}

	local settings_belt_label = settings_frame.add{type="label", name="mpp_belt_label", style="subheader_caption_label", caption={"mpp.settings_belt_label"}}
	local belt_frame = settings_frame.add{type="frame", name="mpp_belt_frame", direction="horizontal", style="invisible_frame"}
	local belt_table = belt_frame.add{type="table", name="mpp_belt_table", style="filter_slot_table", column_count=5}
	ply_global.gui.belt_table = belt_table
	build_belt_table(player)

	local settings_miner_label = settings_frame.add{type="label", name="mpp_miner_label", style="subheader_caption_label", caption={"mpp.settings_miner_label"}}
	local miner_frame = settings_frame.add{type="frame", name="mpp_miner_frame", direction="horizontal", style="invisible_frame"}
	local miner_table = miner_frame.add{type="table", name="mpp_miner_table", style="filter_slot_table", column_count=5}
	ply_global.gui.miner_table = miner_table
	build_miner_table(player)

	local misc_label = settings_frame.add{type="label", name="mpp_misc_label", style="subheader_caption_label", caption={"mpp.settings_misc_label"}}
	local checkbox_lamps = settings_frame.add{type="checkbox", name="mpp_checkbox_lamp", state=ply_global.lamp, caption={"mpp.settings_checkbox_lamps"}, tags={action="mpp_lamp"}}

end

---@param event EventDataGuiCheckedStateChanged
function gui.on_gui_checked_state_changed(event)
	local ply_global = global.players[event.player_index]
	if event.element.tags.action == "mpp_direction" then
		ply_global.layout_choice = event.element.tags.layout
		ply_global[event.element.tags.layout.."_direction"] = event.element.tags.direction
		for key, ele in pairs(ply_global.gui.layout_radio_dir) do
			if key ~= event.element.name then
				ele.state = false
			end
		end
	end
end

---@param event EventDataGuiClick
function gui.on_gui_click(event)
	local player = game.get_player(event.player_index)
	local ply_global = global.players[event.player_index]
	if event.element.tags.action == "mpp_belt_choice" then
		ply_global.belt_choice = event.element.tags.belt
		build_belt_table(player)
	elseif event.element.tags.action == "mpp_miner_choice" then
		ply_global.miner_choice = event.element.tags.miner
		build_miner_table(player)
	elseif event.element.tags.action == "mpp_lamp" then
		ply_global.lamp = event.element.state
	end
end

---@param player LuaPlayer
function gui.destroy_interface(player)
	---@type LuaGuiElement
	local settings_frame = player.gui.left.mpp_settings_frame

	if settings_frame then
		settings_frame.destroy()
		local ply_global = global.players[player.index]
		ply_global.gui = {}
	end
end

function gui.on_player_removed(event)
	global.players[event.player_index] = nil
end

return gui
