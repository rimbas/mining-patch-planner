local mpp_util = require("mpp.mpp_util")
local builder  = require("mpp.builder")
local belt_planner = require("mpp.belt_planner")

local floor = math.floor
local EAST, NORTH, SOUTH, WEST, ROTATION = mpp_util.directions()
local coord_convert, coord_revert = mpp_util.coord_convert, mpp_util.coord_revert

local task_runner = {}

function task_runner.mining_patch_task(state)
	local layout = algorithm.layouts[state.layout_choice]

	local last_callback = state._callback
	---@type TickResult
	local tick_result

	if not __DebugAdapter then
		tick_result = layout:tick(state)
	else
		local success
		success, tick_result = pcall(layout.tick, layout, state)
		if success == false then
			game.print(tick_result)
			tick_result = false
		end
	end

	if last_callback == tick_result then
		if __DebugAdapter then
			table.remove(storage.tasks, 1)
		else
			error("Layout "..state.layout_choice.." step "..tostring(tick_result).." called itself again")
		end
	elseif tick_result == nil then
		if __DebugAdapter then
			game.print(("Callback for layout %s after call %s has no result"):format(state.layout_choice, state._callback))
			table.remove(storage.tasks, 1)

			---@type PlayerData
			local player_data = storage.players[state.player.index]
			player_data.last_state = nil
			-- TODO: fix rendering
			--rendering.destroy(state._preview_rectangle)
			if state._preview_rectangle.valid then
				state._preview_rectangle.destroy()
			end
			mpp_util.update_undo_button(player_data)
		else
			error("Layout "..state.layout_choice.." missing a callback name")
		end
	elseif tick_result == false then
		local player = state.player
		if state.blueprint then state.blueprint.clear() end
		if state.blueprint_inventory then state.blueprint_inventory.destroy() end
		-- TODO: fix rendering
		--rendering.destroy(state._preview_rectangle)
		if state._preview_rectangle.valid then
			state._preview_rectangle.destroy()
		end

		---@type PlayerData
		local player_data = storage.players[player.index]
		state._previous_state = nil
		player_data.tick_expires = math.huge
		if __DebugAdapter then
			player_data.last_state = state
		else
			player_data.last_state = {
				player = state.player,
				surface = state.surface,
				resources = state.resources,
				coords = state.coords,
				layout_choice = state.layout_choice,
				direction_choice = state.direction_choice,
				belt_choice = state.belt_choice,
				belt_planner_belts = state.belt_planner_belts,
				_preview_rectangle = state._preview_rectangle,
				_collected_ghosts = state._collected_ghosts,
				_render_objects = state._render_objects,
				_lane_info_rendering = state._lane_info_rendering,
			}
		end

		table.remove(storage.tasks, 1)
		-- TODO: sound
		-- player.play_sound{path="utility/build_blueprint_medium"}
		mpp_util.update_undo_button(player_data)
	elseif tick_result ~= true then
		state._callback = tick_result
	end
end

---comment
---@param state BeltinatorState
function task_runner.belt_plan_task(state)
	
	local coords = state.coords
	local belt_specification = state.belt_specification
	local count = belt_specification.count
	local tx, ty = state.belt_x, state.belt_y
	local world_direction = state.belt_direction
	
	local conv = coord_convert[state.direction_choice]
	-- local rot = mpp_util.bp_direction[state.direction_choice][direction]
	-- local bump = state.direction_choice == "north" or state.direction_choice EAST
	-- local belt_direction = mpp_util.clamped_rotation(((-defines.direction[state.direction_choice]) % ROTATION)-EAST, world_direction)
	local belt_direction = world_direction
	
	local create_entity = builder.create_entity_builder(state)
	
	if belt_direction == EAST then
		-- rong direction
	elseif belt_direction == WEST then
		-- algorithm to determine collection
	else
		local x_direction = belt_direction == NORTH and 1 or -1
		for i, belt in ipairs(belt_specification) do
			belt_planner.build_elbow(create_entity, {
			-- table.insert(segment_specification, {
				start_direction = WEST,
				end_direction = belt_direction,
				type = "elbow",
				x1 = belt.x1 - 1,
				y1 = belt.y,
				x2 = tx + (count - i) * x_direction,
				y2 = ty,
				belt_choice = state.belt_choice,
			})
		end
	end
end

return task_runner
