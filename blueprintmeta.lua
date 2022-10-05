local mpp_util = require("mpp_util")

---@class EvaluatedBlueprint
---@field w number
---@field h number
---@field bp_grid BlueprintGrid
---@field entities table<number, BlueprintEntity>
local bp_meta = {}
bp_meta.__index = bp_meta

---@class BlueprintGrid
---@ 

---Blueprint analysis data
---@param bp LuaItemStack
---@return EvaluatedBlueprint
function bp_meta:new(bp)
	---@type EvaluatedBlueprint
	local new = setmetatable({}, self)

	new.w, new.h = bp.blueprint_snap_to_grid.x, bp.blueprint_snap_to_grid.y
	new.entities = bp.get_blueprint_entities()

	new:evaluate_tiling()
	new:evaluate_miners()

	return new
end

---Marks capstone BlueprintEntities
function bp_meta:evaluate_tiling()
	local sw, sh = self.w, self.h
	local buckets = {}

	for i, ent in pairs(self.entities) do
		local x, y = ent.position.x, ent.position.y
		if not buckets[x] then buckets[x] = {} end
		table.insert(buckets[x], ent)
	end

	for _, bucket in pairs(buckets) do
		for i = 1, #bucket-1 do
			local e1 = bucket[i] ---@type BlueprintEntity
			local e1y = e1.position.y
			for j = 2, #bucket do
				local e2 = bucket[j] ---@type BlueprintEntity
				if e1y + sh == e2.position.y or e1y - sh == e2.position.y then
					e2.capstone = true
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
