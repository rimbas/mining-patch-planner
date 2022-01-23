local algorithm = require("algorithm")

local layouts = algorithm.layouts

local gui = {}

--[[
	tag explanations:
	mpp_action - a choice between several settings for a "*_choice"
	mpp_toggle - a toggle for a boolean "*_choice"
]]

---Creates a setting section (label + table)
---Can be hidden
---@param player_data PlayerData
---@param root any
---@param name any
---@return LuaGuiElement, LuaGuiElement
local function create_setting_section(player_data, root, name)
	local section = root.add{type="flow", direction="vertical"}
	player_data.gui.section[name] = section
	section.add{type="label", style="subheader_caption_label", caption={"mpp.settings_"..name.."_label"}}
	local table_root = section.add{
		type="table",
		direction="horizontal",
		style="filter_slot_table",
		column_count=6,
	}
	player_data.gui.tables[name] = table_root
	return table_root, section
end

local function style_helper_selection(check)
	if check then return "yellow_slot_button" end
	return "recipe_slot_button"
end

local function style_helper_advanced_toggle(check)
	return check and "mpp_selected_frame_action_button" or "frame_action_button"
end

---@param player_data any global player GUI reference object
---@param root LuaGuiElement
local function create_setting_selector(player_data, root, action_type, action, values)
	local action_class = {}
	player_data.gui.selections[action] = action_class
	root.clear()
	local selected = player_data[action.."_choice"]
	for _, value in ipairs(values) do
		local toggle_value = action_type == "mpp_toggle" and player_data[value.value.."_choice"]
		local style_check = value.value == selected or toggle_value
		local button = root.add{
			type="sprite-button",
			style=style_helper_selection(style_check),
			sprite=value.icon,
			tags={[action_type]=action, value=value.value, default=value.default},
			tooltip=value.tooltip,
		}
		action_class[value.value] = button
	end
end

