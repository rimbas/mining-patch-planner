local enums = {}

local cached_miners, cached_resources = nil, nil
local fluid_resources = {}
local miner_blacklist = {
	["se-core-miner-drill"] = true
}

function enums.get_default_miner()
	if game.active_mods["nullius"] then
		return "nullius-medium-miner-1"
	end
	return "electric-mining-drill"
end

function enums.get_available_miners()
	enums.get_available_miners = function() return cached_miners, cached_resources end

	local all_miners = game.get_filtered_entity_prototypes{{filter="type", type="mining-drill"}}
	---@type table<string, LuaEntityPrototype>
	local all_resources = game.get_filtered_entity_prototypes{{filter="type", type="resource"}}
	---@type table<string, LuaResourceCategoryPrototype>
	local all_categories = game.resource_category_prototypes

	if game.active_mods["Cursed-FMD"] then
		for name, proto in pairs(all_resources) do
			local mineable_properties = proto.mineable_properties
			for _, product in ipairs(mineable_properties.products) do
				if product.type == "fluid" then
					fluid_resources[name] = true
					break
				end
			end
		end

		local mangled_categories = {}

		local miners = {}
		for name, proto in pairs(all_miners) do
			if proto.flags and proto.flags.hidden then goto continue_miner end
			if string.find(name, ";") then -- Cursed-FMD hack
				for resource_name, _ in pairs(proto.resource_categories) do
					if not fluid_resources[resource_name] and not string.find(resource_name, "core-fragment") then
						mangled_categories[resource_name] = true
					end
				end
			else
				if miner_blacklist[name] then goto continue_miner end

				for resource_name, _ in pairs(proto.resource_categories) do
					if not fluid_resources[resource_name] and not string.find(resource_name, "core-fragment") then
						miners[name] = proto
					end
				end
			end
			::continue_miner::
		end
		cached_miners = miners
		cached_resources = mangled_categories
	else
		local miners = {}
		for name, proto in pairs(all_miners) do
			if proto.flags.hidden then goto continue_miner end
			if not proto.resource_categories["basic-solid"] then goto continue_miner end

			miners[name] = proto

			::continue_miner::
		end

		cached_miners = miners
		cached_resources = {
			["basic-solid"] = true,
			["hard-resource"] = true,
		}
	end
	return enums.get_available_miners()
end

enums.resource_categories = {
	["basic-solid"] = true,
	["hard-resource"] = true,
}

return enums
