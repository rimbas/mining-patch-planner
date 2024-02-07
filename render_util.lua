local mpp_util = require("mpp_util")

local floor, ceil = math.floor, math.ceil
local min, max = math.min, math.max
local EAST, NORTH, SOUTH, WEST = mpp_util.directions()
local DIR = defines.direction

local render_util = {}

local triangles = {
	west={
		{{target={-.6, 0}}, {target={.6, -0.6}}, {target={.6, 0.6}}},
		{{target={-.4, 0}}, {target={.5, -0.45}}, {target={.5, 0.45}}},
	},
	east={
		{{target={.6, 0}}, {target={-.6, -0.6}}, {target={-.6, 0.6}}},
		{{target={.4, 0}}, {target={-.5, -0.45}}, {target={-.5, 0.45}}},
	},
	north={
		{{target={0, -.6}}, {target={-.6, .6}}, {target={.6, .6}}},
		{{target={0, -.4}}, {target={-.45, .5}}, {target={.45, .5}}},
	},
	south={
		{{target={0, .6}}, {target={-.6, -.6}}, {target={.6, -.6}}},
		{{target={0, .4}}, {target={-.45, -.5}}, {target={.45, -.5}}},
	},
}
local alignment = {
	west={"center", "center"},
	east={"center", "center"},
	north={"left", "right"},
	south={"right", "left"},
}

local bound_alignment = {
	west="right",
	east="left",
	north="center",
	south="center",
}

---Draws a belt lane overlay
---@param state State
---@param belt BeltSpecification
function render_util.draw_belt_lane(state, belt)
	local r = state._render_objects
	local c, ttl, player = state.coords, 0, {state.player}
	local x1, y1, x2, y2 = belt.x1, belt.y, math.max(belt.x1+2, belt.x2), belt.y
	local function l2w(x, y) -- local to world
		return mpp_util.revert(c.gx, c.gy, state.direction_choice, x, y, c.tw, c.th)
	end
	local c1, c2, c3 = {.9, .9, .9}, {0, 0, 0}, {.4, .4, .4}
	local w1, w2 = 4, 10
	if not belt.lane1 and not belt.lane2 then c1 = c3 end
	
	r[#r+1] = rendering.draw_line{ -- background main line
		surface=state.surface, players=player, only_in_alt_mode=true,
		width=w2, color=c2, time_to_live=ttl or 1,
		from=l2w(x1, y1), to=l2w(x2+.5, y1),
	}
	r[#r+1] = rendering.draw_line{ -- background vertical cap
		surface=state.surface, players=player, only_in_alt_mode=true,
		width=w2, color=c2, time_to_live=ttl or 1,
		from=l2w(x2+.5, y1-.6), to=l2w(x2+.5, y2+.6),
	}
	r[#r+1] = rendering.draw_polygon{ -- background arrow
		surface=state.surface, players=player, only_in_alt_mode=true,
		width=w2, color=c2, time_to_live=ttl or 1,
		target=l2w(x1, y1),
		vertices=triangles[state.direction_choice][1],
	}
	r[#r+1] = rendering.draw_line{ -- main line
		surface=state.surface, players=player, only_in_alt_mode=true,
		width=w1, color=c1, time_to_live=ttl or 1,
		from=l2w(x1-.2, y1), to=l2w(x2+.5, y1),
	}
	r[#r+1] = rendering.draw_line{ -- vertical cap
		surface=state.surface, players=player, only_in_alt_mode=true,
		width=w1, color=c1, time_to_live=ttl or 1,
		from=l2w(x2+.5, y1-.5), to=l2w(x2+.5, y2+.5),
	}
	r[#r+1] = rendering.draw_polygon{ -- arrow
		surface=state.surface, players=player, only_in_alt_mode=true,
		width=0, color=c1, time_to_live=ttl or 1,
		target=l2w(x1, y1),
		vertices=triangles[state.direction_choice][2],
	}
end

