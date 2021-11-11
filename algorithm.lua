local floor, ceil = math.floor, math.ceil
local min, max = math.min, math.max

---@class GridRow: GridTile[]

---@class Grid
---@field data GridRow[]
---@field coords Coords
---@field resource_tiles GridTile[]
---@field miner_characteristics MinerCharacteristics
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

local direction_map = {
	left = defines.direction.west,
	right = defines.direction.east,
	up = defines.direction.north,
	down = defines.direction.south,
}

local resource_categories = {
	["basic-solid"] = true,
	["hard-resource"] = true,
}

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
---@field built_on boolean Is tile occupied by a building entity

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
	local row = self.data[y]
	if row then return row[x] end
end

---@class MinerCharacteristics
---@field w integer Tile width
---@field h integer Tile height
---@field near integer Bounds radius of the miner
---@field far integer Reach radius of the miner
---@field cbox BoundingBox Miner bounding box
---@field miner_name string Miner name
---@field resource_categories table<string, boolean> Resource categories miner can mine

---Convolves a resource patch reach using characteristics of a miner
---@param x integer coordinate of the resource patch
---@param y integer coordinate of the resource patch
function grid_mt:convolve(x, y)
	local near, far = self.miner_characteristics.near, self.miner_characteristics.far
	for sy = -far, far do
		local row = self.data[y+sy]
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

---Marks tiles as consumed by a miner
---@param cx integer
---@param cy integer
function grid_mt:consume(cx, cy)
	local mc = self.miner_characteristics
	local w, h, near, far = mc.w, mc.h, mc.near, mc.far
	for y = -far, far do
		local row = self.data[cy+y]
		if row == nil then goto continue_row end
		for x = -far, far do
			local tile = row[cx+x]
			if tile then
				tile.consumed = tile.consumed + 1
				if -near <= x and x <= near and -near <= y and y <= near then
					tile.built_on = true
				end
			end
		end
		::continue_row::
	end
end

function grid_mt:get_unconsumed(mx, my)
	local far = self.miner_characteristics.far
	local count = 0
	for y = -far, far do
		local row = self.data[my+y]
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

---@param player LuaPlayer
---@return MinerCharacteristics
local function get_miner_characteristics(player)
	local miner_name = global.players[player.index].miner_choice
	local miner = game.entity_prototypes[miner_name]
	local mining_drill_radius = floor(miner.mining_drill_radius)
	local cbox = miner.collision_box
	local cbox_tl, cbox_br = cbox.left_top, cbox.right_bottom
	local cw, ch = cbox_br.x - cbox_tl.x, cbox_br.y - cbox_tl.y
	local tw, th = ceil(cw), ceil(ch)
	local near_w, near_h = floor(tw * 0.5), floor(th * 0.5)
	local far = floor(mining_drill_radius)
	return {
		w = tw, h = th,
		cbox=cbox,
		near_w = near_w, near_h = near_h,
		near = near_w, far = far,
		miner_name = miner_name,
		resource_categories = miner.resource_categories,
	}
end

