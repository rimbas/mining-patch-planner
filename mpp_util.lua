local enums = require("enums")
local floor, ceil = math.floor, math.ceil
local min, max = math.min, math.max

local mpp_util = {}

local coord_convert = {
	west = function(x, y, w, h) return x, y end,
	east = function(x, y, w, h) return w-x+1, h-y+1 end,
	south = function(x, y, w, h) return h-y+1, x end,
	north = function(x, y, w, h) return y, w-x+1 end,
}
mpp_util.coord_convert = coord_convert

local coord_revert = {
	west = coord_convert.west,
	east = coord_convert.east,
	north = coord_convert.south,
	south = coord_convert.north,
}
mpp_util.coord_revert = coord_revert

mpp_util.miner_direction = {west="south",east="north",north="west",south="east"}
mpp_util.belt_direction = {west="north", east="south", north="east", south="west"}
mpp_util.opposite = {west="east",east="west",north="south",south="north"}

do
	local d = defines.direction
	local t = {
		west = {
			[d.north] = d.north,
			[d.east] = d.east,
			[d.south] = d.south,
			[d.west] = d.west,
		},
		north = {
			[d.north] = d.east,
			[d.east] = d.south,
			[d.south] = d.west,
			[d.west] = d.north,
		},
		east = {
			[d.north] = d.south,
			[d.east] = d.west,
			[d.south] = d.north,
			[d.west] = d.east,
		},
		south = {
			[d.north] = d.west,
			[d.east] = d.north,
			[d.south] = d.east,
			[d.west] = d.south,
		},
	}
	mpp_util.bp_direction = t
end

---A mining drill's origin (0, 0) is the top left corner
---The spawn location is (x, y), rotations need to rotate around
---@class MinerStruct
---@field name string
---@field size number Physical miner size
---@field parity (-1|0) Parity offset for even sized drills, -1 when odd
---@field resource_categories table<string, boolean>
---@field radius float Mining area reach
---@field area number Full coverage span of the miner
---@field module_inventory_size number
---@field x number Drill x origin
---@field y number Drill y origin
---@field w number Collision width
---@field h number Collision height
---@field drop_pos MapPosition Raw drop position
---@field out_x integer Resource drop position x
---@field out_y integer Resource drop position y
---@field extent_negative number 
---@field extent_positive number
---@field supports_fluids boolean

---@type table<string, MinerStruct>
local miner_struct_cache = {}

---Calculates values for drill sizes and extents
---@param mining_drill_name string
---@return MinerStruct
function mpp_util.miner_struct(mining_drill_name)
	local cached = miner_struct_cache[mining_drill_name]
	if cached then return cached end
	
	local miner_proto = game.entity_prototypes[mining_drill_name]
	---@diagnostic disable-next-line: missing-fields
	local miner = {} --[[@as MinerStruct]]
	local cbox = miner_proto.collision_box
	local cbox_tl, cbox_br = cbox.left_top, cbox.right_bottom
	local cw, ch = cbox_br.x - cbox_tl.x, cbox_br.y - cbox_tl.y
	miner.w, miner.h = ceil(cw), ceil(ch)
	if miner.w ~= miner.h then
		-- we have a problem ?
	end
	miner.size = miner.w
	miner.parity = miner.size % 2 - 1
	miner.x, miner.y = miner.w / 2, miner.h / 2
	miner.radius = miner_proto.mining_drill_radius
	miner.area = ceil(miner_proto.mining_drill_radius * 2)
	miner.resource_categories = miner_proto.resource_categories
	miner.name = miner_proto.name
	miner.module_inventory_size = miner_proto.module_inventory_size
	miner.extent_negative = floor(miner.size * 0.5) - floor(miner_proto.mining_drill_radius) + miner.parity
	miner.extent_positive = miner.extent_negative + miner.area - 1

	local nauvis = game.get_surface("nauvis") --[[@as LuaSurface]]

	local dummy = nauvis.create_entity{
		name = mining_drill_name,
		position = {miner.x, miner.y},
	}

	if dummy then
		miner.drop_pos = dummy.drop_position
		miner.out_x = floor(dummy.drop_position.x)
		miner.out_y = floor(dummy.drop_position.y)
		dummy.destroy()
	else
		-- hardcoded fallback
		local dx, dy = floor(miner.size / 2) + miner.parity, -1
		miner.drop_pos = { dx+.5, -0.296875, x = dx+.5, y = -0.296875 }
		miner.out_x = dx
		miner.out_y = dy
	end

	--[[ pipe height stuff
	if miner_proto.fluidbox_prototypes and #miner_proto.fluidbox_prototypes > 0 then
		local connections = miner_proto.fluidbox_prototypes[1].pipe_connections

		for _, conn in pairs(connections) do
			---@cast conn FluidBoxConnection
			--game.print(conn)
		end

	else
		miner.supports_fluids = false
	end
	--]]

	return miner