---Draws a belt lane overlay
---@param state State
---@param belt BeltSpecification
function render_util.draw_belt_stats(state, belt, belt_speed, speed1, speed2)
	local r = state._render_objects
	local c, ttl, player = state.coords, 0, {state.player}
	local x1, y1, x2, y2 = belt.x1, belt.y, belt.x2, belt.y
	local function l2w(x, y) -- local to world
		return mpp_util.revert(c.gx, c.gy, state.direction_choice, x, y, c.tw, c.th)
	end
	local c1, c2, c3, c4 = {.9, .9, .9}, {0, 0, 0}, {.9, 0, 0}, {.4, .4, .4}
	
	local ratio1 = speed1 / belt_speed
	local ratio2 = speed2 / belt_speed
	local function get_color(ratio)
		return ratio > 1.01 and c3 or ratio == 0 and c4 or c1
	end

	r[#r+1] = rendering.draw_text{
		surface=state.surface, players=player, only_in_alt_mode=true,
		color=get_color(ratio1), time_to_live=ttl or 1,
		alignment=alignment[state.direction_choice][1], vertical_alignment="middle",
		target=l2w(x1-2, y1-.6), scale=1.6,
		text=string.format("%.2fx", ratio1),
	}
	r[#r+1] = rendering.draw_text{
		surface=state.surface, players=player, only_in_alt_mode=true,
		color=get_color(ratio2), time_to_live=ttl or 1,
		alignment=alignment[state.direction_choice][2], vertical_alignment="middle",
		target=l2w(x1-2, y1+.6), scale=1.6,
		text=string.format("%.2fx", ratio2),
	}

end

---Draws a belt lane overlay
---@param state State
---@param pos_x number
---@param pos_y number
---@param speed1 number
---@param speed2 number
function render_util.draw_belt_total(state, pos_x, pos_y, speed1, speed2)
	local r = state._render_objects
	local c, ttl, player = state.coords, 0, {state.player}
	local function l2w(x, y, b) -- local to world
		if ({south=true, north=true})[state.direction_choice] then
			x = x + (b and -.5 or .5)
			y = y + (b and -.5 or .5)
		end
		return mpp_util.revert(c.gx, c.gy, state.direction_choice, x, y, c.tw, c.th)
	end
	local c1 = {0.7, 0.7, 1.0}

	local lower_bound = math.min(speed1, speed2)
	local upper_bound = math.max(speed1, speed2)

	r[#r+1] = rendering.draw_text{
		surface=state.surface, players=player, only_in_alt_mode=true,
		color=c1, time_to_live=ttl or 1,
		alignment=bound_alignment[state.direction_choice], vertical_alignment="middle",
		target=l2w(pos_x-4, pos_y-.6, false), scale=2,
		text={"mpp.msg_print_info_lane_saturation_belts", string.format("%.2fx", upper_bound), string.format("%.2fx", (lower_bound+upper_bound)/2)},
	}
	r[#r+1] = rendering.draw_text{
		surface=state.surface, players=player, only_in_alt_mode=true,
		color=c1, time_to_live=ttl or 1,
		alignment=bound_alignment[state.direction_choice], vertical_alignment="middle",
		target=l2w(pos_x-4, pos_y+.6, true), scale=2,
		text={"mpp.msg_print_info_lane_saturation_bounds", string.format("%.2fx", lower_bound), string.format("%.2fx", upper_bound)},
	}

end

---@class RendererParams
---@field origin MapPosition?
---@field target MapPosition?
---@field x number?
---@field y number?
---@field w number?
---@field h number?
---@field r number?
---@field c Color?
---@field left_top MapPosition?
---@field right_bottom MapPosition?

