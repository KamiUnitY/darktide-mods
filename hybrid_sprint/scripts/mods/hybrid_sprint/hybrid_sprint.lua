-- Hybrid Sprint by KamiUnitY. Ver. 1.2.0

local mod = get_mod("hybrid_sprint")
local modding_tools = get_mod("modding_tools")

---------------
-- CONSTANTS --
---------------

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
    hub_jog        = true,
}

local MOVEMENT_ACTIONS = {
    move_forward  = true,
    move_backward = true,
    move_left     = true,
    move_right    = true,
}

---------------
-- VARIABLES --
---------------

mod.promise_sprint = false

local movement_pressed = {
    move_forward  = false,
    move_backward = false,
    move_left     = false,
    move_right    = false,
}

local is_in_hub = false

mod.character_state = ""

mod.wants_to_stop = false
mod.keep_sprint = false

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
    enable_hold_to_sprint                   = mod:get("enable_hold_to_sprint"),
    enable_keep_sprint_after_weapon_actions = mod:get("enable_keep_sprint_after_weapon_actions"),
    enable_debug_modding_tools              = mod:get("enable_debug_modding_tools"),
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
    -- modding_tools:watch("character_state", mod, "character_state")
    -- modding_tools:watch("wants_to_stop", mod, "wants_to_stop")
    -- modding_tools:watch("keep_sprint", mod, "keep_sprint")
end

---------------------------
-- ON GAME STATE CHANGED --
---------------------------

mod.on_game_state_changed = function(status, state_name)
    -- Update is_in_hub
    is_in_hub = _is_in_hub()

    -- Force hold sprint in vanilla settings
    local input_settings = Managers.save:account_data().input_settings
    input_settings.hold_to_sprint = true
end

-----------------------
-- PROMISE FUNCTIONS --
-----------------------

local function setPromise(from)
    if not mod.promise_sprint and ALLOWED_CHARACTER_STATE[mod.character_state] then
        mod.promise_sprint = true
        if modding_tools then debug:print_mod("setPromiseFrom: " .. from) end
    end
end

local function clearPromise(from)
    if mod.promise_sprint or mod.keep_sprint then
        mod.promise_sprint = false
        mod.keep_sprint = false
        if modding_tools then debug:print_mod("clearPromiseFrom: " .. from) end
    end
end

local function isPromised(promise)
    if promise then
        if modding_tools then debug:print_mod("Attempting to sprint for you !!!") end
    end
    return promise
end

----------------
-- ON TRIGGER --
----------------

-- REMOVE HOLD SPRINT FROM VANILLA SETTINGS --

mod:hook_require("scripts/settings/options/input_settings", function(instance)
    for i, setting in ipairs(instance.settings) do
        if setting.id == "hold_to_sprint" then
            table.remove(instance.settings, i)
            break
        end
    end
end)

-- CLEARING PROMISE ON WEAPON ACTION

mod:hook_safe("PlayerCharacterStateWalking", "on_enter", function(self, unit, dt, t, previous_state, params)
    if mod.settings["enable_keep_sprint_after_weapon_actions"] then
        mod.wants_to_stop = true
    else
        if previous_state == "sprinting" then
            clearPromise("wants_to_stop")
        end
    end
    if modding_tools then debug:print_mod("wants_to_stop") end
end)

-- KEEPING SPRINT AFTER FINISHING WEAPON ACTION

mod:hook_safe("ActionHandler", "_finish_action", function(self, handler_data, reason, data, t, next_action_params)
    if mod.promise_sprint and mod.wants_to_stop and (reason == "new_interrupting_action" or reason == "started_sprint") then
        clearPromise("new_interrupting_action")
        mod.keep_sprint = true
        mod.wants_to_stop = false
    end
    if mod.keep_sprint and (reason == "action_complete" or reason == "hold_input_released") then
        setPromise("action_complete")
        mod.keep_sprint = false
    end
end)

-- UPDATE CHARACTER STATE VARIABLE AND CLEAR PROMISE ON UNALLOWED CHARACTER STATE

local _update_character_state = function (self)
    mod.character_state = self._state_current.name
    if not ALLOWED_CHARACTER_STATE[mod.character_state] then
        clearPromise("Unallowed Character State")
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

local _input_hook = function(func, self, action_name)
    local out = func(self, action_name)
    local pressed = (out == true) or (type(out) == "number" and out > 0)

    -- While on hub
    if is_in_hub and MOVEMENT_ACTIONS[action_name] then
        -- On releasing movement
        if not pressed and movement_pressed[action_name] then
            local any_movement_pressed = false
            for key, value in pairs(movement_pressed) do
                if key ~= action_name and value then
                    any_movement_pressed = true
                    break
                end
            end
            if not any_movement_pressed then
                clearPromise("Released All Movement")
            end
        end
        movement_pressed[action_name] = pressed
        return out
    end

    if action_name == "move_forward" then
        -- On releasing forward
        if not pressed and movement_pressed["move_forward"] then
            clearPromise("Realeased Forward")
        end
        movement_pressed["move_forward"] = pressed
        return out
    end

    if action_name == "move_backward" and pressed then
        -- On pressing backward
        if pressed and not movement_pressed["move_backward"] then
            clearPromise("Pressed Backward")
        end
        return out
    end

    if action_name == "sprinting" then
        if pressed and not mod.settings["enable_hold_to_sprint"] then
            setPromise("Pressed Sprint")
        end
        local promise = mod.promise_sprint
        return out or (promise and isPromised(promise))
    end

    return out
end

mod:hook("InputService", "_get", _input_hook)
mod:hook("InputService", "_get_simulate", _input_hook)
