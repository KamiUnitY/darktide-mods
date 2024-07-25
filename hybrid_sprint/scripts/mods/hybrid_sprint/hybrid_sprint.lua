-- Guarantee Better Sprint mod by KamiUnitY. Ver. 1.1.0

local mod = get_mod("hybrid_sprint")
local modding_tools = get_mod("modding_tools")

mod.settings = {
    enable_hold_to_sprint                   = mod:get("enable_hold_to_sprint"),
    enable_keep_sprint_after_weapon_actions = mod:get("enable_keep_sprint_after_weapon_actions"),
    enable_debug_modding_tools              = mod:get("enable_debug_modding_tools"),
}

mod.on_setting_changed = function(setting_id)
    mod.settings[setting_id] = mod:get(setting_id)
end

mod.on_all_mods_loaded = function()
    -- modding_tools:watch("pressed_forward", mod, "pressed_forward")
    -- modding_tools:watch("interrupt_sprint", mod, "interrupt_sprint")
    -- modding_tools:watch("character_state", mod, "character_state")
end

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

mod.promise_sprint = false
mod.promise_dodge = false

local action_pressed = {
    move_forward = false,
    move_backward = false,
    move_left = false,
    move_right = false
}

-- mod.interrupt_sprint = false

mod.character_state = nil

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

local INTERRUPTED_INPUT = {
    action_one_pressed   = true,
    action_one_hold      = true,
    action_one_release   = true,
    action_two_pressed   = true,
    action_two_hold      = true,
    action_two_release   = true,
    weapon_extra_pressed = true,
    weapon_extra_hold    = true,
    weapon_extra_release = true,
    weapon_reload        = true,
}

mod.on_game_state_changed = function(status, state_name)
    local input_settings = Managers.save:account_data().input_settings
    input_settings.hold_to_sprint = true
end

mod:hook_require("scripts/settings/options/input_settings", function(instance)
    for i, setting in ipairs(instance.settings) do
        if setting.id == "hold_to_sprint" then
            table.remove(instance.settings, i)
            break
        end
    end
end)

local function setPromise(from)
    if not mod.promise_sprint and ALLOWED_CHARACTER_STATE[mod.character_state] then
        mod.promise_sprint = true
        if modding_tools then debug:print_mod("setPromiseFrom: " .. from) end
    end
end

local function clearPromise(from)
    if mod.promise_sprint then
        mod.promise_sprint = false
        if modding_tools then debug:print_mod("clearPromiseFrom: " .. from) end
    end
end

local function isPromised()
    local result = mod.promise_sprint and action_pressed["move_forward"]
    if result then
        if modding_tools then debug:print_mod("Attempting to sprint for you !!!") end
    end
    return result
end

local _input_hook = function(func, self, action_name)
    local out = func(self, action_name)
    local type_str = type(out)
    local pressed = (type_str == "boolean" and out == true) or (type_str == "number" and out > 0)

    if action_pressed[action_name] ~= nil then
        action_pressed[action_name] = pressed
    end

    if action_name == "move_left" then
        if pressed then
            -- debug:print(out)
        end
    end

    if action_name == "move_forward" then
        action_pressed["move_forward"] = pressed
        local released_forward = action_pressed["move_forward"] and not pressed
        if released_forward then
            clearPromise("Realeased Forward")
        end
        return out
    end

    if action_name == "sprinting" then
        if pressed and not mod.settings["enable_hold_to_sprint"] then
            setPromise("Pressed Sprint")
        end
        return (out or isPromised()) and not mod.promise_dodge
    end

    if action_name == "jump" then
        return out and not (mod.character_state == "sprinting" and (action_pressed["move_left"] or action_pressed["move_right"]))
    end
    if action_name == "dodge" then
        if pressed and (action_pressed["move_left"] or action_pressed["move_right"]) and mod.character_state == "sprinting" then
            mod.promise_dodge = true
            clearPromise("Pressed Dodge")
        end
        return out or mod.promise_dodge
    end

    return out
end

mod:hook_require("scripts/extension_systems/character_state_machine/character_states/utilities/dodge", function(instance)
    debug:print(instance)
    --hook not working
    mod:hook_safe(instance, "check", function(t, unit_data_extension, base_dodge_template, input_source)
        debug.print(t)
    end)
end)

mod:hook_safe("PlayerCharacterStateDodging", "on_enter", function(self, unit, dt, t, previous_state, params)
    mod.promise_dodge = false
end)

mod:hook_safe("PlayerCharacterStateJumping", "on_enter", function(self, unit, dt, t, previous_state, params)
    mod.promise_dodge = false
end)

mod:hook("InputService", "_get", _input_hook)
mod:hook("InputService", "_get_simulate", _input_hook)

mod:hook_safe("CharacterStateMachine", "fixed_update", function(self, unit, dt, t, frame, ...)
    if self._unit_data_extension._player.viewport_name == 'player1' then
        mod.character_state = self._state_current.name
        if not ALLOWED_CHARACTER_STATE[mod.character_state] then
            clearPromise("Unallowed Character State")
        end
    end
end)

local function check_weapon_want_to_stop(keywords)
    local has = {}
    for _, keyword in ipairs(keywords) do
        has[keyword] = true
    end
    local melee = has["melee"]
    local ranged = has["ranged"]
    local want_to_stop = (melee and not has["combat_knife"]) or (ranged and has["heavystubber"])
    return want_to_stop
end

local PlayerUnitVisualLoadout = require("scripts/extension_systems/visual_loadout/utilities/player_unit_visual_loadout")
mod:hook("PlayerCharacterStateSprinting", "_check_transition", function(func, self, ...)
    local out = func(self, ...)
    if out == "walking" then
        if mod.settings["enable_keep_sprint_after_weapon_actions"] then
            local weapon_template = PlayerUnitVisualLoadout.wielded_weapon_template(self._visual_loadout_extension, self._inventory_component)
            if check_weapon_want_to_stop(weapon_template.keywords) then
                clearPromise("wants_to_stop")
            end
        else
            clearPromise("wants_to_stop")
        end
    end
    return out
end)

-- mod:hook_require("scripts/extension_systems/character_state_machine/character_states/utilities/sprint", function(instance)
--     mod:hook_safe(instance, "sprint_input", function(input_source, is_sprinting, sprint_requires_press_to_interrupt)
--         mod.interrupt_sprint = sprint_requires_press_to_interrupt
--     end)
-- end)

-- mod:hook_require("scripts/utilities/attack/interrupt", function(instance)
--     mod:hook_safe(instance, "action", function(t, unit, reason, reason_data_or_nil, ignore_immunity)
--         debug:print("Interrupt reason: " .. reason)
--     end)
-- end)