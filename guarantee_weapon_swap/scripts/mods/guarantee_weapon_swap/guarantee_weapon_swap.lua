-- Guarantee Weapon Swap by KamiUnitY. Ver. 1.3.1

local mod = get_mod("guarantee_weapon_swap")
local modding_tools = get_mod("modding_tools")

---------------
-- CONSTANTS --
---------------

local PROMISE_SLOT_MAP = {
    slot_primary          = "primary",
    slot_secondary        = "secondary",
    slot_pocketable       = "pocketable",
    slot_pocketable_small = "pocketable_small",
    slot_device           = "device",
    slot_grenade_ability  = "grenade",
}

local PROMISE_ACTION_MAP = {
    quick_wield             = "quick",
    wield_1                 = "primary",
    wield_2                 = "secondary",
    wield_3                 = "pocketable",
    wield_4                 = "pocketable_small",
    wield_5                 = "device",
    grenade_ability_pressed = "grenade",
}

local ACTION_SLOT_MAP = {
    wield_1                 = "slot_primary",
    wield_2                 = "slot_secondary",
    wield_3                 = "slot_pocketable",
    wield_4                 = "slot_pocketable_small",
    wield_5                 = "slot_device",
    grenade_ability_pressed = "slot_grenade_ability",
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

local EXCEPTION_ATTACK_PREVENT_ACTION = {
    action_shoot_hip_start    = true,
    action_shoot_zoomed_start = true,
}

---------------
-- VARIABLES --
---------------

mod.promise_exist = false

mod.promises = {
    quick            = false,
    primary          = false,
    secondary        = false,
    pocketable       = false,
    pocketable_small = false,
    device           = false,
    grenade          = false,
}

local is_in_hub = false

local grenade_ability = ""

local current_slot = ""
local previous_slot = ""

local current_action = ""
local previous_action = ""

local character_state = ""

---------------
-- UTILITIES --
---------------

local debug = {
    is_enabled = function(self)
        return mod.settings["enable_debug_modding_tools"] and modding_tools and modding_tools:is_enabled()
    end,
    print = function(self, text)
        pcall(function() modding_tools:console_print(text) end)
    end,
    print_mod = function(self, text)
        if self:is_enabled() then
            self:print(mod:localize("mod_name") .. ": " .. text)
        end
    end,
}

local _is_in_hub = function()
    local game_mode_manager = Managers.state.game_mode
    local game_mode_name = game_mode_manager and game_mode_manager:game_mode_name()
    return game_mode_name == "hub"
end

--------------------------
-- MOD SETTINGS CACHING --
--------------------------

mod.settings = {
    enable_zealot_throwing_knives = mod:get("enable_zealot_throwing_knives"),
    enable_debug_modding_tools    = mod:get("enable_debug_modding_tools"),
}

mod.on_setting_changed = function(setting_id)
    mod.settings[setting_id] = mod:get(setting_id)
end

------------------------
-- ON ALL MODS LOADED --
------------------------

mod.on_all_mods_loaded = function()
    -- Update is_in_hub
    is_in_hub = _is_in_hub()

    -- WATCHER
    -- modding_tools:watch("promise_exist",mod,"promise_exist")
    -- modding_tools:watch("character_state",mod,"character_state")
end

---------------------------
-- ON GAME STATE CHANGED --
---------------------------

mod.on_game_state_changed = function(status, state_name)
    -- Update is_in_hub
    is_in_hub = _is_in_hub()
end

-----------------------
-- PROMISE FUNCTIONS --
-----------------------

local function setPromise(action)
    if not mod.promises[action] then
        mod.promises[action] = true
        mod.promise_exist = true
    end
end

local function clearPromise(action)
    if mod.promises[action] then
        mod.promises[action] = false
        mod.promise_exist = false -- Every setPromise() got clearAllPromises() first, So this is fine
    end
end

local function clearAllPromises()
    if mod.promise_exist then
        for key in pairs(mod.promises) do
            mod.promises[key] = false
        end
        mod.promise_exist = false
    end
end

local function isPromised(promise)
    if promise then
        if modding_tools then debug:print_mod("Attempting to switch weapon !!!") end
    end
    return promise
end

----------------
-- ON TRIGGER --
----------------

-- CLEAR PROMISE ON ENTER OR EXIT GAMEPLAY

mod:hook_safe("GameplayStateRun", "on_enter", function(...)
    clearAllPromises()
end)

mod:hook_safe("GameplayStateRun", "on_exit", function(...)
    clearAllPromises()
end)

-- CLEAR PROMISE ON SUCCESSFULLY CHANGE WEAPON

mod:hook_safe("PlayerUnitWeaponExtension", "on_slot_wielded", function(self, slot_name, t, skip_wield_action)
    if self._player.viewport_name == "player1" then
        clearPromise("quick")
        clearPromise(PROMISE_SLOT_MAP[slot_name])
        previous_slot = current_slot
        current_slot = slot_name
        if current_slot ~= "" and previous_slot ~= "" then
            if modding_tools then debug:print_mod(previous_slot .. " -> " .. current_slot) end
        end
    end
end)

-- CLEAR PROMISE ON FAILING TO WIELD GRENADE

mod:hook("PlayerUnitAbilityExtension", "can_wield", function(func, self, slot_name, previous_check)
    local can_wield = func(self, slot_name, previous_check)
    if self._player.viewport_name == "player1" then
        if slot_name == "slot_grenade_ability" then
            if not can_wield then
                clearPromise("grenade")
            elseif self._equipped_abilities.grenade_ability.name == "zealot_throwing_knives" then
                clearPromise("grenade")
            end
        end
    end
    return can_wield
end)

-- CLEAR PROMISE FOR NOT AVAILABLE ITEMS

mod:hook("PlayerUnitWeaponExtension", "can_wield", function(func, self, slot_name)
    local can_wield = func(self, slot_name)
    if self._player.viewport_name == "player1" then
        if not can_wield then
            clearPromise(PROMISE_SLOT_MAP[slot_name])
        end
    end
    return can_wield
end)

-- UPDATE CHARACTER STATE VARIABLE AND CLEAR PROMISE ON UNALLOWED CHARACTER STATE

local _update_character_state = function (self)
    character_state = self._state_current.name
    if not ALLOWED_CHARACTER_STATE[character_state] then
        clearAllPromises()
    end
end

mod:hook_safe("CharacterStateMachine", "fixed_update", function(self, unit, dt, t, frame, ...)
    if character_state ~= "" then
        mod:hook_disable("CharacterStateMachine", "fixed_update")
    end
    if self._unit_data_extension._player.viewport_name == 'player1' then
        _update_character_state(self)
    end
end)

mod:hook_safe("CharacterStateMachine", "_change_state", function(self, unit, dt, t, next_state, ...)
    if self._unit_data_extension._player.viewport_name == 'player1' then
        _update_character_state(self)
    end
end)

-- UPDATE GRENADE ABILITY VARIABLE

mod:hook_safe("PlayerUnitAbilityExtension", "update", function(self, unit, dt, t, fixed_frame)
    if grenade_ability ~= "" then
        mod:hook_disable("PlayerUnitAbilityExtension", "update")
    end
    if self._player.viewport_name == "player1" then
        local _grenade_ability = self._equipped_abilities.grenade_ability
        if _grenade_ability ~= nil then
            grenade_ability = _grenade_ability.name
        end
    end
end)

mod:hook_safe("PlayerUnitAbilityExtension", "equip_ability", function(self, ability_type, ability, fixed_t)
    if self._player.viewport_name == "player1" then
        if ability_type == "grenade_ability" then
            grenade_ability = ability.name
        end
    end
end)

-- UPDATE ACTION VARIABLE

mod:hook_safe("ActionHandler", "start_action", function(self, id, action_objects, action_name, action_params, action_settings, used_input, t, transition_type, condition_func_params, automatic_input, reset_combo_override)
    if self._unit_data_extension._player.viewport_name == 'player1' then
        current_action = action_name
    end
end)

mod:hook_safe("ActionHandler", "_finish_action", function(self, handler_data, reason, data, t, next_action_params)
    if self._unit_data_extension._player.viewport_name == 'player1' then
        previous_action = current_action
        current_action = "none"
    end
end)

--------------------
-- ON EVERY FRAME --
--------------------

----------------
-- INPUT HOOK --
----------------

local _input_hook = function(func, self, action_name)
    local out = func(self, action_name)
    local pressed = (out == true) or (type(out) == "number" and out > 0)

    if is_in_hub then
        return out
    end

    local promise_action = PROMISE_ACTION_MAP[action_name]
    if promise_action then
        if pressed then
            clearAllPromises()
            if current_slot ~= ACTION_SLOT_MAP[action_name] and ALLOWED_CHARACTER_STATE[character_state] then
                if action_name ~= "grenade_ability_pressed"
                    or (
                        (grenade_ability ~= "zealot_throwing_knives" or mod.settings["enable_zealot_throwing_knives"])
                        and current_slot ~= "slot_luggable"
                    )
                then
                    setPromise(promise_action)
                end
            end
        end
        local promise = mod.promises[promise_action]
        return out or (promise and isPromised(promise))
    end

    if mod.promise_exist and not EXCEPTION_ATTACK_PREVENT_ACTION[current_action] then
        if action_name == "action_one_pressed" or action_name == "action_one_hold" then
            return false
        end

        if action_name == "action_two_pressed" or action_name == "action_two_hold" then
            return false
        end
    end

    return out
end

mod:hook("InputService", "_get", _input_hook)
mod:hook("InputService", "_get_simulate", _input_hook)
