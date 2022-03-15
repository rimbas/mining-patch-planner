local conf = require("configuration")
require("migration")
local gui = require("gui")
local algorithm = require("algorithm")

script.on_init(function()
	global.players = {}
	global.tasks = {}
	conf.initialize_deconstruction_filter()

	for _, player in pairs(game.players) do
		conf.initialize_global(player.index)
	end
end)

---@param event EventData
local function task_runner(event)
	if #global.tasks == 0 then
		script.on_event(defines.events.on_tick, nil)
		return
	end

	---@type State
	local state = global.tasks[1]
	local layout = algorithm.layouts[state.layout_choice]

	layout:tick(state)
	if state.finished then
		rendering.destroy(state.preview_rectangle)
		table.remove(global.tasks, 1)
	end
end

script.on_event(defines.events.on_player_selected_area, function(event)
	local player = game.get_player(event.player_index)
	local cursor_stack = player.cursor_stack
	if not cursor_stack or not cursor_stack.valid or not cursor_stack.valid_for_read then return end
	if cursor_stack and cursor_stack.valid and cursor_stack.valid_for_read and cursor_stack.name ~= "mining-patch-planner" then return end

	if #event.entities == 0 then return nil end

	for _, task in ipairs(global.tasks) do
		if task.player == player then
			return
		end
	end

	local state, error = algorithm.on_player_selected_area(event)

	--rendering.clear("mining-patch-planner")

	if state then
		table.insert(global.tasks, state)
		script.on_event(defines.events.on_tick, task_runner)
	elseif error then
		player.print(error)
	end
end)

script.on_load(function()
	if global.tasks and #global.tasks > 0 then
		script.on_event(defines.events.on_tick, task_runner)
		for _, task in ipairs(global.tasks) do
			algorithm.layouts[task.layout_choice]:on_load(task)
		end
	end
end)

script.on_event(defines.events.on_player_cursor_stack_changed, function(e)
	local player = game.get_player(e.player_index)
	local cursor_stack = player.cursor_stack
	if cursor_stack and cursor_stack.valid and cursor_stack.valid_for_read and cursor_stack.name == "mining-patch-planner" then
		gui.show_interface(player)
	else
		gui.hide_interface(player)
	end
end)
