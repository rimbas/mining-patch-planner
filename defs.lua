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

---@class EventDataGuiSelectionStateChanged : EventData
---@field player_index uint
---@field element LuaGuiElement

---@class PoleCharacteristics
---@field width number The entity width
---@field reach number Wire connection reach
---@field area number Supply area width

---@class Layout
---@field name string
---@field starting_state string Initial state
---@field defaults LayoutDefaults
---@field restrictions Restrictions
---@field validate function(state: State)
---@field initialize function(state: State)
---@field tick function(state: State)

---@class LayoutDefaults
---@field miner string
---@field belt string
---@field pole string
---@field logistics string

---@class Restrictions
---@field miner_available boolean
---@field miner_near_radius number[] Supported near radius of a miner
---@field miner_far_radius number[] Supported far radius of a miner
---@field belt_available boolean
---@field uses_underground_belts boolean
---@field pole_available boolean
---@field pole_omittable boolean Allow a no electric pole option
---@field pole_width number[]
---@field pole_length number[]
---@field pole_supply_area number[]
---@field logistics_available boolean
---@field lamp_available boolean Enable lamp placement option
---@field coverage_tuning boolean
---@field landfill_omit_available boolean

table.deepcopy = function(t) end
