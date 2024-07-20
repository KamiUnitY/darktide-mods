-- Guarantee Better Sprint mod by KamiUnitY. Ver. 1.0.0

local mod = get_mod("guarantee_better_sprint")
local modding_tools = get_mod("modding_tools")

mod.promise_sprint = false
mod.pressed_forward = false

local debug = {
    is_enabled = function(self)
        return modding_tools and modding_tools:is_enabled() and mod:get("enable_debug_modding_tools")
    end,
    print = function(self, text)
        pcall(function() modding_tools:console_print(text) end)
    end
}

mod.on_all_mods_loaded = function()
    -- modding_tools:watch("pressed_forward", mod, "pressed_forward")
end

mod.on_game_state_changed = function(status, state_name)
    local input_settings = Managers.save:account_data().input_settings
    input_settings.hold_to_sprint = true
end

mod:hook_require("scripts/settings/options/input_settings", function(instance)
    -- Filter out the hold_to_sprint setting from the settings array
    local filtered_settings = {}
    for i, setting in ipairs(instance.settings) do
        if setting.id ~= "hold_to_sprint" then
            table.insert(filtered_settings, setting)
        end
    end
    -- Update the settings array with the filtered settings
    instance.settings = filtered_settings
end)

local ALLOWED_CHARACTER_STATE = {
    dodging = true,
    ledge_vaulting = true,
    lunging = true,
    sliding = true,
    sprinting = true,
    stunned = true,
    walking = true,
    jumping = true,
    falling = true,
}

local INTERRUPTED_INPUT = {
    action_one_pressed = true,
    action_one_hold = true,
    action_one_release = true,
    action_two_pressed = true,
    action_two_hold = true,
    action_two_release = true,
    weapon_extra_pressed = true,
    weapon_extra_hold = true,
    weapon_extra_release = true,
    weapon_reload = true,
}

local function setPromise(from)
    if not mod.promise_sprint and ALLOWED_CHARACTER_STATE[mod.character_state] then
        if debug:is_enabled() then
            debug:print("Guarantee Better Sprint: setPromiseFrom: " .. from)
        end
        mod.promise_sprint = true
    end
end

local function clearPromise(from)
    if mod.promise_sprint then
        if debug:is_enabled() then
            debug:print("Guarantee Better Sprint: clearPromiseFrom: " .. from)
        end
        mod.promise_sprint = false
    end
end

local function isPromised()
    local result = mod.promise_sprint and mod.pressed_forward
    if result then
        if debug:is_enabled() then
            debug:print("Guarantee Better Sprint: Attempting to sprint for you !!!")
        end
    end
    return result
end

local _input_hook = function(func, self, action_name)
    local out = func(self, action_name)
    local type_str = type(out)
    local pressed = (type_str == "boolean" and out == true) or (type_str == "number" and out == 1)

    if action_name == "move_forward" then
        local released_forward = mod.pressed_forward and not pressed
        if released_forward then
            clearPromise("Realeased Forward")
        end
        mod.pressed_forward = pressed
    end

    if action_name == "sprint" and pressed and not mod:get("enable_hold_to_sprint") then
        setPromise("Pressed Sprint");
    end

    if INTERRUPTED_INPUT[action_name] and pressed then
        clearPromise("Pressed INTERRUPTED_INPUT: " .. action_name)
    end

    if action_name == "sprinting" then
        return out or isPromised()
    end

    return out
end

mod:hook("InputService", "_get", _input_hook)
mod:hook("InputService", "_get_simulate", _input_hook)

mod:hook_safe("CharacterStateMachine", "fixed_update", function(self, unit, dt, t, frame, ...)
    if self._unit_data_extension._player.viewport_name == 'player1' then
        mod.character_state = self._state_current.name
        if not ALLOWED_CHARACTER_STATE[mod.character_state] then
            mod.promise_sprint = false
        end
    end
end)