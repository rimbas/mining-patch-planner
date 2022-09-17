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

---@class MinerStruct
---@field name string
---@field size number Physical miner size
---@field w number Miner collision width
---@field h number Miner collision height
---@field far number Far radius
---@field near number Close radius
---@field resource_categories table<string, boolean>
---@field full_size number Full span of the miner

---@param miner_proto LuaEntityPrototype
---@return MinerStruct
function mpp_util.miner_struct(miner_proto)
	local miner = {}
	miner.far = floor(miner_proto.mining_drill_radius)
	local cbox = miner_proto.collision_box
	local cbox_tl, cbox_br = cbox.left_top, cbox.right_bottom
	local cw, ch = cbox_br.x - cbox_tl.x, cbox_br.y - cbox_tl.y
	miner.w, miner.h = ceil(cw), ceil(ch)
	miner.size = miner.w
	miner.full_size = miner.far * 2 + 1
	miner.near =  floor(miner.size * 0.5)
	miner.resource_categories = miner_proto.resource_categories
	miner.name = miner_proto.name

	return miner
end

---@class PoleStruct
---@field size number
---@field radius number
---@field supply_width number
---@field wire number max wire distance

---@param pole_proto LuaEntityPrototype
---@return PoleStruct
function mpp_util.pole_struct(pole_proto)
	if pole_proto then
		local pole = {}
		local cbox = pole_proto.collision_box
		pole.size = ceil(cbox.right_bottom.x - cbox.left_top.x)
		local radius = pole_proto.supply_area_distance
		pole.supply_width = radius * 2 + ((radius * 2 % 2) == 0 and 1 or 0)
		pole.radius = pole.supply_width / 2
		pole.wire = pole_proto.max_wire_distance

		return pole
	end
	return {
		size = 1,
		supply_width = 7,
		radius = 3.5,
		wire = 9,
	}
end

function mpp_util.map(t, key)
	local new = {}
	for _, v in pairs(t) do new[v[key]] = v end
	return new
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
	local m = mpp_util.miner_struct(game.entity_prototypes[state.miner_choice])
	local p = mpp_util.pole_struct(game.entity_prototypes[state.pole_choice])

	local miner_coverage = max((miner_count-1)*m.far+miner_count, 1)

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

	local pole_start = m.near
	if capable_span then
		if covered_miners % 2 == 0 then
			pole_start = m.near * 2
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
	local m = mpp_util.miner_struct(game.entity_prototypes[state.miner_choice])
	local p = mpp_util.pole_struct(game.entity_prototypes[state.pole_choice])

	local miner_coverage = max((miner_count-1)*m.far+miner_count, 1)

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
	return true
end


return mpp_util
