-- Guarantee Weapon Swap mod by KamiUnitY. Ver. 1.2.0

local mod = get_mod("guarantee_weapon_swap")
local modding_tools = get_mod("modding_tools")

mod.settings = {
    enable_zealot_throwing_knives = mod:get("enable_zealot_throwing_knives"),
    enable_debug_modding_tools    = mod:get("enable_debug_modding_tools"),
}

mod.on_setting_changed = function(setting_id)
    mod.settings[setting_id] = mod:get(setting_id)
end

mod.on_all_mods_loaded = function()
    -- modding_tools:watch("character_state",mod,"character_state")
end

local debug = {
    is_enabled = function(self)
        return mod.settings["enable_debug_modding_tools"] and modding_tools and modding_tools:is_enabled()
    end,
    print = function(self, text)
        pcall(function() modding_tools:console_print(text) end)
    end,
    print_if_enabled = function(self, text)
        if self:is_enabled() then
            self:print(text)
        end
    end,
}

local grenade_ability = nil

local current_slot = ""
local previous_slot = ""

mod.character_state = nil

mod.promises = {
    quick            = false,
    primary          = false,
    secondary        = false,
    grenade          = false,
    pocketable       = false,
    pocketable_small = false,
    device           = false,
}

local PROMISE_SLOT_MAP = {
    slot_primary          = "primary",
    slot_secondary        = "secondary",
    slot_grenade_ability  = "grenade",
    slot_pocketable       = "pocketable",
    slot_pocketable_small = "pocketable_small",
    slot_device           = "device",
}

local PROMISE_ACTION_MAP = {
    quick_wield             = "quick",
    wield_1                 = "primary",
    wield_2                 = "secondary",
    grenade_ability_pressed = "grenade",
    wield_3                 = "pocketable",
    wield_4                 = "pocketable_small",
    wield_5                 = "device"
}

local ACTION_SLOT_MAP = {
    wield_1                 = "slot_primary",
    wield_2                 = "slot_secondary",
    grenade_ability_pressed = "slot_grenade_ability",
    wield_3                 = "slot_pocketable",
    wield_4                 = "slot_pocketable_small",
    wield_5                 = "slot_device"
}

local ALLOWED_CHARACTER_STATE = {
    dodging        = true,
    ledge_vaulting = true,
    lunging        = true,
    sliding        = true,
    sprinting      = true,
    stunned        = true,
    walking        = true,
    jumping        = true,
    falling        = true,
}

local function isPromised(action)
    if mod.promises[action] and current_slot ~= "" then
        if modding_tools then debug:print_if_enabled("Guarantee Weapon Swap: Attempting to switch weapon: " .. current_slot .. " -> " .. action) end
    end
    return mod.promises[action]
end

local function setPromise(action_name)
    mod.promises[PROMISE_ACTION_MAP[action_name]] = true
end

local function clearAllPromises()
    for key in pairs(mod.promises) do
        mod.promises[key] = false
    end
end

mod:hook_safe("PlayerUnitDataExtension", "fixed_update", function (self, unit, dt, t, fixed_frame)
    grenade_ability = self._components.equipped_abilities[1].grenade_ability
end)

mod:hook_safe("PlayerUnitWeaponExtension", "on_slot_wielded", function(self, slot_name, t, skip_wield_action)
    mod.promises.quick = false
    mod.promises[PROMISE_SLOT_MAP[slot_name] or ""] = false
end)

mod:hook_safe("PlayerUnitWeaponExtension", "_wielded_weapon", function(self, inventory_component, weapons)
    local wielded_slot = inventory_component.wielded_slot
    if wielded_slot ~= nil and wielded_slot ~= current_slot then
        previous_slot = current_slot
        current_slot = wielded_slot
        if current_slot ~= "" and previous_slot ~= "" then
            if modding_tools then debug:print_if_enabled("Guarantee Weapon Swap: " .. previous_slot .. " -> " .. current_slot) end
        end
    end
end)

local _input_hook = function(func, self, action_name)
    local out = func(self, action_name)
    local type_str = type(out)
    local pressed = (type_str == "boolean" and out == true) or (type_str == "number" and out == 1)

    if PROMISE_ACTION_MAP[action_name] then
        if pressed then
            clearAllPromises()
            if current_slot ~= ACTION_SLOT_MAP[action_name] and ALLOWED_CHARACTER_STATE[mod.character_state] and current_slot ~= "slot_unarmed" then
                if action_name ~= "grenade_ability_pressed" or grenade_ability ~= "zealot_throwing_knives" or (mod.settings["enable_zealot_throwing_knives"] and current_slot ~= "slot_luggable") then
                    setPromise(action_name)
                end
            end
        end
        return out or isPromised(PROMISE_ACTION_MAP[action_name])
    end

    return out
end

mod:hook("InputService", "_get", _input_hook)
mod:hook("InputService", "_get_simulate", _input_hook)

mod:hook_safe("HudElementPlayerWeaponHandler", "_weapon_scan", function (self, extensions, ui_renderer)
    if (self._player_weapons.slot_pocketable_small == nil) then
        mod.promises.pocketable_small = false
    end
    if (self._player_weapons.slot_pocketable == nil) then
        mod.promises.pocketable = false
    end
    if (self._player_weapons.slot_device == nil) then
        mod.promises.device = false
    end
end)

mod:hook("PlayerUnitAbilityExtension", "can_wield", function (func, self, slot_name, previous_check)
    local out = func(self, slot_name, previous_check)
    if slot_name == "slot_grenade_ability" then
        if out ~= true then
           mod.promises.grenade = false
           return out
        end
        if self._equipped_abilities.grenade_ability.name == "zealot_throwing_knives" then
            mod.promises.grenade = false
            return out
        end
    end
    return out
end)

mod:hook_safe("CharacterStateMachine", "fixed_update", function (self, unit, dt, t, frame, ...)
    if self._unit_data_extension._player.viewport_name == 'player1' then
        mod.character_state = self._state_current.name
    end
end)