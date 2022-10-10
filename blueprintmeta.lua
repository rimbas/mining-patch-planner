local mpp_util = require("mpp_util")

---@class EvaluatedBlueprint
---@field w number
---@field h number
---@field tw number Runtime transposed width
---@field th number Runtime transposed height
---@field ox number Start offset x
---@field oy number Start offset y
---@field entities BlueprintEntityEx All entities in the blueprint
---@field miners table<string, MinerStruct> List of used miner types
local bp_meta = {}
bp_meta.__index = bp_meta

---@class BlueprintEntityEx : BlueprintEntity
---@field capstone_x number
---@field capstone_y number

---Blueprint analysis data
---@param bp LuaItemStack
---@return EvaluatedBlueprint
function bp_meta:new(bp)
	---@type EvaluatedBlueprint
	local new = setmetatable({}, self)

	new.w, new.h = bp.blueprint_snap_to_grid.x, bp.blueprint_snap_to_grid.y
	if bp.blueprint_position_relative_to_grid then
		new.ox, new.oy = bp.blueprint_position_relative_to_grid.x, bp.blueprint_position_relative_to_grid.y
	else
		new.ox, new.oy = 0, 0
	end
	new.entities = bp.get_blueprint_entities()

	new:evaluate_tiling()
	new:evaluate_miners()

	return new
end

---Marks capstone BlueprintEntities
function bp_meta:evaluate_tiling()
	local sw, sh = self.w, self.h
	local buckets_x, buckets_y = {}, {}

	for i, ent in pairs(self.entities) do
		local x, y = ent.position.x, ent.position.y
		if not buckets_x[x] then buckets_x[x] = {} end
		table.insert(buckets_x[x], ent)
		if not buckets_y[y] then buckets_y[y] = {} end
		table.insert(buckets_y[y], ent)
	end

	for _, bucket in pairs(buckets_x) do
		for i = 1, #bucket-1 do
			local e1 = bucket[i] ---@type BlueprintEntity
			local e1x = e1.position.x
			for j = 2, #bucket do
				local e2 = bucket[j] ---@type BlueprintEntity
				if e1x + sh == e2.position.x or e1x - sh == e2.position.x then
					e2.capstone_x = true
				end
			end
		end
	end

	for _, bucket in pairs(buckets_y) do
		for i = 1, #bucket-1 do
			local e1 = bucket[i] ---@type BlueprintEntity
			local e1y = e1.position.y
			for j = 2, #bucket do
				local e2 = bucket[j] ---@type BlueprintEntity
				if e1y + sh == e2.position.y or e1y - sh == e2.position.y then
					e2.capstone_y = true
				end
			end
		end
	end
end

function bp_meta:evaluate_miners()
	local miners = {}
	self.miners = miners
	for _, ent in pairs(self.entities) do
		local name = ent.name
		if game.entity_prototypes[name].type == "mining-drill" then
			local proto = game.entity_prototypes[name]
			miners[name] = mpp_util.miner_struct(proto)
		end
	end
end

return bp_meta