end

---@class PoleStruct
---@field place boolean Flag if poles are to be actually placed
---@field size number
---@field radius number Power supply reach
---@field supply_width number Full width of supply reach
---@field wire number Max wire distance

---@type table<string, PoleStruct>
local pole_struct_cache = {}

---@param pole_name string
---@return PoleStruct
function mpp_util.pole_struct(pole_name)
	local cached_struct = pole_struct_cache[pole_name]
	if cached_struct then return cached_struct end

	local pole_proto = game.entity_prototypes[pole_name]
	if pole_proto then
		local pole = {place=true}
		local cbox = pole_proto.collision_box
		pole.size = ceil(cbox.right_bottom.x - cbox.left_top.x)
		local radius = pole_proto.supply_area_distance
		pole.supply_width = radius * 2 + ((radius * 2 % 2) == 0 and 1 or 0)
		pole.radius = pole.supply_width / 2
		pole.wire = pole_proto.max_wire_distance

		pole_struct_cache[pole_name] = pole
		return pole
	end
	return {
		place = false,
		size = 1,
		supply_width = 7,
		radius = 3.5,
		wire = 9,
	}
end

local hardcoded_pipes = {}

---@param pipe_name string Name of the normal pipe
---@return string|nil, LuaEntityPrototype|nil
function mpp_util.find_underground_pipe(pipe_name)
	if hardcoded_pipes[pipe_name] then
		return hardcoded_pipes[pipe_name], game.entity_prototypes[hardcoded_pipes[pipe_name]]
	end
	local ground_name = pipe_name.."-to-ground"
	local ground_proto = game.entity_prototypes[ground_name]
	if ground_proto then
		return ground_name, ground_proto
	end
	return nil, nil
end

function mpp_util.revert(gx, gy, direction, x, y, w, h)
	local tx, ty = coord_revert[direction](x, y, w, h)
	return {gx + tx, gy + ty}
end

---Calculates needed power pole count
---@param state SimpleState
function mpp_util.calculate_pole_coverage(state, miner_count, lane_count, shifted)
	shifted = shifted or false
	local cov = {}
	local pole_proto = game.entity_prototypes[state.pole_choice]
	local m = mpp_util.miner_struct(state.miner_choice)
	local p = mpp_util.pole_struct(game.entity_prototypes[state.pole_choice])

	local miner_coverage = max((miner_count-1)*m.size+miner_count, 1)

	-- Shift subtract
	local shift_subtract = shifted and 2 or 0
	local covered_miners = ceil((p.supply_width - shift_subtract) / m.size)
	local miner_step = covered_miners * m.size
	local miner_coverage_excess = ceil(miner_count / covered_miners) * covered_miners - miner_count

	local capable_span = false
	if floor(p.wire) >= miner_step and m.size ~= p.supply_width then
		capable_span = true
	else
		miner_step = floor(p.wire)
	end

	local pole_start = m.size
	if capable_span then
		if covered_miners % 2 == 0 then
			pole_start = m.size * 2
		elseif miner_count % covered_miners == 0 then
			pole_start = pole_start + m.size
		end
	end

	cov.pole_start = pole_start
	cov.pole_step = miner_step
	cov.full_miner_width = miner_count * m.size

	cov.lane_start = 0
	cov.lane_step = m.size * 2 + 2
	local lane_pairs = floor(lane_count / 2)
	local lane_coverage = ceil((p.radius-1) / (m.size + 0.5))
	if lane_coverage > 1 then
		cov.lane_start = (ceil(lane_pairs / 2) % 2 == 0 and 1 or 0) * (m.size * 2 + 2)
		cov.lane_step = lane_coverage * (m.size * 2 + 2)
	end

	return cov
end

