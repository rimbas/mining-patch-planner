local conf = {}

conf.default_config = {
	layout_choice = "horizontal",
	horizontal_direction = "right",
	vertical_direction = "down",
	belt_choice = "transport-belt",
	miner_choice = "electric-mining-drill",
	lamp = false,

	gui = {},
}

---@param player LuaPlayer
function conf.initialize_global(player)
	global.players[player.index] = conf.default_config
end

return conf