---this went off the rails
---@param event EventData.on_player_reverse_selected_area
---@return MppRendering
function render_util.renderer(event)

	---@param t RendererParams
	local function parametrizer(t, overlay)

		for k, v in pairs(overlay or {}) do t[k] = v end
		if t.x and t.y then t.origin = {t.x, t.y} end
		local target = t.origin or t.left_top
		local left_top, right_bottom = t.left_top or t.origin or target, t.right_bottom or t.origin

		if t.origin and t.w or t.h then
			t.w, t.h = t.w or t.h, t.h or t.w
			right_bottom = {(target[1] or target.x) + t.w, (target[2] or target.y) + t.h}
		elseif t.r then
			local r = t.r
			local ox, oy = target[1] or target.x, target[2] or target.y
			left_top = {ox-r, oy-r}
			right_bottom = {ox+r, oy+r}
		end

		local new = {
			surface = event.surface,
			players = {event.player_index},
			filled = false,
			radius = t.r or 1,
			color = t.c or t.color or {1, 1, 1},
			left_top = left_top,
			right_bottom = right_bottom,
			target = target, -- circles
			from = left_top,
			to = right_bottom, -- lines
			width = 1,
		}
		for k, v in pairs(t) do new[k]=v end
		for _, v in ipairs{"x", "y", "h", "w", "r", "origin"} do new[v]=nil end
		return new
	end

	local meta_renderer_meta = {}
	meta_renderer_meta.__index = function(self, k)
		return function(t, t2)
			return {
				rendering[k](
					parametrizer(t, t2)
				)
			}
	end end
	local rendering = setmetatable({}, meta_renderer_meta)

	---@class MppRendering
	local rendering_extension = {}

	---Draws an x between left_top and right_bottom
	---@param params RendererParams
	function rendering_extension.draw_cross(params)
		rendering.draw_line(params)
		rendering.draw_line({
			width = params.width,
			color = params.color,
			left_top={
				params.right_bottom[1],
				params.left_top[2]
			},
			right_bottom={
				params.left_top[1],
				params.right_bottom[2],
			}
		})
	end

	function rendering_extension.draw_rectangle_dashed(params)
		rendering.draw_line(params, {
			from={params.left_top[1], params.left_top[2]},
			to={params.right_bottom[1], params.left_top[2]},
			dash_offset = 0.0,
		})
		rendering.draw_line(params, {
			from={params.left_top[1], params.right_bottom[2]},
			to={params.right_bottom[1], params.right_bottom[2]},
			dash_offset = 0.5,
		})
		rendering.draw_line(params, {
			from={params.right_bottom[1], params.left_top[2]},
			to={params.right_bottom[1], params.right_bottom[2]},
			dash_offset = 0.0,
		})
		rendering.draw_line(params, {
			from={params.left_top[1], params.left_top[2]},
			to={params.left_top[1], params.right_bottom[2]},
			dash_offset = 0.5,
		})
	end

	local meta = {}
	function meta:__index(k)
		return function(t, t2)
			if rendering_extension[k] then
				rendering_extension[k](parametrizer(t, t2))
			else
				rendering[k](parametrizer(t, t2))
			end
		end
	end

	return setmetatable({}, meta)
end

---@param player_data PlayerData
---@param event EventData.on_player_reverse_selected_area
function render_util.draw_mining_drill_overlay(player_data, event)

	local renderer = render_util.renderer(event)

	local fx1, fy1 = event.area.left_top.x, event.area.left_top.y
	fx1, fy1 = floor(fx1), floor(fy1)
	local x, y = fx1 + 0.5, fy1 + 0.5
	local fx2, fy2 = event.area.right_bottom.x, event.area.right_bottom.y
	fx2, fy2 = ceil(fx2), ceil(fy2)

	--renderer.draw_cross{x=fx1, y=fy1, w=fx2-fx1, h=fy2-fy1}
	--renderer.draw_cross{x=fx1, y=fy1, w=2}

	local drill = mpp_util.miner_struct(player_data.choices.miner_choice)

	renderer.draw_circle{
		x = fx1 + drill.drop_pos.x,
		y = fy1 + drill.drop_pos.y,
		c = {0, 1, 0},
		r = 0.2,
	}

	-- drop pos
	renderer.draw_cross{
		x = fx1 + 0.5 + drill.out_x,
		y = fy1 + 0.5 + drill.out_y,
		r = 0.3,
	}

	-- drill origin
	renderer.draw_circle{
		x = fx1 + 0.5,
		y = fy1 + 0.5,
		width = 2,
		r = 0.4,
	}

	-- negative extent - cyan
	renderer.draw_cross{
		x = fx1 +.5 + drill.extent_negative,
		y = fy1 +.5 + drill.extent_negative,
		r = 0.25,
		c = {0, 0.8, 0.8},
	}

	-- positive extent - purple
	renderer.draw_cross{
		x = fx1 +.5 + drill.extent_positive,
		y = fy1 +.5 + drill.extent_positive,
		r = 0.25,
		c = {1, 0, 1},
	}

	renderer.draw_rectangle{
		x=fx1,
		y=fy1,
		w=drill.size,
		h=drill.size,
		width=3,
		gap_length=0.5,
		dash_length=0.5,
	}

	renderer.draw_rectangle_dashed{
		x=fx1 + drill.extent_negative,
		y=fy1 + drill.extent_negative,
		w=drill.area,
		h=drill.area,
		c={0.5, 0.5, 0.5},
		width=5,
		gap_length=0.5,
		dash_length=0.5,
	}

	renderer.draw_circle{ x = fx1, y = fy1, r = 0.1 }
	--renderer.draw_circle{ x = fx2, y = fy2, r = 0.15, color={1, 0, 0} }
end

function render_util.draw_patch_edge(state)

	local layout_categories = get_miner_categories(state, layout)
	local coords, filtered, found_resources, requires_fluid, resource_counts = process_entities(event.entities, layout_categories)
	state.coords = coords
	state.resources = filtered
	state.found_resources = found_resources
	state.requires_fluid = requires_fluid
	state.resource_counts = resource_counts
end

return render_util