---Calculates needed power pole count
---@param state SimpleState
function mpp_util.calculate_shifted_pole_coverage(state, miner_count)
	local cov = {}
	local pole_proto = game.entity_prototypes[state.pole_choice]
	local m = mpp_util.miner_struct(state.miner_choice)
	local p = mpp_util.pole_struct(state.pole_choice)

	local miner_coverage = max((miner_count-1)*m.size+miner_count, 1)

	-- Shift subtract
	local covered_miners = ceil(p.supply_width / m.size)
	local miner_step = covered_miners * m.size
	local miner_coverage_excess = ceil(miner_count / covered_miners) * covered_miners - miner_count

	if floor(p.wire) < miner_step and covered_miners > 1 then
		covered_miners = covered_miners - 1
		miner_step = covered_miners * m.size
	end

	local pole_start = m.size - 1
	if covered_miners % 2 == 0 then
		pole_start = m.near * 2
	elseif covered_miners > 1 and miner_count % covered_miners == 0 then
		pole_start = pole_start + m.size
	end

	cov.pole_start = pole_start
	cov.pole_step = miner_step
	cov.full_miner_width = miner_count * m.size

	return cov
end

---@param t table
---@param func function
---@return true | nil
function mpp_util.table_find(t, func)
	for k, v in pairs(t) do
		if func(v) then return true end
	end
end

---@param t table
---@param m LuaObject 
function mpp_util.table_mapping(t, m)
	for k, v in pairs(t) do
		if k == m then return v end
	end
end

---@param player LuaPlayer
---@param blueprint LuaItemStack
function mpp_util.validate_blueprint(player, blueprint)
	if not blueprint.blueprint_snap_to_grid then
		player.print({"mpp.msg_blueprint_undefined_grid"})
		return false
	end
	
	local miners, _ = enums.get_available_miners()
	local cost = blueprint.cost_to_build
	for name, _ in pairs(miners) do
		if cost[name] then
			return true
		end
	end
	
	player.print({"mpp.msg_blueprint_no_miner"})
	return false
end

function mpp_util.keys_to_set(...)
	local set, temp = {}, {}
	for _, t in pairs{...} do
		for k, _ in pairs(t) do
			temp[k] = true
		end
	end
	for k, _  in pairs(temp) do
		set[#set+1] = k
	end
	table.sort(set)
	return set
end

function mpp_util.list_to_keys(t)
	local temp = {}
	for _, k in ipairs(t) do
		temp[k] = true
	end
	return temp
end

---@param bp LuaItemStack
function mpp_util.blueprint_label(bp)
	local label = bp.label
	if label then
		if #label > 30 then
			return string.sub(label, 0, 28) .. "...", label
		end
		return label
	else
		return {"", {"gui-blueprint.unnamed-blueprint"}, " ", bp.item_number}
	end
end

---Filters out a list
---@param t any
---@param func any
function table.filter(t, func)
	local new = {}
	for k, v in ipairs(t) do
		if func(v) then new[#new+1] = v end
	end
	return new
end

function table.map(t, func)
	local new = {}
	for k, v in pairs(t) do
		new[k] = func(v)
	end
	return new
end

function table.mapkey(t, func)
	local new = {}
	for k, v in pairs(t) do
		new[func(v)] = v
	end
	return new
end

function math.divmod(a, b)
	return math.floor(a / b), a % b
end

---@class CollisionBoxProperties
---@field w number
---@field h number
---@field near number
---@field [1] boolean
---@field [2] boolean

-- LuaEntityPrototype#tile_height was added in 1.1.64, I'm developing on 1.1.61
local even_width_memoize = {}
---Gets properties of entity collision box
---@param name string
---@return CollisionBoxProperties
function mpp_util.entity_even_width(name)
	local check = even_width_memoize[name]
	if check then return check end
	local proto = game.entity_prototypes[name]
	local cbox = proto.collision_box
	local cbox_tl, cbox_br = cbox.left_top, cbox.right_bottom
	local cw, ch = cbox_br.x - cbox_tl.x, cbox_br.y - cbox_tl.y
	local w, h = ceil(cw), ceil(ch)
	local res = {w % 2 ~= 1, h % 2 ~= 1, w=w, h=h, near=floor(w/2)}
	even_width_memoize[name] = res
	return res
end

--- local EAST, NORTH, SOUTH, WEST = mpp_util.directions()
function mpp_util.directions()
	return
		defines.direction.east,
		defines.direction.north,
		defines.direction.south,
		defines.direction.west
end

---@param player_index uint
---@return uint
function mpp_util.get_display_duration(player_index)
	return settings.get_player_settings(player_index)["mpp-lane-filling-info-duration"].value * 60 --[[@as uint]]
end

---@param player_index uint
---@return boolean
function mpp_util.get_dump_state(player_index)
	return settings.get_player_settings(player_index)["mpp-dump-heuristics-data"].value --[[@as boolean]]
end

function mpp_util.wrap_tooltip(tooltip)
	return tooltip and {"", "     ", tooltip}
end

return mpp_util
