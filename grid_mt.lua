local mpp_util = require("mpp_util")

---@class GridRow: GridTile[]

---@class Grid
---@field [number] GridRow
local grid_mt = {}
grid_mt.__index = grid_mt

---@class Coords
---@field x1 double Top left corner
---@field y1 double Top left corner
---@field x2 double Bottom right corner
---@field y2 double Bottom right corner
---@field ix1 number Integer top left corner
---@field iy1 number Integer top left corner
---@field ix2 number Integer bottom right corner
---@field iy2 number Integer bottom right corner
---@field w integer Width
---@field h integer Height
---@field tw integer Width Rotation invariant width
---@field th integer Height Rotation invariant height
---@field gx double x1 but -1 for grid rendering
---@field gy double y1 but -1 for grid rendering
---@field extent_x1 number Internal grid dimensions
---@field extent_y1 number Internal grid dimensions
---@field extent_x2 number Internal grid dimensions
---@field extent_y2 number Internal grid dimensions

---@class GridTile
---@field amount number Amount of resource on tile
---@field neighbors_inner number
---@field neighbors_outer number
---@field neighbor_counts table<number, number> Convolution result
---@field x integer
---@field y integer
---@field gx double actual coordinate in surface
---@field gy double actual coordinate in surface
---@field boolean integer Is a miner consuming this tile
---@field built_on boolean|string Is tile occupied by a building entity
---@field consumed boolean Track if tile is covered by a mining drill

---comment
---@param x integer Grid coordinate
---@param y integer Grid coordinate
---@return GridTile|nil
function grid_mt:get_tile(x, y)
	local row = self[y]
	if row then return row[x] end
end

---Convolves resource count for a grid cell
---@param ox any
---@param oy any
---@param size any
function grid_mt:convolve(ox, oy, size)
	local nx1, nx2 = ox, ox+size - 1
	local ny1, ny2 = oy, oy+size - 1

	for y = ny1, ny2 do
		---@type table<number, GridTile>
		local row = self[y]
		if row == nil then goto continue_row end
		for x = nx1, nx2 do
			local tile = row[x]
			if tile == nil then goto continue_column end
			local counts = tile.neighbor_counts
			counts[size] = counts[size] + 1
			::continue_column::
		end
		::continue_row::
	end
end

---Convolves resource count for a grid cell
---@param ox any
---@param oy any
---@param size any
function grid_mt:convolve_inner(ox, oy, size)
	local nx1, nx2 = ox, ox+size - 1
	local ny1, ny2 = oy, oy+size - 1

	for y = ny1, ny2 do
		---@type table<number, GridTile>
		local row = self[y]
		if row == nil then goto continue_row end
		for x = nx1, nx2 do
			local tile = row[x]
			if tile == nil then goto continue_column end
			tile.neighbors_inner = tile.neighbors_inner + 1
			::continue_column::
		end
		::continue_row::
	end
end

---Convolves resource count for a grid cell
---@param ox any
---@param oy any
---@param size any
function grid_mt:convolve_outer(ox, oy, size)
	local nx1, nx2 = ox, ox+size - 1
	local ny1, ny2 = oy, oy+size - 1

	for y = ny1, ny2 do
		---@type table<number, GridTile>
		local row = self[y]
		if row == nil then goto continue_row end
		for x = nx1, nx2 do
			local tile = row[x]
			if tile == nil then goto continue_column end
			tile.neighbors_outer = tile.neighbors_outer + 1
			::continue_column::
		end
		::continue_row::
	end
end

---Marks tiles as consumed by a miner
---@param ox integer
---@param oy integer
function grid_mt:consume(ox, oy, size)
	local nx1, nx2 = ox, ox+size - 1
	local ny1, ny2 = oy, oy+size - 1

	for y = ny1, ny2 do
		local row = self[y]
		if row == nil then goto continue_row end
		for x = nx1, nx2 do
			local tile = row[x]
			if tile and tile.amount then
				tile.consumed = true
			end
		end
		::continue_row::
	end
end

---@param cx number
---@param cy number
---@param w number
---@param evenw boolean
---@param evenh boolean
---@deprecated
function grid_mt:consume_custom(cx, cy, w, evenw, evenh)
	local ox, oy = evenw and 1 or 0, evenh and 1 or 0
	local x1, x2 = cx+ox-w, cx+w
	for y = cy+oy-w, cy+w do
		local row = self[y]
		if row == nil then goto continue_row end
		for x = x1, x2 do
			local tile = row[x]
			if tile and tile.amount then
				tile.consumed = true
			end
		end
		::continue_row::
	end
