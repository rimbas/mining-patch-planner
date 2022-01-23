
---@class GridRow: GridTile[]

---@class Grid
---@field data GridRow[]
---@field coords Coords
---@field resource_tiles GridTile[]
---@field miner MinerStruct
---@field event EventDataPlayerSelectedArea
---@field layout_choice string
---@field horizontal_direction string
---@field vertical_direction string
---@field direction string
---@field belt_choice string
---@field miner_choice string
---@field lamp boolean
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

---@class GridTile
---@field contains_resource boolean
---@field resources integer
---@field neighbor_count integer
---@field far_neighbor_count integer
---@field x integer
---@field y integer
---@field gx double actual coordinate in surface
---@field gy double actual coordinate in surface
---@field consumed integer How many miners are consuming this tile
---@field built_on boolean|string Is tile occupied by a building entity

---@class Miner
---@field tile GridTile
---@field center GridTile Center tile
---@field line integer -- Line index of the miner
---@field unconsumed integer

---comment
---@param x integer Grid coordinate
---@param y integer Grid coordinate
---@return GridTile
function grid_mt:get_tile(x, y)
	local row = self[y]
	if row then return row[x] end
end

---Convolves a resource patch reach using characteristics of a miner
---@param x integer coordinate of the resource patch
---@param y integer coordinate of the resource patch
function grid_mt:convolve(x, y)
	local near, far = self.miner.near, self.miner.far
	for sy = -far, far do
		local row = self[y+sy]
		if row == nil then goto continue_row end
		for sx = -far, far do
			local tile = row[x+sx]
			if tile == nil then goto continue_column end

			tile.far_neighbor_count = tile.far_neighbor_count + 1
			if -near <= sx and sx <= near and -near <= sy and sy <= near then
				tile.neighbor_count = tile.neighbor_count + 1
			end
			::continue_column::
		end
		::continue_row::
	end
end

---Marks tiles as consumed and built on by a miner
---@param cx integer
---@param cy integer
function grid_mt:consume(cx, cy)
	local mc = self.miner
	local w, h, near, far = mc.size, mc.size, mc.near, mc.far
	for y = -far, far do
		local row = self[cy+y]
		if row == nil then goto continue_row end
		for x = -far, far do
			local tile = row[cx+x]
			if tile then
				tile.consumed = tile.consumed + 1
				if -near <= x and x <= near and -near <= y and y <= near then
					tile.built_on = "miner"
				end
			end
		end
		::continue_row::
	end
end

function grid_mt:get_unconsumed(mx, my)
	local far = self.miner.far
	local count = 0
	for y = -far, far do
		local row = self[my+y]
		if row == nil then goto continue_row end
		for x = -far, far do
			local tile = row[mx+x]
			if tile then
				if tile.contains_resource and tile.consumed == 0 then
					count = count + 1
				end
			end
		end
		::continue_row::
	end
	return count
end

return grid_mt
