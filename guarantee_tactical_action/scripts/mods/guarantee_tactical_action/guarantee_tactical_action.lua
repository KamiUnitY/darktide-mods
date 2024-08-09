-- Guarantee Tactical Action by KamiUnitY. Ver. 0.0.1

local mod = get_mod("guarantee_tactical_action")
local modding_tools = get_mod("modding_tools")

---------------
-- CONSTANTS --
---------------

local PROMISE_ACTION_MAP = {
    weapon_extra_pressed = "special",
    weapon_reload        = "reload",
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

---------------
-- VARIABLES --
---------------

mod.character_state = ""

mod.promise_exist = false

mod.promises = {
    special = false,
    reload  = false,
}

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

--------------------------
-- MOD SETTINGS CACHING --
--------------------------

mod.settings = {
    enable_debug_modding_tools    = mod:get("enable_debug_modding_tools"),
}

mod.on_setting_changed = function(setting_id)
    mod.settings[setting_id] = mod:get(setting_id)
end

------------------------
-- ON ALL MODS LOADED --
------------------------

mod.on_all_mods_loaded = function()
    -- WATCHER
    -- modding_tools:watch("promise_exist",mod,"promise_exist")
    -- modding_tools:watch("character_state",mod,"character_state")
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
        if modding_tools then debug:print_mod("Attempting to do tactical action !!!") end
    end
    return promise
end

----------------
-- ON TRIGGER --
----------------

-- CLEAR PROMISE ON CHANGE WEAPON

mod:hook_safe("PlayerUnitWeaponExtension", "on_slot_wielded", function(self, slot_name, t, skip_wield_action)
    if self._player.viewport_name == "player1" then
        clearAllPromises()
    end
end)

-- CLEAR PROMISE ON START ACTION

mod:hook_safe("ActionHandler", "start_action", function(self, id, action_objects, action_name, action_params, action_settings, used_input, t, transition_type, condition_func_params, automatic_input, reset_combo_override)
    if self._unit_data_extension._player.viewport_name == 'player1' then
        if PROMISE_ACTION_MAP[used_input] then
            clearPromise(PROMISE_ACTION_MAP[used_input])
        end
    end
end)

-- UPDATE CHARACTER STATE VARIABLE AND CLEAR PROMISE ON UNALLOWED CHARACTER STATE

local _update_character_state = function (self)
    mod.character_state = self._state_current.name
    if not ALLOWED_CHARACTER_STATE[mod.character_state] then
        clearAllPromises()
    end
end

mod:hook_safe("CharacterStateMachine", "fixed_update", function(self, unit, dt, t, frame, ...)
    if mod.character_state ~= "" then
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

--------------------
-- ON EVERY FRAME --
--------------------

----------------
-- INPUT HOOK --
----------------

local input_tick = 0

local _input_hook = function(func, self, action_name)
    local out = func(self, action_name)
    local pressed = (out == true) or (type(out) == "number" and out > 0)

    input_tick = input_tick + 1

    local promise_action = PROMISE_ACTION_MAP[action_name]
    if promise_action then
        if pressed then
            clearAllPromises()
            if ALLOWED_CHARACTER_STATE[mod.character_state] then
                setPromise(promise_action)
            end
        end
        if input_tick % 10 == 0 then
            local promise = mod.promises[promise_action]
            return out or (promise and isPromised(promise))
        end
    end

    return out
end

mod:hook("InputService", "_get", _input_hook)
mod:hook("InputService", "_get_simulate", _input_hook)
