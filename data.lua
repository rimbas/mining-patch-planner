local graphics = "__mining-patch-planner__/graphics/"

data:extend{
	{
		type="selection-tool",
		name="mining-patch-planner",
		icon=graphics.."drill-icon.png",
		icon_size = 64,
		flags = {"only-in-cursor", "hidden", "spawnable", "not-stackable"},
        stack_size = 1,
		order="c[automated-construction]-e[miner-planner]",
		draw_label_for_cursor_render = true,
		selection_color = {r=0, g=0, b=1, a=0.5},
		selection_cursor_box_type="entity",
		selection_mode={"any-entity"},
		alt_selection_color = {r=0, g=0, b=1, a=0.5},
		alt_selection_cursor_box_type="entity",
		alt_selection_mode={"any-entity"},
		entity_filter_mode="whitelist",
		entity_type_filters = {"resource"},
	},
	{
		type="custom-input",
		name="mining-patch-planner-keybind",
		key_sequence="CONTROL + M",
		action="spawn-item",
		item_to_spawn="mining-patch-planner",
	},
	{
		type="shortcut",
		name="mining-patch-planner-shortcut",
		icon={
			filename=graphics.."drill-icon-toolbar-white.png",
			priority = "extra-high-no-scale",
			size=32,
			flags={"gui-icon"}
		},
		small_icon={
			filename=graphics.."drill-icon-toolbar-white.png",
			priority = "extra-high-no-scale",
			size=32,
			scale=1,
			flags={"gui-icon"}
		},
		disabled_small_icon={
			filename=graphics.."drill-icon-toolbar-disabled.png",
			priority = "extra-high-no-scale",
			size=32,
			scale=1,
			flags={"gui-icon"}
		},
		order="b[blueprints]-i[miner-planner]",
        action = "spawn-item",
		icon_size = 64,
		item_to_spawn="mining-patch-planner",
		style="blue",
		associated_control_input="mining-patch-planner-keybind",
		technology_to_unlock="",
	},
	{
		type = "sprite",
		name = "mpp_advanced_settings",
		filename = graphics.."advanced-settings.png",
		size = 64,
		mipmap_count = 3,
		flags = { "icon" },
	},
	{
		type = "sprite",
		name = "mpp_advanced_settings_black",
		filename = graphics.."advanced-settings-black.png",
		size = 64,
		mipmap_count = 3,
		flags = { "icon" },
	},
	{
		type = "sprite",
		name = "mpp_no_entity",
		filename = graphics.."no-entity.png",
		size = 64,
		mipmap_count = 3,
		flags = { "icon" },
	},
	{
		type = "sprite",
		name = "mpp_plus",
		filename = graphics.."plus.png",
		size = 64,
		mipmap_count = 3,
		flags = { "icon" },
	},
	{
		type = "sprite",
		name = "mpp_cross",
		filename = graphics.."cross.png",
		size = 64,
		mipmap_count = 2,
		flags = { "icon" },
	},
	{
		type = "sprite",
		name = "mpp_blueprint_add",
		filename = graphics.."blueprint_add.png",
		size = 64,
		mipmap_count = 2,
		flags = { "icon" },
	},
	{
		type = "sprite",
		name = "mpp_direction_north",
		filename = graphics.."arrow-north.png",
		size = 64,
		mipmap_count = 3,
		flags = { "icon" },
	},
	{
		type = "sprite",
		name = "mpp_direction_east",
		filename = graphics.."arrow-east.png",
		size = 64,
		mipmap_count = 3,
		flags = { "icon" },
	},
	{
		type = "sprite",
		name = "mpp_direction_south",
		filename = graphics.."arrow-south.png",
		size = 64,
		mipmap_count = 3,
		flags = { "icon" },
	},
	{
		type = "sprite",
		name = "mpp_direction_west",
		filename = graphics.."arrow-west.png",
		size = 64,
		mipmap_count = 3,
		flags = { "icon" },
	},
	{
		type = "sprite",
		name = "mpp_miner_coverage",
		filename = graphics.."miner_coverage.png",
		size = 64,
		mipmap_count = 2,
		flags = { "icon" },
	},
	{
		type = "sprite",
		name = "mpp_omit_landfill",
		filename = graphics.."omit_landfill.png",
		size = 64,
		mipmap_count = 3,
		flags = { "icon" },
	},
	{
		type = "sprite",
		name = "mpp_align_start",
		filename = graphics.."align_start.png",
		size = 64,
		mipmap_count = 1,
		flags = { "icon" },
	},
	{
		type = "sprite",
		name = "mpp_omit_deconstruct",
		filename = graphics.."omit_deconstruct.png",
		size = 64,
		mipmap_count = 2,
		flags = { "icon" },
	},
	{
		type = "sprite",
		name = "mpp_no_module",
		filename = graphics.."no_module.png",
		size = 64,
		mipmap_count = 1,
		flags = { "icon" },
	},
}

