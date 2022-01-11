---@meta
---@diagnostic disable

---@class EventDataPlayerSelectedArea : EventData
---@field item string
---@field player_index uint
---@field entities LuaEntity[]
---@field tiles LuaTile[]
---@field surface LuaSurface

---@class EventDataPlayerCreated : EventData
---@field player_index uint

---@class EventDataGuiCheckedStateChanged : EventData
---@field player_index uint
---@field element LuaGuiElement

---@class EventDataGuiClick : EventData
---@field player_index uint
---@field element LuaGuiElement
---@field button defines.mouse_button_type
---@field alt boolean
---@field control boolean
---@field shift boolean

---@class MinerCharacteristics
---@field w integer Tile width
---@field h integer Tile height
---@field near integer Bounds radius of the miner
---@field far integer Reach radius of the miner
---@field cbox BoundingBox Miner bounding box
---@field miner_name string Miner name
---@field resource_categories table<string, boolean> Resource categories miner can mine

---@class PoleCharacteristics
---@field width number The entity width
---@field reach number Wire connection reach
---@field area number Supply area width

---@class Layout
---@field name string
---@field starting_state string Initial 
---@field restrictions Restrictions

---@class Restrictions
---@field miner_near_radius number[] #Supported near radius of a miner
---@field miner_far_radius number[] #Supported far radius of a miner
---@field pole_width number[] 
---@field pole_length number[]
---@field pole_supply_area number[]
---@field lamp boolean #Enable lamp placement option

table.deepcopy = function(t) end
