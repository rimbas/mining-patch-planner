local algorithm = require("algorithm")
local mpp_util = require("mpp_util")
local enums = require("enums")
local blacklist = require("blacklist")

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
local function create_setting_section(player_data, root, name, opts)
	opts = opts or {}
	local section = root.add{type="flow", direction="vertical"}
	player_data.gui.section[name] = section
	section.add{type="label", style="subheader_caption_label", caption={"mpp.settings_"..name.."_label"}}
	local table_root = section.add{
		type="table",
		direction=opts.direction or "horizontal",
		style="filter_slot_table",
		column_count=opts.column_count or 6,
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

local function style_helper_blueprint_toggle(check)
	return check and "mpp_blueprint_mode_button_active" or "mpp_blueprint_mode_button"
end

---@param player_data any global player GUI reference object
---@param root LuaGuiElement
local function create_setting_selector(player_data, root, action_type, action, values)
	local action_class = {}
	player_data.gui.selections[action] = action_class
	root.clear()
	local selected = player_data.choices[action.."_choice"]
	for _, value in ipairs(values) do
		local toggle_value = action_type == "mpp_toggle" and player_data.choices[value.value.."_choice"]
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

---@param player_data PlayerData
---@param table_root LuaGuiElement
local function create_blueprint_entry(player_data, table_root, blueprint_item)
	local blueprint_line = table_root.add{type="flow"}
	player_data.blueprints.flow[blueprint_line.index] = blueprint_line
	player_data.blueprints.mapping[blueprint_line.index] = blueprint_item
	
	local blueprint_button = blueprint_line.add{
		type="button",
		style="mpp_fake_blueprint_button",
		tags={mpp_fake_blueprint_button=true},
	}
	player_data.blueprints.button[blueprint_line.index] = blueprint_button

	local fake_table = blueprint_button.add{
		type="table",
		style="mpp_fake_blueprint_table",
		direction="horizontal",
		column_count=2,
		tags={mpp_fake_blueprint_table=true},
		ignored_by_interaction=true,
	}

	for k, v in pairs(blueprint_item.blueprint_icons) do
		local s = v.signal
		local sprite = s.name
		if s.type == "virtual" then
			sprite = "virtual-signal/"..sprite --wube pls
		else
			sprite = s.type .. "/" .. sprite
		end
		fake_table.add{
			type="sprite",
			sprite=(sprite),
			style="mpp_fake_blueprint_sprite",
			tags={mpp_fake_blueprint_sprite=true},
		}
	end

	local delete_button = blueprint_line.add{
		type="sprite-button",
		sprite="mpp_cross",
		style="mpp_delete_blueprint_button",
		tags={mpp_delete_blueprint_button=blueprint_line.index},
	}
	player_data.blueprints.delete[blueprint_line.index] = delete_button

	blueprint_line.add{
		type="label",
		caption=blueprint_item.label or {"mpp.label_unnamed_blueprint"},
	}
end

---@param player LuaPlayer
function gui.create_interface(player)
	---@type LuaGuiElement
	local frame = player.gui.screen.add{type="frame", name="mpp_settings_frame", direction="vertical"}
	---@type PlayerData
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
			if player_data.choices.layout_choice == layout.name then
				index = i
			end
			choices[#choices+1] = layout.translation
		end

		local flow = table_root.add{type="flow", direction="horizontal"}

		player_gui.layout_dropdown = flow.add{
			type="drop-down",
			items=choices,
			selected_index=index --[[@as uint]],
			tags={mpp_drop_down="layout", default=1},
		}

		player_gui.blueprint_add_button = flow.add{
			type="sprite-button",
			name="blueprint_add_button",
			sprite="mpp_plus",
			style=style_helper_blueprint_toggle(),
			tooltip={"mpp.blueprint_add_mode"},
			tags={mpp_blueprint_add_mode=true},
		}
		player_gui.blueprint_add_button.visible = player_data.choices.layout_choice == "blueprints"
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
		local table_root, section = create_setting_section(player_data, frame, "miner")
	end

	do -- Belt selection
		local table_root, section = create_setting_section(player_data, frame, "belt")
	end

	do -- Logistics selection
		local table_root, section = create_setting_section(player_data, frame, "logistics")
	end

	do -- Electric pole selection
		local table_root, section = create_setting_section(player_data, frame, "pole")
	end

	do -- Blueprint settings
		---@type LuaGuiElement, LuaGuiElement
		--local table_root, section = create_setting_section(player_data, frame, "blueprints")
		local section = frame.add{type="flow", direction="vertical"}
		player_data.gui.section["blueprints"] = section
		section.add{type="label", style="subheader_caption_label", caption={"mpp.settings_blueprints_label"}}

		local root = section.add{type="flow", direction="vertical"}
		player_data.gui.tables["blueprints"] = root

		player_gui.blueprint_add_section = section.add{
			type="flow",
			direction="horizontal",
		}

		player_gui.blueprint_receptacle = player_gui.blueprint_add_section.add{
			type="sprite-button",
			sprite="mpp_blueprint_add",
			tags={mpp_blueprint_receptacle=true},
		}
		local blueprint_label = player_gui.blueprint_add_section.add{
			type="label",
			caption={"mpp.label_add_blueprint", },
		}
		player_gui.blueprint_add_section.visible = player_data.blueprint_add_mode

	end

	do -- Misc selection
		local table_root, section = create_setting_section(player_data, frame, "misc")
	end
end

---@param player_data PlayerData
local function update_miner_selection(player_data)
	local player_choices = player_data.choices
	local layout = layouts[player_choices.layout_choice]
	local restrictions = layout.restrictions
	
	player_data.gui.section["miner"].visible = restrictions.miner_available
	if not restrictions.miner_available then return end

	local near_radius_min, near_radius_max = restrictions.miner_near_radius[1], restrictions.miner_near_radius[2]
	local far_radius_min, far_radius_max = restrictions.miner_far_radius[1], restrictions.miner_far_radius[2]
	local values = {}
	local existing_choice_is_valid = false
	local cached_miners, cached_resources = enums.get_available_miners()

	for _, miner_proto in pairs(cached_miners) do
		if blacklist[miner_proto.name] then goto skip_miner end
		local miner = mpp_util.miner_struct(miner_proto)

		if not miner_proto.electric_energy_source_prototype then goto skip_miner end
		if miner.size % 2 == 0 then goto skip_miner end -- Algorithm doesn't support even size miners
		if miner.near < near_radius_min or near_radius_max < miner.near then goto skip_miner end
		if miner.far < far_radius_min or far_radius_max < miner.far then goto skip_miner end

		values[#values+1] = {
			value=miner.name,
			tooltip=miner_proto.localised_name,
			icon=("entity/"..miner.name),
			order=miner_proto.order,
		}
		if miner.name == player_choices.miner_choice then existing_choice_is_valid = true end

		::skip_miner::
	end

	if not existing_choice_is_valid then
		player_choices.miner_choice = layout.defaults.miner
	end

	local table_root = player_data.gui.tables["miner"]
	create_setting_selector(player_data, table_root, "mpp_action", "miner", values)
end

---@param player_data PlayerData
local function update_belt_selection(player_data)
	local choices = player_data.choices
	local layout = layouts[choices.layout_choice]
	local restrictions = layout.restrictions
	
	player_data.gui.section["belt"].visible = restrictions.belt_available
	if not restrictions.belt_available then return end

	local values = {}
	local existing_choice_is_valid = false

	local belts = game.get_filtered_entity_prototypes{{filter="type", type="transport-belt"}}
	for _, belt in pairs(belts) do
		if blacklist[belt.name] then goto skip_belt end
		if belt.flags and belt.flags.hidden then goto skip_belt end
		if layout.restrictions.uses_underground_belts and belt.related_underground_belt == nil then goto skip_belt end

		values[#values+1] = {
			value=belt.name,
			tooltip=belt.localised_name,
			icon=("entity/"..belt.name),
			order=belt.order,
		}
		if belt.name == choices.belt_choice then existing_choice_is_valid = true end

		::skip_belt::
	end

	if not existing_choice_is_valid then
		if mpp_util.table_find(values, function(v) return v.value == layout.defaults.belt end) then
			choices.belt_choice = layout.defaults.belt
		else
			choices.belt_choice = values[1].value
		end
	end

	local table_root = player_data.gui.tables["belt"]
	create_setting_selector(player_data, table_root, "mpp_action", "belt", values)
end

---@param player_data PlayerData
local function update_logistics_selection(player_data)
	local choices = player_data.choices
	local layout = layouts[choices.layout_choice]
	local restrictions = layout.restrictions
	local values = {}

	player_data.gui.section["logistics"].visible = restrictions.logistics_available
	if not restrictions.logistics_available then return end

	local filter = {
		["passive-provider"]=true,
		["active-provider"]=true,
		["storage"] = true,
	}

	local existing_choice_is_valid = false
	local logistics = game.get_filtered_entity_prototypes{{filter="type", type="logistic-container"}}
	for _, chest in pairs(logistics) do
		if chest.flags and chest.flags.hidden then goto skip_chest end
		if blacklist[chest.name] then goto skip_chest end
		local cbox = chest.collision_box
		local size = math.ceil(cbox.right_bottom.x - cbox.left_top.x)
		if size > 1 then goto skip_chest end
		if not filter[chest.logistic_mode] then goto skip_chest end

		values[#values+1] = {
			value=chest.name,
			tooltip=chest.localised_name,
			icon=("entity/"..chest.name),
		}
		if chest.name == choices.logistics_choice then existing_choice_is_valid = true end

		::skip_chest::
	end

	if not existing_choice_is_valid then
		if mpp_util.table_find(values, function(v) return v.value == layout.defaults.logistics end) then
			choices.logistics_choice = layout.defaults.logistics
		else
			choices.logistics_choice = values[1].value
		end
	end

	local table_root = player_data.gui.tables["logistics"]
	create_setting_selector(player_data, table_root, "mpp_action", "logistics", values)
end

---@param player_data PlayerData
local function update_pole_selection(player_data)
	local choices = player_data.choices
	local layout = layouts[choices.layout_choice]
	local restrictions = layout.restrictions

	player_data.gui.section["pole"].visible = restrictions.pole_available
	if not restrictions.pole_available then return end

	local pole_width_min, pole_width_max = restrictions.pole_width[1], restrictions.pole_width[2]
	local pole_supply_min, pole_supply_max = restrictions.pole_supply_area[1], restrictions.pole_supply_area[2]

	local values = {}
	values[1] = {
		value="none",
		tooltip={"mpp.choice_none"},
		icon="mpp_no_entity",
	}

	local existing_choice_is_valid = ("none" == choices.pole_choice)
	local poles = game.get_filtered_entity_prototypes{{filter="type", type="electric-pole"}}
	for _, pole in pairs(poles) do
		if pole.flags and pole.flags.hidden then goto skip_pole end
		if blacklist[pole.name] then goto skip_pole end
		local cbox = pole.collision_box
		local size = math.ceil(cbox.right_bottom.x - cbox.left_top.x)
		local supply_area = pole.supply_area_distance
		if size < pole_width_min or pole_width_max < size then goto skip_pole end
		if supply_area < pole_supply_min or pole_supply_max < supply_area then goto skip_pole end

		values[#values+1] = {
			value=pole.name,
			tooltip=pole.localised_name,
			icon=("entity/"..pole.name),
		}
		if pole.name == choices.pole_choice then existing_choice_is_valid = true end

		::skip_pole::
	end

	if not existing_choice_is_valid then
		choices.pole_choice = layout.defaults.pole
	end

	local table_root = player_data.gui.tables["pole"]
	create_setting_selector(player_data, table_root, "mpp_action", "pole", values)
end

---@param player_data PlayerData
local function update_misc_selection(player_data)
	local choices = player_data.choices
	local layout = layouts[choices.layout_choice]
	local values = {}

	if layout.restrictions.lamp_available then
		values[#values+1] = {
			value="lamp",
			tooltip={"mpp.choice_lamp"},
			icon=("entity/small-lamp"),
		}
	end

	if player_data.advanced then
		if layout.restrictions.coverage_tuning then
			values[#values+1] = {
				value="coverage",
				tooltip={"mpp.choice_coverage"},
				icon=("mpp_miner_coverage"),
			}
		end

		if layout.restrictions.landfill_omit_available then
			values[#values+1] = {
				value="landfill",
				tooltip={"mpp.choice_landfill"},
				icon=("mpp_omit_landfill")
			}
		end
	end

	local misc_section = player_data.gui.section["misc"]
	misc_section.visible = #values > 0

	local table_root = player_data.gui.tables["misc"]
	create_setting_selector(player_data, table_root, "mpp_toggle", "misc", values)
end

---@param player_data PlayerData
local function update_blueprint_selection(player_data)
	local choices = player_data.choices
	local player_blueprints = player_data.blueprints
	player_data.gui.section["blueprints"].visible = choices.layout_choice == "blueprints"
	player_data.gui["blueprint_add_section"].visible = player_data.blueprint_add_mode
	player_data.gui["blueprint_add_button"].style = style_helper_blueprint_toggle(player_data.blueprint_add_mode)

	for key, value in pairs(player_blueprints.delete) do
		value.visible = player_data.blueprint_add_mode
	end
end

---@param player_data PlayerData
local function update_selections(player_data)
	player_data.gui.blueprint_add_button.visible = player_data.choices.layout_choice == "blueprints"
	update_miner_selection(player_data)
	update_belt_selection(player_data)
	update_logistics_selection(player_data)
	update_pole_selection(player_data)
	update_blueprint_selection(player_data)
	update_misc_selection(player_data)
end

---@param player LuaPlayer
function gui.show_interface(player)
	---@type LuaGuiElement
	local frame = player.gui.screen["mpp_settings_frame"]
	local player_data = global.players[player.index]
	player_data.blueprint_add_mode = false
	if frame then
		frame.visible = true
	else
		gui.create_interface(player)
	end
	update_selections(player_data)
end

---@param player_data PlayerData
local function set_player_blueprint(player_data)

end

---@param player LuaPlayer
local function abort_blueprint_mode(player)
	local player_data = global.players[player.index]
	if not player_data.blueprint_add_mode then return end
	player_data.blueprint_add_mode = false
	update_blueprint_selection(player_data)
	local cursor_stack = player.cursor_stack
	player.clear_cursor()
	cursor_stack.set_stack("mining-patch-planner")
end

---@param player LuaPlayer
function gui.hide_interface(player)
	---@type LuaGuiElement
	local frame = player.gui.screen["mpp_settings_frame"]
	local player_data = global.players[player.index]
	player_data.blueprint_add_mode = false
	if frame then
		frame.visible = false
	end
end

---@param event EventDataGuiClick
local function on_gui_click(event)
	local player = game.players[event.player_index]
	---@type PlayerData
	local player_data = global.players[event.player_index]
	local evt_ele_tags = event.element.tags
	if evt_ele_tags["mpp_advanced_settings"] then
		abort_blueprint_mode(player)

		local last_value = player_data.advanced
		local value = not last_value
		player_data.advanced = value

		update_selections(player_data)

		player_data.gui["advanced_settings"].style = style_helper_advanced_toggle(value)
	elseif evt_ele_tags["mpp_action"] then
		abort_blueprint_mode(player)

		local action = evt_ele_tags["mpp_action"]
		local value = evt_ele_tags["value"]
		local last_value = player_data.choices[action.."_choice"]

		---@type LuaGuiElement
		player_data.gui.selections[action][last_value].style = style_helper_selection(false)
		event.element.style = style_helper_selection(true)
		player_data.choices[action.."_choice"] = value
	elseif evt_ele_tags["mpp_toggle"] then
		abort_blueprint_mode(player)

		local action = evt_ele_tags["mpp_toggle"]
		local value = evt_ele_tags["value"]
		local last_value = player_data.choices[value.."_choice"]
		player_data.choices[value.."_choice"] = not last_value
		event.element.style = style_helper_selection(not last_value)
	elseif evt_ele_tags["mpp_blueprint_add_mode"] then
	--elseif evt_ele_tags["mpp_blueprint_receptacle"] then
		---@type PlayerData
		local player_data = global.players[event.player_index]
		player_data.blueprint_add_mode = not player_data.blueprint_add_mode
		player.clear_cursor()
		if not player_data.blueprint_add_mode then
			player.cursor_stack.set_stack("mining-patch-planner")
		end
		player_data.gui["blueprint_add_section"].visible = player_data.blueprint_add_mode
		player_data.gui["blueprint_add_button"].style = style_helper_blueprint_toggle(player_data.blueprint_add_mode)
		update_blueprint_selection(player_data)
	elseif evt_ele_tags["mpp_blueprint_receptacle"] then
		local cursor_stack = player.cursor_stack
		if (
			not cursor_stack or
			not cursor_stack.valid or
			not cursor_stack.valid_for_read or
			not cursor_stack.is_blueprint
		) then
			if not cursor_stack.is_blueprint then
				player.print({"mpp.msg_blueprint_valid"})
			end
			return nil
		elseif not mpp_util.validate_blueprint(player, cursor_stack) then
			return nil
		end

		local player_blueprints = player_data.blueprint_items
		local pending_slot = player_blueprints.find_empty_stack()

		if not pending_slot then
			player_blueprints.resize(#player_blueprints+1--[[@as uint16]])
			pending_slot = player_blueprints.find_empty_stack()
		end
		pending_slot.set_stack(cursor_stack)
		
		local blueprint_table = player_data.gui.tables["blueprints"]

		create_blueprint_entry(player_data, blueprint_table, pending_slot)

	elseif evt_ele_tags["mpp_fake_blueprint_button"] then
		local choices = player_data.choices
		local button = event.element
		local player_blueprints = player_data.blueprints
		local blueprint_flow = player_blueprints.flow[button.parent.index]
		
		if blueprint_flow == choices.blueprint_choice then
			return nil
		end
		
		if choices.blueprint_choice then
			local current_blueprint = choices.blueprint_choice
			local current_blueprint_button = player_blueprints.button[current_blueprint.index]
			current_blueprint_button.style = "mpp_fake_blueprint_button"
		end
		
		--local blueprint = player_blueprints.mapping[blueprint_flow.index]
		button.style = "mpp_fake_blueprint_button_selected"
		choices.blueprint_choice = blueprint_flow
	elseif evt_ele_tags["mpp_delete_blueprint_button"] then
		local choices = player_data.choices
		local deleted_index = evt_ele_tags["mpp_delete_blueprint_button"]
		local player_blueprints = player_data.blueprints
		if choices.blueprint_choice == player_blueprints.flow[deleted_index] then
			choices.blueprint_choice = nil
		end
		player_blueprints.mapping[deleted_index].clear()
		player_blueprints.flow[deleted_index].destroy()

		player_blueprints.button[deleted_index] = nil
		player_blueprints.delete[deleted_index] = nil
		player_blueprints.flow[deleted_index] = nil
		player_blueprints.mapping[deleted_index] = nil
	end
end
script.on_event(defines.events.on_gui_click, on_gui_click)
--script.on_event(defines.events.on_gui_checked_state_changed, gui.on_gui_checked_state_changed)

---@param event EventDataGuiSelectionStateChanged
local function on_gui_selection_state_changed(event)
	local player = game.players[event.player_index]
	if event.element.tags["mpp_drop_down"] then
		abort_blueprint_mode(player)
		---@type PlayerData
		local player_data = global.players[event.player_index]

		local action = event.element.tags["mpp_drop_down"]
		local value = layouts[event.element.selected_index].name
		player_data.choices.layout_choice = value
		update_selections(player_data)
	end
end
script.on_event(defines.events.on_gui_selection_state_changed, on_gui_selection_state_changed)

return gui