local default_style = data.raw["gui-style"].default

--- taken from flib
default_style.mpp_selected_frame_action_button = {
	type = "button_style",
	parent = "frame_action_button",
	default_graphical_set = {
		base = {position = {225, 17}, corner_size = 8},
		shadow = {position = {440, 24}, corner_size = 8, draw_type = "outer"},
	},
	hovered_graphical_set = {
		base = {position = {369, 17}, corner_size = 8},
		shadow = {position = {440, 24}, corner_size = 8, draw_type = "outer"},
	},
	clicked_graphical_set = {
		base = {position = {352, 17}, corner_size = 8},
		shadow = {position = {440, 24}, corner_size = 8, draw_type = "outer"},
	}
}

default_style.mpp_blueprint_mode_button = {
	type = "button_style",
	parent = "recipe_slot_button",
	size = 28,
}

default_style.mpp_blueprint_mode_button_active = {
	type = "button_style",
	parent = "recipe_slot_button",
	size = 28,
	default_graphical_set = {
		base = {position = {225, 17}, corner_size = 8},
		shadow = {position = {440, 24}, corner_size = 8, draw_type = "outer"},
	},
	hovered_graphical_set = {
		base = {position = {369, 17}, corner_size = 8},
		shadow = {position = {440, 24}, corner_size = 8, draw_type = "outer"},
	},
	clicked_graphical_set = {
		base = {position = {352, 17}, corner_size = 8},
		shadow = {position = {440, 24}, corner_size = 8, draw_type = "outer"},
	}
}

default_style.mpp_fake_item_placeholder = {
	type="image_style",
	vertically_stretchable = "on",
	horizontally_stretchable = "on",
	stretch_image_to_widget_size = true,
	size=32,
}

default_style.mpp_fake_blueprint_button = {
	type="button_style",
	parent="shortcut_bar_button_blue",
	padding=3,
	size=48,
}
default_style.mpp_delete_blueprint_button = {
	type="button_style",
	parent="shortcut_bar_button_red",
	padding=0,
	size=24,
	stretch_image_to_widget_size=true,
}

default_style.mpp_fake_blueprint_button_selected = {
	type="button_style",
	parent="shortcut_bar_button_blue",
	padding=3,
	size=48,
	default_graphical_set = {
		base = {position = {225, 17}, corner_size = 8},
		shadow = {position = {440, 24}, corner_size = 8, draw_type = "outer"},
	},
	hovered_graphical_set = {
		base = {position = {369, 17}, corner_size = 8},
		shadow = {position = {440, 24}, corner_size = 8, draw_type = "outer"},
	},
	clicked_graphical_set = {
		base = {position = {352, 17}, corner_size = 8},
		shadow = {position = {440, 24}, corner_size = 8, draw_type = "outer"},
	}
}

default_style.mpp_fake_blueprint_button_invalid = {
	type="button_style",
	parent="shortcut_bar_button_red",
	padding=3,
	size=48,
	stretch_image_to_widget_size=true,
}

default_style.mpp_fake_blueprint_table = {
	type="table_style",
	padding=0,
	cell_padding=0,
	horizontal_spacing=2,
	vertical_spacing=2,
}

default_style.mpp_fake_blueprint_sprite = {
	type="image_style",
	size=16,
	stretch_image_to_widget_size=true,
}