---Filters resource entity list and returns patch coordinates and size
---@param entities LuaEntity[]
---@return Coords, LuaEntity[]
---@return table<string, string> @key:resource name; value:resource category
local function process_entities(entities)
	local filtered = {}
	local found_resources = {} -- resource.name: resource_category
	local x1, y1 = math.huge, math.huge
	local x2, y2 = -math.huge, -math.huge
	for _, entity in pairs(entities) do
		local category = entity.prototype["resource_category"]
		if resource_categories[category] then
			found_resources[entity.name] = category
			filtered[#filtered+1] = entity
			local x, y = entity.position.x, entity.position.y
			if x < x1 then x1 = x end
			if y < y1 then y1 = y end
			if x2 < x then x2 = x end
			if y2 < y then y2 = y end
		end
	end
	local coords = {
		x1 = x1, y1 = y1, x2 = x2, y2 = y2,
		ix1 = floor(x1), iy1 = floor(y1),
		ix2 = ceil(x2), iy2 = ceil(y2),
	}
	coords.w, coords.h = coords.ix2 - coords.ix1, coords.iy2 - coords.iy1
	return coords, filtered, found_resources
end

---Initializes grid structure
---@param coords Coords
---@param miner_characteristics MinerCharacteristics
---@return Grid
local function initialize_grid(coords, miner_characteristics, event)
	local grid = {
		coords=coords,
		miner_characteristics=miner_characteristics,
		near=miner_characteristics.near, miner_characteristics.far,
		data={},
		event=event,
	}
	local mw, mh = miner_characteristics.w, miner_characteristics.h

	for y = 1-mh, coords.h + mh do
		local row = {}
		grid.data[y] = row
		for x = 1-mw, coords.w + mw do
			row[x] = {
				contains_resource = false,
				resources = 0,
				neighbor_count = 0,
				far_neighbor_count = 0,
				x=x, y=y,
				gx=coords.x1+x-1, gy=coords.y1+y-1,
				consumed=0,
				built_on=false,
			}
		end
	end

	local ply_global = global.players[grid.event.player_index]
	grid.layout_choice = ply_global.layout_choice
	grid.horizontal_direction = ply_global.horizontal_direction
	grid.vertical_direction = ply_global.vertical_direction
	grid.belt_choice = ply_global.belt_choice
	grid.miner_choice = ply_global.miner_choice
	grid.lamp = ply_global.lamp
	grid.direction = ply_global[ply_global.layout_choice.."_direction"]

	--[[ debug visualisation - bounding box
	rendering.draw_rectangle{
		surface=event.surface,
		left_top={coords.ix1, coords.iy1}, right_bottom={coords.ix2, coords.iy2},
		filled=false, width=4, color={0, 0, 1, 1},
		players={event.player_index},
	}

	rendering.draw_rectangle{
		surface=event.surface,
		left_top={coords.ix1-mw, coords.iy1-mw}, right_bottom={coords.ix1+coords.w+mw, coords.iy1+coords.h+mw},
		filled=false, width=4, color={0, 0.5, 1, 1},
		players={event.player_index},
	}

	rendering.draw_circle{
		surface = event.surface,
		filled = false,
		color = {1, 0, 0, 1},
		width = 5,
		target = {coords.ix1, coords.iy1},
		radius = 0.5,
		players={event.player_index},
	}
	--]]

	return setmetatable(grid, grid_mt)
end

---Processes entities into the grid
---@param grid Grid
---@param entities LuaEntity[]
local function process_grid(grid, entities)
	local x1, y1 = grid.coords.x1, grid.coords.y1
	local resource_tiles = {}
	grid.resource_tiles = resource_tiles
	for _, ent in ipairs(entities) do
		local x, y = ent.position.x, ent.position.y
		local ix, iy = ceil(x-x1)+1, ceil(y-y1)+1
		local tile = grid:get_tile(ix, iy)
		tile.contains_resource = true
		tile.amount = ent.amount
		grid:convolve(ix, iy)
		resource_tiles[#resource_tiles+1] = tile
	end

	--[[ debug visualisation
	for _, ent in ipairs(entities) do
		local x, y = ent.position.x, ent.position.y
		local ix, iy = ceil(x-x1)+1, ceil(y-y1)+1
		local tile = grid:get_tile(ix, iy)
		rendering.draw_circle{
			surface = grid.event.surface,
			filled = false,
			color = {1, 1, 1, 1},
			width = 2,
			target = {tile.gx, tile.gy},
			radius = 0.5,
			players={grid.event.player_index},
		}
		rendering.draw_text{
			surface=grid.event.surface,
			text=""..tile.neighbor_count,
			target={tile.gx,tile.gy-.66},
			color={1, 1, 1, 1},
			alignment="center",
			players={grid.event.player_index},
		}
		rendering.draw_text{
			surface=grid.event.surface,
			text=""..tile.far_neighbor_count,
			target={tile.gx,tile.gy-.33},
			color={1, 1, 1, 1},
			alignment="center",
			players={grid.event.player_index},
		}
	end
	--]]
end

---First pass of the algorithm
---@param grid Grid
---@param shift_x integer
---@param shift_y integer
local function first_pass_horizontal(grid, shift_x, shift_y)
	local near, far = grid.miner_characteristics.near, grid.miner_characteristics.far
	local mw, mh = grid.miner_characteristics.w, grid.miner_characteristics.h
	local neighbor_sum = 0
	local miners, postponed = {}, {}
	local miner_index = 1

	local neighbor_cap = floor((mw ^ 2) / 2)
	local far_neighbor_cap = floor((mw + far - near)^2 / 5 * 2)

	-- Start with the top left corner
	for y = 1 + shift_y, grid.coords.h, mh + 1 do
		for x = 1 + shift_x, grid.coords.w, mw do
			-- Get the "center tile" covered by miner
			local tile = grid:get_tile(x, y)
			local center = grid:get_tile(x+near, y+near)
			local miner = {
				tile = tile,
				line = miner_index,
				center=center,
			}
			if center.neighbor_count > neighbor_cap or (center.far_neighbor_count > far_neighbor_cap and center.neighbor_count > mw) then
				miners[#miners+1] = miner
				neighbor_sum = neighbor_sum + center.neighbor_count
			elseif center.far_neighbor_count > 0 then
				postponed[#postponed+1] = miner
			end
		end
		miner_index = miner_index + 1
	end
	return miners, postponed, neighbor_sum
end

---First pass of the algorithm
---Let's just copypaste the horizontal variant and change a few things, that certainly won't cause problems...
---@param grid Grid
---@param shift_x integer
---@param shift_y integer
local function first_pass_vertical(grid, shift_x, shift_y)
	local near, far = grid.miner_characteristics.near, grid.miner_characteristics.far
	local mw, mh = grid.miner_characteristics.w, grid.miner_characteristics.h
	local neighbor_sum = 0
	local miners, postponed = {}, {}
	local miner_index = 1

	local neighbor_cap = floor((mw ^ 2) / 2)
	local far_neighbor_cap = floor((mw + far - near)^2 / 5 * 2)

	-- Start with the top left corner
	for x = 1 + shift_x, grid.coords.w, mw + 1 do
		for y = 1 + shift_y, grid.coords.h, mh do
			-- Get the "center tile" covered by miner
			local tile = grid:get_tile(x, y)
			local center = grid:get_tile(x+near, y+near)
			local miner = {
				tile = tile,
				line = miner_index,
				center=center,
			}
			if center.neighbor_count > neighbor_cap or (center.far_neighbor_count > far_neighbor_cap and center.neighbor_count > mw) then
				miners[#miners+1] = miner
				neighbor_sum = neighbor_sum + center.neighbor_count
			elseif center.far_neighbor_count > 0 then
				postponed[#postponed+1] = miner
			end
		end
		miner_index = miner_index + 1
	end
	return miners, postponed, neighbor_sum
end

---Second pass that adds miners on loose resources
---@param grid Grid
---@param miners Miner[]
---@param postponed Miner[]
local function second_pass(grid, miners, postponed)
	local mc = grid.miner_characteristics
	local w, h, near, far = mc.w, mc.h, mc.near, mc.far

	for _, miner in ipairs(miners) do
		grid:consume(miner.center.x, miner.center.y)
	end

	--[[ debug visualisation - unconsumed tiles
	for k, tile in pairs(grid.resource_tiles) do
		if tile.consumed == 0 then
			rendering.draw_circle{
				surface = grid.event.surface,
				filled = false,
				color = {1, 1, 1, 1},
				width = 2,
				target = {tile.gx, tile.gy},
				radius = 0.5,
				players={grid.event.player_index},
			}
		end
	end
	--]]

	for _, miner in ipairs(postponed) do
		local center = miner.center
		miner.unconsumed = grid:get_unconsumed(center.x, center.y)
	end

	table.sort(postponed, function(a, b)
		if a.unconsumed == b.unconsumed then
			return a.center.far_neighbor_count > b.center.far_neighbor_count
		end
		return a.unconsumed > b.unconsumed
	end)

	for _, miner in ipairs(postponed) do
		local center = miner.center
		local unconsumed_count = grid:get_unconsumed(center.x, center.y)
		if unconsumed_count > 0 then
			grid:consume(center.x, center.y)
			local tile = miner.tile
			miners[#miners+1] = miner
		end
	end

end

---@param grid Grid
---@param shift any
---@return Miner[] @miner candidates
---@return Miner[] @postponed miner candidates
---@return number @First heuristic value - ratio of "touched resources" and miner count
---@return number @Second heuristic value - number of postponed miners
local function calculate_attempt(grid, shift)
	local placement_function
	if shift.layout_choice == "horizontal" then
		placement_function = first_pass_horizontal
	elseif shift.layout_choice == "vertical" then
		placement_function = first_pass_vertical
	end
	local miners, postponed, far_neighbor_sum = placement_function(grid, shift.x, shift.y)
	return miners, postponed, far_neighbor_sum / #miners, #postponed
end

---@class Algorithm
local algorithm = {}

---@param event EventDataPlayerSelectedArea
function algorithm.on_player_selected_area(event)
	if event.item ~= "mining-patch-planner" then return end
	local player = game.get_player(event.player_index)
	local surface = event.surface
	local mc = get_miner_characteristics(player)

	local coords, filtered_entities, found_resources = process_entities(event.entities)

	for k, v in pairs(found_resources) do
		if not mc.resource_categories[v] then
			local miner_name = game.entity_prototypes[mc.miner_name].localised_name
			local resource_name = game.entity_prototypes[k].localised_name
			--player.print(("Can't build on this resource patch with selected miner \"%s\" because it can't mine resource \"%s\""):format())
			player.print{"", {"mpp.msg_miner_err_1"}, " \"", miner_name, "\" ", {"mpp.msg_miner_err_2"}, " \"", resource_name, "\""}
			return
		end
	end

	--rendering.clear("mining-patch-planner")

	local minimum_span = mc.w * 2 + 1
	if #filtered_entities == 0 then return end
	if global.players[event.player_index].layout_choice == "horizontal" then
		if coords.h < minimum_span or coords.w < mc.w then
			player.print("Span is too small to create a layout")
			return
		end
	else
		if coords.h < mc.w or coords.w < minimum_span then
			player.print("Span is too small to create a layout")
			return
		end
	end
	if coords.h > 200 or coords.w > 200 then
		player.print("Span is too big to create a layout")
		return
	end

	local grid = initialize_grid(coords, mc, event)
	process_grid(grid, filtered_entities)

	-- This is just bruteforcing, right?
	local attempts = {}
	for sy = -mc.near, mc.near do
		for sx = -mc.near, mc.near do
			if grid.layout_choice == "horizontal" then
				attempts[#attempts+1] = {x=sx, y=sy, layout_choice="horizontal"}
			elseif grid.layout_choice == "vertical" then
				attempts[#attempts+1] = {x=sx, y=sy, layout_choice="vertical"}
			end
		end
	end

	local best_attempt = attempts[1]
	local best_miners, best_postponed, best_heuristic, best_heuristic2 = calculate_attempt(grid, best_attempt)

	for i = 2, #attempts do
		local miners, postponed, heuristic, heuristic2 = calculate_attempt(grid, attempts[i])

		if heuristic2 < best_heuristic2 or (heuristic2 == best_heuristic2 and heuristic > best_heuristic) then
			best_miners, best_postponed, best_heuristic, best_heuristic2 = miners, postponed, heuristic, heuristic2
			best_attempt = attempts[i]
		end
	end

	second_pass(grid, best_miners, best_postponed)

	--[[ debug visualisation
	for i, miner in ipairs(best_miners) do
		local tile = miner.tile
		local center = miner.center
		rendering.draw_circle{
			surface = event.surface,
			filled = false,
			color = {0.0, 1, 0, 1},
			width = 5,
			target = {center.gx, center.gy},
			radius = mc.w / 2,
			players={event.player_index},
		}
	end
	--]]

	surface.deconstruct_area{
		force=player.force,
		player=player.index,
		area={
			left_top={coords.x1-mc.far, coords.y1-mc.far},
			right_bottom={coords.x2+mc.far, coords.y2+mc.far}
		}
	}

	local water_tiles = surface.find_tiles_filtered{
		area={
			left_top={coords.x1-mc.w-1, coords.y1-mc.h-1},
			right_bottom={coords.x2+mc.w+1, coords.y2+mc.h+1}
		},
		collision_mask="water-tile"
	}

	-- Around here any semblance of sanity falls apart

	---@type table<number, Miner>
	local miner_lines = {}
	local miner_line_number = 0 -- highest index of a group, because using # won't do the job if a line is skipped
	for _, miner in ipairs(best_miners) do
		local index = miner.line
		miner_line_number = max(miner_line_number, index)
		if not miner_lines[index] then miner_lines[index] = {} end
		local line = miner_lines[index]
		line[#line+1] = miner
	end

	local function line_sorting_horizontal(a, b)
		return a.center.gx < b.center.gx
	end
	local function line_sorting_vertical(a, b)
		return a.center.gy < b.center.gy
	end
	for _, line in ipairs(miner_lines) do
		local sorting_function = grid.layout_choice == "horizontal" and line_sorting_horizontal or line_sorting_vertical
		table.sort(line, sorting_function)
	end

	-- Direction to switch miner output side per lane
	local function direction_transform(index)
		if best_attempt.layout_choice == "horizontal" then
			if index % 2 == 1 then
				return defines.direction.south
			else
				return defines.direction.north
			end
		elseif best_attempt.layout_choice == "vertical" then
			if index % 2 == 1 then
				return defines.direction.east
			else
				return defines.direction.west
			end
		end
	end

	local function belt_direction()
		if best_attempt.layout_choice == "horizontal" then
			return direction_map[grid.horizontal_direction]
		elseif best_attempt.layout_choice == "vertical" then
			return direction_map[grid.vertical_direction]
		end
	end

	local function place_miner_ghost(miner)
		local center = miner.center
		local can_place = surface.can_place_entity{
			name=grid.miner_choice,
			force=player.force,
			position={center.gx, center.gy},
			direction=direction_transform(miner.line),
			build_check_type=defines.build_check_type.script_ghost,
			forced=true,
		}
		if can_place then
			surface.create_entity{
				name="entity-ghost",
				player=event.player_index,
				force=player.force,
				position={center.gx, center.gy},
				direction=direction_transform(miner.line),
				inner_name=grid.miner_choice,
			}
		end
	end

	---@type Miner
	local direction_extremum = best_miners[1] -- probably possible to get this with best_attempt shift and coords
	for _, miner in ipairs(best_miners) do
		place_miner_ghost(miner)
		if grid.layout_choice == "horizontal" then
			if grid.horizontal_direction == "left" then
				local extremum = miner.center.gx
				if extremum < direction_extremum.center.gx then direction_extremum = miner end
			else
				local extremum = miner.center.gx
				if extremum > direction_extremum.center.gx then direction_extremum = miner end
			end
		else
			if grid.vertical_direction == "up" then
				local extremum = miner.center.gy
				if extremum < direction_extremum.center.gy then direction_extremum = miner end
			else
				local extremum = miner.center.gy
				if extremum > direction_extremum.center.gy then direction_extremum = miner end
			end
		end
	end

	---Gets the extreme points of a belt line
	---@param line Miner[]
	---@param line2 Miner[]
	---@param y double Belt y coordinate
	---@return double @Minimum x coordinate
	---@return double @Maximum x coordinate
	local function belt_horizontal(line, line2, y)
		---@type Miner
		local miner_from_x = line and line[1].center.gx or (line2[1].center.gx + mc.far * 2 + 1)
		if line2 then miner_from_x = min(miner_from_x, line2[1].center.gx) end
		---@type Miner
		local miner_to_x = line and line[#line].center.gx or (line2[#line2].center.gx + mc.far * 2 + 1)
		if line2 then miner_to_x = max(miner_to_x, line2[#line2].center.gx) end
		if grid.horizontal_direction == "right" then
			miner_from_x = miner_from_x - mc.near
			miner_to_x = direction_extremum.center.gx + mc.near
		else
			miner_from_x = direction_extremum.center.gx - mc.near
			miner_to_x = miner_to_x + mc.near
		end

		--[[ debug visualisation
		rendering.draw_circle{surface = event.surface, filled = false, color = {0, 1, 0, 1}, width = 5, target = {miner_to_x, y}, radius = 0.5, players={event.player_index}, }
		rendering.draw_circle{surface = event.surface, filled = false, color = {0, 0, 1, 1}, width = 5, target = {miner_from_x, y}, radius = 0.5, players={event.player_index}, }
		rendering.draw_line{surface=event.surface, width=3, color={1, 1, 1, 1}, from={miner_from_x, y}, to={miner_to_x, y}, }
		--]]
		return miner_from_x, miner_to_x
	end

	--- Gets the extremes of a belt line
	---@param line Miner[]
	---@param line2 Miner[]
	---@param x double Belt x coordinate
	---@return double @Minimum y coordinate
	---@return double @Maximum y coordinate
	local function belt_vertical(line, line2, x)
		---@type Miner
		local miner_from_y = line and line[1].center.gy or (line2[1].center.gy + mc.far * 2 + 1)
		if line2 then miner_from_y = min(miner_from_y, line2[1].center.gy) end
		---@type Miner
		local miner_to_y = line and line[#line].center.gy or (line2[#line2].center.gy + mc.far * 2 + 1)
		if line2 then miner_to_y = max(miner_to_y, line2[#line2].center.gy) end
		if grid.vertical_direction == "down" then
			miner_from_y = miner_from_y - mc.near
			miner_to_y = direction_extremum.center.gy + mc.near
		else
			miner_from_y = direction_extremum.center.gy - mc.near
			miner_to_y = miner_to_y + mc.near
		end

		--[[ debug visualisation
		rendering.draw_circle{surface = event.surface, filled = false, color = {0, 1, 0, 1}, width = 5, target = {x, miner_to_y}, radius = 0.5, players={event.player_index}, }
		rendering.draw_circle{surface = event.surface, filled = false, color = {0, 0, 1, 1}, width = 5, target = {x, miner_from_y}, radius = 0.5, players={event.player_index}, }
		rendering.draw_line{surface=event.surface, width=3, color={1, 1, 1, 1}, from={x, miner_from_y}, to={x, miner_to_y}, }
		--]]
		return miner_from_y, miner_to_y
	end

	local function place_belt_ghost(x, y)
		local ix, iy = ceil(x-coords.x1)+1, ceil(y-coords.y1)+1 -- belt position on the grid
		local tile = grid:get_tile(ix, iy)
		if tile then tile.built_on = true end

		local can_place = surface.can_place_entity{
			name=grid.belt_choice,
			force=player.force,
			position={x, y},
			direction=belt_direction(),
			build_check_type=defines.build_check_type.script_ghost,
			forced=true,
		}
		if can_place then
			surface.create_entity{
				name="entity-ghost",
				player=event.player_index,
				force=player.force,
				position={x, y},
				direction=belt_direction(),
				inner_name=grid.belt_choice,
			}
		end
	end

	local longest_belt = 0 -- longest belt to get "actual" width/height of a layout
	for i = 1, miner_line_number, 2 do
		local line = miner_lines[i]
		local line2 = miner_lines[i+1]
		if line or line2 then
			if grid.layout_choice == "horizontal" then
				local y = coords.iy1 + best_attempt.y + (mc.h + 1) * i - .5
				local min_x, max_x = belt_horizontal(line, line2, y)
				longest_belt = max(longest_belt, max_x - min_x + 1)
				for x = min_x, max_x do
					place_belt_ghost(x, y)
				end
			else
				local x = coords.ix1 + best_attempt.x + (mc.w + 1) * i - .5
				local min_y, max_y = belt_vertical(line, line2, x)
				longest_belt = max(longest_belt, max_y - min_y + 1)
				for y = min_y, max_y do
					place_belt_ghost(x, y)
				end
			end
		end
	end

	--- Power poles
	local power_poles = {}
	local power_poles_all = {}
	do
		-- Hardcoding medium electric poles
		local wire_reach = 9
		local miner_gap = (mc.w * 2 + 1) + 1

		local pole_start_x, pole_start_y = 0, 0
		local pole_x, pole_y
		local step_x, step_y
		if grid.layout_choice == "horizontal" then
			pole_start_x = floor(longest_belt / 3) % 3 == 0 and 3 or 0
			pole_x, pole_y = coords.x1 + best_attempt.x + 1, coords.y1 + best_attempt.y - 1
			step_x, step_y = wire_reach, miner_gap
		else
			pole_start_y = floor(longest_belt / 3) % 3 == 0 and 3 or 0
			pole_x, pole_y = coords.x1 + best_attempt.x - 1, coords.y1 + best_attempt.y + 1
			step_x, step_y = miner_gap, wire_reach
		end

		---comment
		---@param pole integer Power pole
		local function get_covered_miners(pole)
			local ix, iy = pole.ix, pole.iy
			--local tile = grid:get_tile(ix, iy)

			for sy = -2, 2 do
				for sx = -2, 2 do
					local tile = grid:get_tile(ix+sx, iy+sy)
					if tile and tile.built_on then
						return true
					end
				end
			end
		end

		local function place_powerpole_ghost(pole)
			local x, y = pole.x, pole.y
			local tile = grid:get_tile(pole.ix, pole.iy)
			if tile then tile.built_on = true end

			local can_place = surface.can_place_entity{
				name="medium-electric-pole",
				force=player.force,
				position={x, y},
				build_check_type=defines.build_check_type.script_ghost,
				forced=true,
			}
			if can_place then
				surface.create_entity{
					name="entity-ghost",
					player=event.player_index,
					force=player.force,
					position={x, y},
					inner_name="medium-electric-pole",
				}
			end
		end

		local power_pole_ty = 1
		for iy=pole_start_y, coords.h + mc.far, step_y do
			local row = {}
			power_poles[power_pole_ty] = row
			local power_pole_tx = 1
			for ix=pole_start_x, coords.w + mc.far, step_x do
				local power_pole = {
					x = pole_x+ix, y = pole_y+iy,
					tx = power_pole_tx, ty = power_pole_ty,
					built=false,
				}
				power_pole.ix, power_pole.iy = ceil(power_pole.x-coords.x1)+1, ceil(power_pole.y-coords.y1)+1
				row[ix] = power_pole
				power_poles_all[#power_poles_all+1] = power_pole

				if get_covered_miners(power_pole) then
					power_pole.built = true
					place_powerpole_ghost(power_pole)
				end

				--[[ debug visualisation - power pole distribution
				rendering.draw_circle{
					surface = event.surface,
					filled = false,
					color = {1, 1, 1, 1},
					width = 5,
					target = {pole_x+ix, pole_y+iy},
					radius = 0.4,
					players={event.player_index},
				}
				--]]
				power_pole_tx = power_pole_tx + 1
			end
			power_pole_ty = power_pole_ty + 1
		end

	end

	--lamps
	if grid.lamp then
		local off_lx, off_ly
		if grid.direction == "left" then
			off_lx, off_ly = -1, 0
		elseif grid.direction == "right" then
			off_lx, off_ly = 1, 0
		else
			off_lx, off_ly = 0, 1
		end

		local function place_lamp_ghost(pole, off_x, off_y)
			local x, y = pole.x+off_x, pole.y+off_y
			local tile = grid:get_tile(pole.ix+off_x, pole.iy+off_y)
			if tile then tile.built_on = true end

			local can_place = surface.can_place_entity{
				name="small-lamp",
				force=player.force,
				position={x, y},
				build_check_type=defines.build_check_type.script_ghost,
				forced=true,
			}
			if can_place then
				surface.create_entity{
					name="entity-ghost",
					player=event.player_index,
					force=player.force,
					position={x, y},
					inner_name="small-lamp",
				}
			end
		end

		for _, pole in ipairs(power_poles_all) do
			if pole.built then
				place_lamp_ghost(pole, off_lx, off_ly)
			end
		end
	end

	for _, water_tile in pairs(water_tiles) do
		local ix, iy = water_tile.position.x, water_tile.position.y
		local x, y = ix - coords.ix1 + 1, iy - coords.iy1 + 1
		local tile = grid:get_tile(x, y)
		if tile and tile.built_on then
			surface.create_entity{
				name="tile-ghost",
				player=event.player_index,
				force=player.force,
				position=water_tile.position,
				inner_name="landfill",
			}
		end
	end

	--[[ debug visualisation - built_on tiles
	for _, row in pairs(grid.data) do
		---@type GridTile
		for _, tile in pairs(row) do
			if tile.built_on then
				rendering.draw_circle{
					surface = event.surface,
					filled = false, width=1,
					color = {0, 1, 1, 1},
					target = {tile.gx, tile.gy},
					radius = 0.3,
					players={event.player_index},
				}
			end
		end
	end
	--]]

end

return algorithm
