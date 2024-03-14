local table_insert = table.insert
local min, max = math.min, math.max

-- broke: implement power pole connection calculation yourself
-- woke: place ghosts to make factorio calculate the connections

---@class PowerPoleGrid
---@field [number] table<number, GridPole>
local pole_grid_mt = {}
pole_grid_mt.__index = pole_grid_mt

---@class GridPole
---@field ix number Position in the pole grid
---@field iy number Position in the pole grid
---@field grid_x number Position in the full grid
---@field grid_y number Position in the full grid
---@field built boolean? Does the pole need to be built
---@field entity LuaEntity? Pole ghost LuaEntity
---@field has_consumers boolean Does pole cover any powered items
---@field backtracked boolean
---@field connections table<GridPole, true>
---@field set_id number?
---@field no_light boolean?

function pole_grid_mt.new()
	local new = {
		_max_x = 1,
		_max_y = 1,
	}
	return setmetatable(new, pole_grid_mt)
end

---@param x number
---@param y number
---@param p GridPole
function pole_grid_mt:set_pole(x, y, p)
	if p.connections == nil then p.connections = {} end
	if not self[y] then self[y] = {} end
	self._max_x = max(self._max_x, x)
	self._max_y = max(self._max_y, y)
	self[y][x] = p
end

---@param p GridPole
function pole_grid_mt:add_pole(p)
	self:set_pole(p.ix, p.iy, p)
end

---@param x number
---@param y number
---@return GridPole | nil
function pole_grid_mt:get_pole(x, y)
	if self[y] then return self[y][x] end
end

---@param p1 GridPole
---@param p2 GridPole
---@param struct PoleStruct
---@return boolean
function pole_grid_mt:pole_reaches(p1, p2, struct)
	local x, y = p1.grid_x - p2.grid_x, p1.grid_y - p2.grid_y
	return (x * x + y * y) ^ 0.5 <= (struct.wire)
end

---@param P PoleStruct
---@return table<number, table<GridPole, true>>
function pole_grid_mt:find_connectivity(P)
	-- this went off the rails

	local all_poles = {}
	---@type table<GridPole, true>
	local not_visited = {}

	-- Make connections
	for y1 = 1, #self do
		local row = self[y1]
		for x1 = 1, #row do
			local pole = row[x1]
			if pole == nil then goto continue end

			table.insert(all_poles, pole)

			local right = self:get_pole(x1+1, y1)
			local bottom = self:get_pole(x1, y1+1)

			if right and self:pole_reaches(pole, right, P) then
				pole.connections[right], right.connections[pole] = true, true
			end

			if bottom and self:pole_reaches(pole, bottom, P) then
				pole.connections[bottom], bottom.connections[pole] = true, true
			end

			::continue::
		end
	end

	-- Process network connection sets
	local unconnected = {}
	local set_id, current_set = 1, {}
	local sets = {[0]=unconnected, [1]=current_set}
	for _, v in pairs(all_poles) do not_visited[v] = true end

	local function get_first(t) for value, _ in pairs(t) do return value end end
	---@param pole GridPole
	---@return number?
	local function is_continuation(pole)
		for other, _ in pairs(pole.connections) do
			if other.set_id then
				return other.set_id
			end
		end
	end

	---@param start_pole GridPole
	local function iterate_connections(start_pole)

		local continuation = is_continuation(start_pole)
		if not continuation and table_size(current_set) > 0 then
			if sets[set_id] == nil then
				sets[set_id] = current_set
			end
			current_set, set_id = {}, set_id + 1
		end

		---@param pole GridPole
		---@param depth_remaining number
		local function recurse_pole(pole, depth_remaining)
			not_visited[start_pole] = nil
			
			if not pole.has_consumers then
				unconnected[pole] = true
				return
			end

			pole.set_id = set_id
			current_set[pole] = true

			for other, _ in pairs(pole.connections) do
				if not_visited[other] and depth_remaining > 0 then
					recurse_pole(other, depth_remaining-1)
				end
			end
		end

		recurse_pole(start_pole, 5)
	end

	local remaining = get_first(not_visited)
	while remaining do
		iterate_connections(remaining)
		remaining = get_first(not_visited)
	end
	sets[set_id] = current_set

	return sets
end

---@param connectivity table<number, table<GridPole, true>>
---@return GridPole[]
function pole_grid_mt:ensure_connectivity(connectivity)
	---@type GridPole[]
	local connected = {}

	for set_id, pole_set in pairs(connectivity) do
		if set_id == 0 then goto skip_unconnected_set end
		for pole in pairs(pole_set) do
			table_insert(connected, pole)
		end
		::skip_unconnected_set::
	end

	return connected
end

return pole_grid_mt
