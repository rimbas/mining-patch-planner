local floor, ceil = math.floor, math.ceil
local min, max = math.min, math.max

local common = require("layouts.common")
local simple = require("layouts.simple")
local mpp_util = require("mpp_util")
local builder = require("builder")
local coord_convert, coord_revert = mpp_util.coord_convert, mpp_util.coord_revert
local miner_direction, opposite = mpp_util.miner_direction, mpp_util.opposite
local mpp_revert = mpp_util.revert
local EAST, NORTH, SOUTH, WEST = mpp_util.directions()

---@class CompactLayout : SimpleLayout
local layout = table.deepcopy(simple)

layout.name = "compact"
layout.translation = {"mpp.settings_layout_choice_compact"}

layout.restrictions.miner_near_radius = {1, 1}
layout.restrictions.miner_far_radius = {1, 10e3}
layout.restrictions.uses_underground_belts = true
layout.restrictions.pole_omittable = true
layout.restrictions.pole_width = {1, 1}
layout.restrictions.pole_length = {7.5, 10e3}
layout.restrictions.pole_supply_area = {2.5, 10e3}
layout.restrictions.coverage_tuning = true
layout.restrictions.lamp_available = true
layout.restrictions.module_available = true
layout.restrictions.pipe_available = true

---@param state SimpleState
---@return PlacementAttempt
function layout:_placement_attempt(state, shift_x, shift_y)
	local grid = state.grid
	local size, near, far = state.miner.size, state.miner.near, state.miner.far
	local fullsize = state.miner.full_size
	local neighbor_sum = 0
	local far_neighbor_sum = 0
	local simple_density = 0
	local real_density = 0
	local miners, postponed = {}, {}
	local leech_sum = 0
	local empty_space = 0
	local lane_layout = {}
	
	local heuristic = self:_get_miner_placement_heuristic(state)

	local row_index = 1
	for ry = 1 + shift_y, state.coords.th + near, size + 0.5 do
		local y = ceil(ry)
		local column_index = 0
		lane_layout[#lane_layout+1] = {y = y+near, row_index = row_index}
		for x = 1 + shift_x, state.coords.tw, size do
			local tile = grid:get_tile(x, y)
			local center = grid:get_tile(x+near, y+near)
			column_index = column_index + 1
			if center == nil then goto next_column end
			local miner = {
				tile = tile,
				line = row_index,
				column = column_index,
				center = center,
			}
			if heuristic(center) then
				miners[#miners+1] = miner
				neighbor_sum = neighbor_sum + center.neighbor_count
				far_neighbor_sum = far_neighbor_sum + center.far_neighbor_count
				empty_space = empty_space + (size^2) - center.neighbor_count
				real_density = real_density + center.far_neighbor_count / (fullsize ^ 2)
				simple_density = simple_density + center.neighbor_count / (size ^ 2)
				leech_sum = leech_sum + max(0, center.far_neighbor_count - center.neighbor_count)
			elseif center.far_neighbor_count > 0 then
				postponed[#postponed+1] = miner
			end
			::next_column::
		end
		row_index = row_index + 1
	end
	
	local result = {
		sx=shift_x, sy=shift_y,
		miners=miners,
		miner_count=#miners,
		lane_layout=lane_layout,
		postponed=postponed,
		neighbor_sum=neighbor_sum,
		far_neighbor_sum=far_neighbor_sum,
		leech_sum=leech_sum,
		simple_density=simple_density,
		real_density=real_density,
		empty_space=empty_space,
		unconsumed_count=0,
		postponed_count=0,
	}

	common.process_postponed(state, result, miners, postponed)

	return result
end

---@param self CompactLayout
---@param state SimpleState
function layout:prepare_belt_layout(state)
	local pole_proto = game.entity_prototypes[state.pole_choice] or {supply_area_distance=3, max_wire_distance=9}
	local supply_area, wire_reach = 3.5, 9
	if pole_proto then
		supply_area, wire_reach = pole_proto.supply_area_distance, pole_proto.max_wire_distance
	end

	state.belts = {}

	if supply_area < 3 or wire_reach < 9 then
		state.pole_step = 6
		self:_placement_belts_small(state)
	else
		state.pole_step = 9
		self:_placement_belts_large(state)
	end

	return "prepare_pole_layout"
end

local function create_entity_que(belts)
	return function(t) belts[#belts+1] = t end
end

---@param self CompactLayout
function layout:_placement_belts_small(state)
	local m = state.miner
	local attempt = state.best_attempt
	local belt_choice = state.belt_choice
	local underground_belt = game.entity_prototypes[belt_choice].related_underground_belt.name

	local power_poles = {}
	state.power_poles_all = power_poles

	---@type table<number, MinerPlacement[]>
	local miner_lanes = {}
	local miner_lane_count = 0 -- highest index of a lane, because using # won't do the job if a lane is missing

	for _, miner in ipairs(attempt.miners) do
		local index = miner.line
		miner_lane_count = max(miner_lane_count, index)
		if not miner_lanes[index] then miner_lanes[index] = {} end
		local line = miner_lanes[index]
		line[#line+1] = miner
	end

	for _, lane in ipairs(miner_lanes) do
		table.sort(lane, function(a, b) return a.center.x < b.center.x end)
	end

	---@param lane MinerPlacement[]
	local function get_lane_length(lane) if lane then return lane[#lane].center.x end return 0 end
	---@param lane MinerPlacement[]
	local function get_lane_column(lane) if lane and #lane > 0 then return lane[#lane].column end return 0 end

	local belts = state.belts
	state.belt_count = 0

	local que_entity = create_entity_que(belts)

	local function belts_filled(x1, y, w)
		for x = x1, x1 + w do
			que_entity{name=belt_choice, direction=WEST, grid_x=x, grid_y=y, thing="belt"}
		end
	end

	for i = 1, miner_lane_count, 2 do
		local lane1 = miner_lanes[i]
		local lane2 = miner_lanes[i+1]

		local y = attempt.sy + m.size * i + ceil(i/2)
		local x0 = attempt.sx + 1
		
		local column_count = max(get_lane_column(lane1), get_lane_column(lane2))
		if column_count == 0 then goto continue_lane end

		state.belt_count = state.belt_count + 1

		local indices = {}
		if lane1 then for _, v in ipairs(lane1) do indices[v.column] = v end end
		if lane2 then for _, v in ipairs(lane2) do indices[v.column] = v end end

		for j = 1, column_count do
			local x1 = x0 + (j-1) * m.size
			if j % 2 == 1 then -- part one
				if indices[j] or indices[j+1] then
					que_entity{
						name=state.belt_choice, thing="belt", grid_x=x1, grid_y=y, direction=WEST,
					}
					local stopper = (j+1 > column_count) and state.belt_choice or underground_belt
					que_entity{
						name=stopper, thing="belt", grid_x=x1+1, grid_y=y, direction=WEST, type="output",
					}
					power_poles[#power_poles+1] = {
						x=x1+3, y=y,
						ix=1+floor(i/2), iy=1+floor(j/2),
						built = true,
					}
				else -- just a passthrough belt
					belts_filled(x1, y, m.size - 1)
				end
			elseif j % 2 == 0 then -- part two
				if indices[j-1] or indices[j] then
					que_entity{
						name=belt_choice, thing="belt", grid_x=x1+2, grid_y=y, direction=WEST,
					}
					que_entity{
						name=underground_belt, thing="belt", grid_x=x1+1, grid_y=y, direction=WEST,
					}
				else -- just a passthrough belt
					belts_filled(x1, y, m.size - 1)
				end
			end
		end
		
		::continue_lane::
	end

end


---@param self CompactLayout
function layout:_placement_belts_large(state)
	local c = state.coords
	local m = state.miner
	local g = state.grid
	local DIR = state.direction_choice
	local surface = state.surface
	local attempt = state.best_attempt
	local belt_choice = state.belt_choice
	local underground_belt = game.entity_prototypes[belt_choice].related_underground_belt.name

	local power_poles = {}
	state.power_poles_all = power_poles

	---@type table<number, MinerPlacement[]>
	local miner_lanes = {{}}
	local miner_lane_count = 0 -- highest index of a lane, because using # won't do the job if a lane is missing

	for _, miner in ipairs(attempt.miners) do
		local index = miner.line
		miner_lane_count = max(miner_lane_count, index)
		if not miner_lanes[index] then miner_lanes[index] = {} end
		local line = miner_lanes[index]
		line[#line+1] = miner
	end

	state.miner_lane_count = miner_lane_count

	local belts = state.belts

	local que_entity = create_entity_que(belts)

	for _, lane in pairs(miner_lanes) do
		table.sort(lane, function(a, b) return a.center.x < b.center.x end)
	end

	---@param lane MinerPlacement[]
	local function get_lane_length(lane) if lane and #lane > 0 then return lane[#lane].center.x or 0 end return 0 end
	---@param lane MinerPlacement[]
	local function get_lane_column(lane) if lane and #lane > 0 then return lane[#lane].column or 0 end return 0 end


	local function belts_filled(x1, y, w)
		for x = x1, x1 + w do
			que_entity{name=belt_choice, direction=WEST, grid_x=x, grid_y=y, thing="belt"}
		end
	end

	for i = 1, miner_lane_count, 2 do
		local lane1 = miner_lanes[i]
		local lane2 = miner_lanes[i+1]

		local y = attempt.sy + m.size * i + ceil(i/2)
		local x0 = attempt.sx + 1
		
		local column_count = max(get_lane_column(lane1), get_lane_column(lane2))
		if column_count == 0 then goto continue_lane end

		local indices = {}
		if lane1 then for _, v in ipairs(lane1) do indices[v.column] = v end end
		if lane2 then for _, v in ipairs(lane2) do indices[v.column] = v end end

		for j = 1, column_count do
			local x1 = x0 + (j-1) * m.size
			if j % 3 == 1 then -- part one
				if indices[j] or indices[j+1] or indices[j+2] then
					que_entity{
						name=belt_choice, grid_x=x1, grid_y=y, thing="belt", direction=WEST,
					}

					local stopper = (j+1 > column_count) and state.belt_choice or underground_belt
					que_entity{
						name=stopper, grid_x=x1+1, grid_y=y, thing="belt", direction=WEST,
						type="output",
					}
					power_poles[#power_poles+1] = {
						x=x1+3, y=y,
						ix=1+floor(i/2), iy=1+floor(j/2),
						built = true,
					}
				else -- just a passthrough belt
					belts_filled(x1, y, m.size - 1)
				end
			elseif j % 3 == 2 then -- part two
				if indices[j-1] or indices[j] or indices[j+1] then
					que_entity{
						name=underground_belt, grid_x=x1+1, grid_y=y, thing="belt", direction=WEST,
						type="input",
					}
					que_entity{
						name=belt_choice, grid_x=x1+2, grid_y=y, thing="belt", direction=WEST,
					}
				else -- just a passthrough belt
					belts_filled(x1, y, m.size - 1)
				end
			elseif j % 3 == 0 then
				belts_filled(x1, y, m.size - 1)
			end
		end
		
		::continue_lane::
	end
end

---@param self CompactLayout
---@param state SimpleState
function layout:prepare_pole_layout(state)
	return "unagressive_deconstruct"
end

function layout:_prepare_deconstruct_specification(state)
	state.deconstruct_specification = {
		x = state.best_attempt.sx - 1,
		y = state.best_attempt.sy,
		width = state.miner_max_column * state.miner.size + 1,
		height = state.miner_lane_count * state.miner.size + ceil(state.miner_lane_count/2),
	}

	return state.deconstruct_specification
end

---@param self CompactLayout
---@param state SimpleState
---@return CallbackState
function layout:placement_belts(state)
	local create_entity = builder.create_entity_builder(state)

	for i, belt in ipairs(state.belts --[=[@as GhostSpecification[]]=]) do
		create_entity(belt)
	end

	return "placement_poles"
end

---@param self CompactLayout
---@param state SimpleState
function layout:placement_lamp(state)
	local _next_step = "placement_landfill"
	if not state.lamp_choice then
		return _next_step
	end

	local create_entity = builder.create_entity_builder(state)
	local c = state.coords
	local grid = state.grid
	local surface = state.surface

	local sx, sy = -1, 0
	local lamp_spacing = true
	if state.pole_step > 7 then lamp_spacing = false end

	for _, pole in ipairs(state.power_poles_all) do
		local x, y = pole.x, pole.y
		local ix, iy = pole.ix, pole.iy
		local tile = grid:get_tile(x+sx, y+sy)
		local skippable_lamp = iy % 2 == 1 and ix % 2 == 1
		if tile and pole.built and (not lamp_spacing or skippable_lamp) then
			tile.built_on = "lamp"
			local tx, ty = coord_revert[state.direction_choice](x + sx, y + sy, c.tw, c.th)
			create_entity{
				name="small-lamp",
				thing="lamp",
				grid_x = tx,
				grid_y = ty,
			}
		end
	end

	return _next_step
end

return layout