---@param player LuaPlayer
function gui.create_interface(player)
	---@type LuaGuiElement
	local frame = player.gui.screen.add{type="frame", name="mpp_settings_frame", direction="vertical"}
	local player_data = global.players[player.index]
	local player_gui = player_data.gui

	local titlebar = frame.add{type="flow", name="mpp_titlebar", direction="horizontal"}
	titlebar.add{type="label", style="frame_title", name="mpp_titlebar_label", caption={"mpp.settings_frame"}}
	titlebar.add{type="empty-widget", name="mpp_titlebar_spacer", horizontally_strechable=true}
	player_gui.advanced_settings = titlebar.add{
		type="sprite-button",
		style="frame_action_button",
		sprite="mpp_advanced_settings",
		tooltip={"mpp.advanced_settings"},
		tags={mpp_advanced_settings=true},
	}

	do -- layout selection
		local table_root, section = create_setting_section(player_data, frame, "layout")

		local choices = {}
		local index = 0
		for i, layout in ipairs(layouts) do
			if player_data.layout_choice == layout.name then 
				index = i
			end
			choices[#choices+1] = layout.translation
		end

		local drop_down = table_root.add{
			type="drop-down",
			items=choices,
			selected_index=index,
			tags={mpp_drop_down="layout", default=1},
		}

		section.visible = player_data.advanced
	end

	do -- Direction selection
		local table_root = create_setting_section(player_data, frame, "direction")
		create_setting_selector(player_data, table_root, "mpp_action", "direction", {
			{value="north", icon="mpp_direction_north"},
			{value="south", icon="mpp_direction_south"},
			{value="west", icon="mpp_direction_west"},
			{value="east", icon="mpp_direction_east"},
		})
	end

	do -- Miner selection
		create_setting_section(player_data, frame, "miner")
	end

	do -- Belt selection
		create_setting_section(player_data, frame, "belt")
	end

	do -- Electric pole selection
		create_setting_section(player_data, frame, "pole")
	end

	do -- Misc selection
		create_setting_section(player_data, frame, "misc")
	end

end

---@param player_data PlayerData
local function update_drill_selection(player_data)
	local values = {}
	local miners = game.get_filtered_entity_prototypes{{filter="type", type="mining-drill"}}
	for _, miner in pairs(miners) do
		local cbox_tl, cbox_br = miner.collision_box.left_top, miner.collision_box.right_bottom
		local w, h = math.ceil(cbox_br.x - cbox_tl.x), math.ceil(cbox_br.y - cbox_tl.y) -- Algorithm doesn't support even size miners
		if miner.resource_categories["basic-solid"] and miner.electric_energy_source_prototype and w % 2 == 1 then
			values[#values+1] = {
				value=miner.name,
				tooltip={"entity-name."..miner.name},
				icon=("entity/"..miner.name),
				sort={miner.mining_drill_radius, miner.mining_speed},
			}
		end
	end
	table.sort(values, function(a, b) return a.sort[1] < b.sort[1] and a.sort[2] < b.sort[2] end)
	local table_root = player_data.gui.tables["miner"]
	create_setting_selector(player_data, table_root, "mpp_action", "miner", values)
end

---@param player_data PlayerData
local function update_belt_selection(player_data)
	local values = {}
	local belts = game.get_filtered_entity_prototypes{{filter="type", type="transport-belt"}}
	for _, belt in pairs(belts) do
		values[#values+1] = {
			value=belt.name,
			tooltip={"entity-name."..belt.name},
			icon=("entity/"..belt.name),
			sort=belt.belt_speed,
		}
	end
	table.sort(values, function(a, b) return a.sort < b.sort end)
	local table_root = player_data.gui.tables["belt"]
	create_setting_selector(player_data, table_root, "mpp_action", "belt", values)
end

---@param player_data PlayerData
local function update_pole_selection(player_data)
	local values = {}
	values[1] = {
		value="none",
		tooltip={"mpp.choice_none"},
		icon="mpp_no_entity",
	}

	local poles = game.get_filtered_entity_prototypes{{filter="type", type="electric-pole"}}
	for _, pole in pairs(poles) do
		local cbox = pole.collision_box
		local size = math.ceil(cbox.right_bottom.x - cbox.left_top.x)
		if size <= 1 then
			values[#values+1] = {
				value=pole.name,
				tooltip={"entity-name."..pole.name},
				icon=("entity/"..pole.name),
			}
		end
	end
	local table_root = player_data.gui.tables["pole"]
	create_setting_selector(player_data, table_root, "mpp_action", "pole", values)
end

---@param player_data PlayerData
local function update_misc_selection(player_data)
	local values = {}
	values[1] = {
		value="lamp",
		tooltip={"mpp.choice_lamp"},
		icon=("entity/small-lamp"),
	}
	local table_root = player_data.gui.tables["misc"]
	create_setting_selector(player_data, table_root, "mpp_toggle", "misc", values)
end

---@param player LuaPlayer
function gui.show_interface(player)
	---@type LuaGuiElement
	local frame = player.gui.screen["mpp_settings_frame"]
	local player_data = global.players[player.index]
	if frame then
		frame.visible = true
	else
		gui.create_interface(player)
	end
	update_drill_selection(player_data)
	update_belt_selection(player_data)
	update_pole_selection(player_data)
	update_misc_selection(player_data)
end

---@param player LuaPlayer
function gui.hide_interface(player)
	---@type LuaGuiElement
	local frame = player.gui.screen["mpp_settings_frame"]
	if frame then
		frame.visible = false
	end
end

---@param event EventDataGuiClick
local function on_gui_click(event)
	if event.element.tags["mpp_advanced_settings"] then
		---@type PlayerData
		local player_data = global.players[event.player_index]

		local last_value = player_data.advanced
		local value = not last_value
		player_data.advanced = value

		local layout_section = player_data.gui.section["layout"]

		layout_section.visible = value

		player_data.gui["advanced_settings"].style = style_helper_advanced_toggle(value)
	elseif event.element.tags["mpp_action"] then
		---@type PlayerData
		local player_data = global.players[event.player_index]

		local action = event.element.tags["mpp_action"]
		local value = event.element.tags["value"]
		local last_value = player_data[action.."_choice"]

		---@type LuaGuiElement
		player_data.gui.selections[action][last_value].style = style_helper_selection(false)
		event.element.style = style_helper_selection(true)
		player_data[action.."_choice"] = value
	elseif event.element.tags["mpp_toggle"] then
		---@type PlayerData
		local player_data = global.players[event.player_index]

		local action = event.element.tags["mpp_toggle"]
		local value = event.element.tags["value"]
		local last_value = player_data[value.."_choice"]
		player_data[value.."_choice"] = not last_value
		event.element.style = style_helper_selection(not last_value)
	end
end
script.on_event(defines.events.on_gui_click, on_gui_click)
--script.on_event(defines.events.on_gui_checked_state_changed, gui.on_gui_checked_state_changed)

---@param event EventDataGuiSelectionStateChanged
local function on_gui_selection_state_changed(event)
	if event.element.tags["mpp_drop_down"] then
		---@type PlayerData
		local player_data = global.players[event.player_index]

		local action = event.element.tags["mpp_drop_down"]
		local value = layouts[event.element.selected_index].name
		player_data.layout_choice = value
	end
end
script.on_event(defines.events.on_gui_selection_state_changed, on_gui_selection_state_changed)

return gui
