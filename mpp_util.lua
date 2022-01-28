local floor, ceil = math.floor, math.ceil

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

function mpp_util.map(t, key)
	local new = {}
	for _, v in pairs(t) do new[v[key]] = v end
	return new
end

function mpp_util.revert(gx, gy, direction, x, y, w, h)
	local tx, ty = coord_revert[direction](x, y, w, h)
	return {gx + tx, gy + ty}
end

return mpp_util