end

---Marks tiles as consumed by a miner
---@param tiles GridTile[]
function grid_mt:clear_consumed(tiles)
	for _, tile in pairs(tiles) do
		---@cast tile GridTile
		tile.consumed = false
	end
end

---Builder function
---@param cx number x coord
---@param cy number y coord
---@param size number
---@param thing string Type of building
function grid_mt:build_thing(cx, cy, size, thing)
	for y = cx, cy+size do
		local row = self[y]
		if row == nil then goto continue_row end
		for x = cx, cx+size do
			local tile = row[x]
			if tile then
				tile.built_on = thing
			end
		end
		::continue_row::
	end
end

function grid_mt:build_thing_simple(cx, cy, thing)
	local row = self[cy]
	if row then
		local tile = row[cx]
		if tile then
			tile.built_on = thing
			return true
		end
	end
end

---@param t GhostSpecification
function grid_mt:build_specification(t)
	local cx, cy = t.grid_x, t.grid_y
	local left, right = t.padding_pre, t.padding_post
	local thing = t.thing

	if left == nil and right == nil then
		local row = self[cy]
		if row then
			local tile = row[cx]
			if tile then
				tile.built_on = thing
			end
		end
	else
		left, right = left or 0, right or 0
		local x1, x2 = cx-left, cx+right
		for y = cy-left, cy+right do
			local row = self[y]
			if row == nil then goto continue_row end
			for x = x1, x2 do
				local tile = row[x]
				if tile then
					tile.built_on = thing
				end
			end
			::continue_row::
		end
	end
end

---Finds if an entity type is built near
---@param cx number x coord
---@param cy number y coord
---@param thing string Type of building
---@param r number Radius
---@param even boolean Is even width building
---@return boolean
function grid_mt:find_thing(cx, cy, thing, r, even)
	local o = even and 1 or 0
	for y = cy+o-r, cy+r do
		local row = self[y]
		if row == nil then goto continue_row end
		for x = cx+o-r, cx+r do
			local tile = row[x]
			if tile and tile.built_on == thing then
				return true
			end
		end
		::continue_row::
	end
	return false
end

---Finds if an entity type is built near
---@param cx number x coord
---@param cy number y coord
---@param things table<string, true> Types of entities
---@param r number Radius
---@param even boolean Is even width building
---@return boolean
function grid_mt:find_thing_in(cx, cy, things, r, even)
	things = mpp_util.list_to_keys(things)
	local o = even and 1 or 0
	for y = cy+o-r, cy+r do
		local row = self[y]
		if row == nil then goto continue_row end
		for x = cx+o-r, cx+r do
			local tile = row[x]
			if tile and things[tile.built_on] then
				return true
			end
		end
		::continue_row::
	end
	return false
end

function grid_mt:build_miner(cx, cy, size)
	self:build_thing(cx, cy, size, "miner")
end

function grid_mt:build_miner_custom(cx, cy, w)
	for y = cy-w, cy+w do
		local row = self[y]
		if row == nil then goto continue_row end
		for x = cx-w, cx+w do
			local tile = row[x]
			if tile then
				tile.built_on = "miner"
			end
		end
		::continue_row::
	end
end

function grid_mt:get_unconsumed(ox, oy, size)
	local nx1, nx2 = ox, ox+size - 1
	local ny1, ny2 = oy, oy+size - 1
	local count = 0

	for y = ny1, ny2 do
		local row = self[y]
		if row == nil then goto continue_row end
		for x = nx1, nx2 do
			local tile = row[x]
			if tile then
				if tile.amount and not tile.consumed then
					count = count + 1
				end
			end
		end
		::continue_row::
	end
	return count
end

function grid_mt:get_unconsumed_custom(mx, my, w)
	local count = 0
	for y = my-w, my+w do
		local row = self[y]
		if row == nil then goto continue_row end
		for x = mx-w, mx+w do
			local tile = row[x]
			if tile then
				if tile.amount and not tile.consumed then
					count = count + 1
				end
			end
		end
		::continue_row::
	end
	return count
end

return grid_mt
