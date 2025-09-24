-- Hybrid Sprint by KamiUnitY. Ver. 1.3.4

local mod = get_mod("hybrid_sprint")
local modding_tools = get_mod("modding_tools")
local guarantee_special_action = get_mod("guarantee_special_action")
local toggle_alt_fire = get_mod("ToggleAltFire")

local InputDevice = require("scripts/managers/input/input_device")

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
}

local TRAVELING_CHARACTER_STATE = {
    sprinting = true,
    walking   = true,
}

local MOVEMENT_ACTIONS = {
    move_forward  = true,
    move_backward = true,
    move_left     = true,
    move_right    = true,
}

local IS_AGILE_WEAPON = {
    combatknife_p1_m1 = true,
    combatknife_p1_m2 = true,
}

local DEVICE_TYPE_MAP_ALIASES = {
    mouse           = 1,
    keyboard        = 1,
    ps4_controller  = 2,
    xbox_controller = 3,
}

local DODGE_PRESS_BUFFER = 0.05

---------------
-- VARIABLES --
---------------

mod.promise_sprint = false
mod.promise_dodge = false

mod.keep_sprint = false
mod.keep_sprint_press = false
mod.keep_sprint_empty_action = false

local action_pressed = {}

local movement_pressed = {
    move_forward  = false,
    move_backward = false,
    move_left     = false,
    move_right    = false,
}

local last_press_sprinting = 0
local last_press_dodge = 0

local is_in_hub = false

local character_state = ""

local current_action = ""
local previous_action = ""

local is_action_allowed_during_sprint = true

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

local check_is_in_hub = function()
    local game_mode_manager = Managers.state.game_mode
    local game_mode_name = game_mode_manager and game_mode_manager:game_mode_name()
    return game_mode_name == "hub"
end

local time_now = function()
    return Managers.time and Managers.time:time("main")
end

local elapsed = function(time)
    return time_now() - time
end

-- Function provided by the author of the no_dodge_jump mod, Jaemn
local player_movement_valid_for_dodge = function()
    local player = Managers.player:local_player(1)
    if player == nil then return false end

    local player_unit = player.player_unit
    local archetype = player:profile().archetype
    local dodge_template = archetype.dodge

    local input_extension = ScriptUnit.extension(player_unit, "input_system")
    if input_extension == nil then return false end

    local move = input_extension:get("move")
    local allow_diagonal_forward_dodge = input_extension:get("diagonal_forward_dodge")
    local allow_stationary_dodge = input_extension:get("stationary_dodge")
    local move_length = Vector3.length(move)

    if not allow_stationary_dodge and move_length < dodge_template.minimum_dodge_input then
        return false
    end

    local moving_forward = move.y > 0
    local allow_dodge_while_moving_forward = allow_diagonal_forward_dodge
    local allow_always_dodge = input_extension:get("always_dodge")
    allow_dodge_while_moving_forward = allow_dodge_while_moving_forward or allow_always_dodge

    if not allow_dodge_while_moving_forward and moving_forward then
        return false
    elseif move_length == 0 then
        return true
    else
        local normalized_move = move / move_length
        local x = normalized_move.x
        local y = normalized_move.y

        return allow_always_dodge or y <= 0 or math.abs(x) > 0.707
    end
end

local has_any_movement_pressed = function()
    local any_movement_pressed = false
    for _, value in pairs(movement_pressed) do
        if value then
            any_movement_pressed = true
            break
        end
    end
    return any_movement_pressed
end

local same_dodge_jump_bind = function(self)
    local aliases = self._aliases
    local device_type = DEVICE_TYPE_MAP_ALIASES[InputDevice.last_pressed_device.device_type]
    return aliases.jump[device_type] == aliases.dodge[device_type]
end

local should_sprint_timeout = function ()
    return elapsed(last_press_sprinting) > mod.settings["start_sprint_buffer"]
end

--------------------------
-- MOD SETTINGS CACHING --
--------------------------

mod.settings = {
    enable_hold_to_sprint                  = mod:get("enable_hold_to_sprint"),
    start_sprint_buffer                    = mod:get("start_sprint_buffer"),
    enable_dodge_on_diagonal_sprint        = mod:get("enable_dodge_on_diagonal_sprint"),
    enable_keep_sprint_after_weapon_action = mod:get("enable_keep_sprint_after_weapon_action"),
    enable_debug_modding_tools             = mod:get("enable_debug_modding_tools"),
}

mod.on_setting_changed = function(setting_id)
    mod.settings[setting_id] = mod:get(setting_id)
    mod.keep_sprint = false
end

------------------------
-- ON ALL MODS LOADED --
------------------------

mod.on_all_mods_loaded = function()
    -- Update is_in_hub
    is_in_hub = check_is_in_hub()

    -- WATCHER
    -- modding_tools:watch("character_state", mod, "character_state")
    -- modding_tools:watch("keep_sprint", mod, "keep_sprint")
    -- modding_tools:watch("keep_sprint_press", mod, "keep_sprint_press")
end

---------------------------
-- ON GAME STATE CHANGED --
---------------------------

mod.on_game_state_changed = function(status, state_name)
    -- Update is_in_hub
    is_in_hub = check_is_in_hub()

    -- Force hold sprint in vanilla settings
    local input_settings = Managers.save:account_data().input_settings
    input_settings.hold_to_sprint = true
end

-----------------------
-- PROMISE FUNCTIONS --
-----------------------

local function setPromise(from)
    if not mod.promise_sprint and (ALLOWED_CHARACTER_STATE[character_state] or is_in_hub) then
        mod.promise_sprint = true
        if modding_tools then debug:print_mod("setPromiseFrom: " .. from) end
    end
    mod.keep_sprint = false
end

local function clearPromise(from)
    if mod.promise_sprint then
        mod.promise_sprint = false
        if modding_tools then debug:print_mod("clearPromiseFrom: " .. from) end
    end
    if mod.keep_sprint then
        mod.keep_sprint = false
        if modding_tools then debug:print_mod("clearKeepSprintFrom: " .. from) end
    end
end

local function isPromised()
    local promise = mod.promise_sprint

    if promise then
        if is_in_hub then
            if not has_any_movement_pressed() and should_sprint_timeout() then
                clearPromise("Promised Hub Sprint Timeout")
                return false
            end
        else
            if not movement_pressed.move_forward and should_sprint_timeout() then
                clearPromise("Promised Sprint Timeout")
                return false
            end
        end
        if modding_tools then debug:print_mod("Attempting to sprint for you !!!") end
    end

    return promise
end

---------------
-- FUNCTIONS --
---------------

local empty_action_sprint_check = function(action_name)
    do return end
    if character_state == "sprinting" or mod.keep_sprint then
        local unit = Managers.player:local_player(1).player_unit
        if unit then
            local unit_data_extension = ScriptUnit.extension(unit, "unit_data_system")
            local visual_loadout_extension = unit_data_extension and unit_data_extension._visual_loadout_extension
            if visual_loadout_extension then
                local inventory_component = visual_loadout_extension._inventory_component
                local wielded_slot = inventory_component and visual_loadout_extension._inventory_component.wielded_slot
                local weapon_extension = visual_loadout_extension._weapon_extension
                local slot_weapon = weapon_extension and weapon_extension._weapons[wielded_slot]
                local wieldable_component = visual_loadout_extension._wieldable_slot_components[wielded_slot]
                local weapon_template = slot_weapon and slot_weapon.weapon_template
                local action_inputs = weapon_template and weapon_template.action_inputs
                local weapon_actions = weapon_template and weapon_template.actions

                if action_name == "weapon_reload_pressed" then
                    local weapon_has_reload = action_inputs and (action_inputs.reload or action_inputs.reload_pressed) ~= nil or false
                    local weapon_has_vent = action_inputs and action_inputs.vent ~= nil or false

                    if weapon_has_reload then
                        if wieldable_component.current_ammunition_reserve == 0 or wieldable_component.current_ammunition_clip == wieldable_component.max_ammunition_clip then
                            setPromise("empty_reload_pressed")
                            mod.keep_sprint_empty_action = true
                        end
                    elseif weapon_has_vent then
                        local warp_charge_component = weapon_extension and weapon_extension._warp_charge_component
                        local warp_charge_percentage = warp_charge_component and warp_charge_component.current_percentage
                        if warp_charge_percentage == 0 then
                            setPromise("empty_reload_pressed")
                            mod.keep_sprint_empty_action = true
                        end
                    end

                elseif action_name == "weapon_extra_pressed"  then
                    local weapon_special_tweak_data = weapon_template and weapon_template.weapon_special_tweak_data
                    local special_needs_charges = weapon_special_tweak_data and weapon_special_tweak_data.num_charges_to_consume_on_activation
                    local action_weapon_special = weapon_actions and weapon_actions.action_weapon_special
                    local special_kind = action_weapon_special and action_weapon_special.kind

                    local ignore_active_special, is_toggle_special = false, false
                    if weapon_template then
                        for _, action in pairs(weapon_template.actions or {}) do
                            if ignore_active_special ~= true and string.find(action.kind, "activate_special") and action.activation_cooldown == nil then
                                ignore_active_special = true
                            end
                            if is_toggle_special ~= true and string.find(action.kind, "toggle_special") then
                                is_toggle_special = true
                            end
                            if ignore_active_special and is_toggle_special then break end
                        end
                    end

                    if
                        (wieldable_component.special_active and not ignore_active_special and not is_toggle_special) or
                        ((special_needs_charges ~= nil or wieldable_component.max_num_special_charges ~= 0) and wieldable_component.num_special_charges < (special_needs_charges or 1)) or
                        (special_kind == "ranged_load_special" and wieldable_component.current_ammunition_reserve == 0 and wieldable_component.num_special_charges == 0)
                    then
                        setPromise("empty_special_pressed")
                        mod.keep_sprint_empty_action = true
                    end
                end
            end
        end
    end
end

------------------------------
-- ON USER SETTINGS REQUIRE --
------------------------------

-- REMOVE HOLD SPRINT FROM VANILLA SETTINGS --

mod:hook_require("scripts/settings/options/input_settings", function(instance)
    for i, setting in ipairs(instance.settings) do
        if setting.id == "hold_to_sprint" then
            table.remove(instance.settings, i)
            break
        end
    end
end)

----------------
-- ON TRIGGER --
----------------

-- CLEAR PROMISE ON ENTER OR EXIT GAMEPLAY

mod:hook_safe("GameplayStateRun", "on_enter", function(...)
    clearPromise("ENTER_GAMEPLAY")
    mod.promise_sprint = false
    mod.promise_dodge = false
    mod.keep_sprint = false
    mod.keep_sprint_press = false
    mod.keep_sprint_empty_action = false
end)

mod:hook_safe("GameplayStateRun", "on_exit", function(...)
    clearPromise("EXIT_GAMEPLAY")
    mod.promise_sprint = false
    mod.promise_dodge = false
    mod.keep_sprint = false
    mod.keep_sprint_press = false
    mod.keep_sprint_empty_action = false
end)

-- CLEARING PROMISE ON WEAPON ACTION

mod:hook_safe("PlayerCharacterStateWalking", "on_enter", function(self, unit, dt, t, previous_state, params)
    if self._unit_data_extension._player.viewport_name == 'player1' then
        if mod.promise_sprint then
            clearPromise("wants_to_stop_by_" .. previous_state)
            if mod.settings["enable_keep_sprint_after_weapon_action"] then
                mod.keep_sprint = true
            end
        end
        if mod.keep_sprint then
            local weapon_template_name = self._weapon_action_component.template_name or ""
            local is_agile_weapon = IS_AGILE_WEAPON[weapon_template_name]

            if previous_state ~= "sprinting" and (current_action == "none" or mod.keep_sprint_press or is_agile_weapon) then
                setPromise("was_" .. previous_state)
            elseif is_agile_weapon and (string.find(previous_action, "heavy") or string.find(current_action, "heavy")) then
                setPromise("agile_weapon_heavy")
            elseif mod.keep_sprint_empty_action then
                setPromise("empty_action")
            end
        end
    end
end)

-- CLEAR PROMISED DODGE ON DODGE

mod:hook_safe("PlayerCharacterStateDodging", "on_enter", function(self, unit, dt, t, previous_state, params)
    if self._unit_data_extension._player.viewport_name == 'player1' then
        mod.promise_dodge = false
    end
end)

-- DO STUFF ON ACTION CHANGE

local function _on_action_change(self)
    local registered_components = self._registered_components
    local handler_data = registered_components["weapon_action"]
    local running_action = handler_data and handler_data.running_action
    local action_settings = running_action and running_action._action_settings
    local new_action = action_settings and action_settings.name or "none"

    if handler_data and current_action ~= new_action then
        previous_action = current_action ~= "none" and current_action or previous_action
        current_action = new_action

        if current_action ~= "none" then
            -- START ACTION
            is_action_allowed_during_sprint = action_settings.allowed_during_sprint
        else
            -- FINISH ACTION
            is_action_allowed_during_sprint = true
        end
    end
end

mod:hook_safe("ActionHandler", "start_action", function(self, id, action_objects, action_name, action_params, action_settings, used_input, t, ...)
    if self._unit_data_extension._player.viewport_name == 'player1' then
        _on_action_change(self)
    end
end)

mod:hook_safe("ActionHandler", "_finish_action", function(self, handler_data, reason, data, t, ...)
    if self._unit_data_extension._player.viewport_name == 'player1' then
        _on_action_change(self)

        if mod.keep_sprint then
            if reason == "action_complete" or reason == "hold_input_released" then
                setPromise(reason)
            end
        end
    end
end)

mod:hook_safe("ActionHandler", "server_correction_occurred", function(self, id, action_objects, action_params, actions)
    if self._unit_data_extension._player.viewport_name == 'player1' then
        _on_action_change(self)
    end
end)

-- UPDATE CHARACTER STATE VARIABLE AND CLEAR PROMISE ON UNALLOWED CHARACTER STATE

local _on_character_state_change = function (self)
    character_state = self._state_current.name
    if not ALLOWED_CHARACTER_STATE[character_state] and not is_in_hub then
        clearPromise("Unallowed Character State")
        mod.promise_dodge = false
    end
    if TRAVELING_CHARACTER_STATE[character_state] then
        mod.keep_sprint_press = false
    end
    if character_state == "sprinting" then
        mod.keep_sprint_empty_action = false
    end
end

mod:hook_safe("CharacterStateMachine", "fixed_update", function(self, unit, dt, t, frame, ...)
    if character_state ~= "" then
        mod:hook_disable("CharacterStateMachine", "fixed_update")
    end
    if self._unit_data_extension._player.viewport_name == 'player1' then
        _on_character_state_change(self)
    end
end)

mod:hook_safe("CharacterStateMachine", "_change_state", function(self, unit, dt, t, next_state, ...)
    if self._unit_data_extension._player.viewport_name == 'player1' then
        _on_character_state_change(self)
    end
end)

mod:hook_safe("CharacterStateMachine", "server_correction_occurred", function(self, unit)
    if self._unit_data_extension._player.viewport_name == 'player1' then
        _on_character_state_change(self)
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

    action_pressed[action_name] = pressed

    -- While on hub
    if is_in_hub and MOVEMENT_ACTIONS[action_name] then
        local last_pressed = movement_pressed[action_name]
        movement_pressed[action_name] = pressed
        -- On releasing movement
        if not pressed and last_pressed then
            if not has_any_movement_pressed() then
                clearPromise("Released All Movement")
            end
        end
        return out
    end

    if action_name == "move_forward" then
        -- On releasing forward
        if not pressed and movement_pressed.move_forward then
            clearPromise("Realeased Forward")
        end
        movement_pressed.move_forward = pressed
        return out
    end

    if action_name == "move_backward" then
        -- On pressing backward
        if pressed and not movement_pressed.move_backward then
            clearPromise("Pressed Backward")
        end
        movement_pressed.move_backward = pressed
        return out
    end

    -- Buffer pressing dodge and record last_press_dodge
    if action_name == "dodge" then
        if pressed then
            mod.promise_dodge = true
            last_press_dodge = time_now()
        end
        return out or mod.promise_dodge and elapsed(last_press_dodge) < DODGE_PRESS_BUFFER
    end

    -- Prevent jumping on valid dodge
    if action_name == "jump" then
        if pressed then
            if mod.settings["enable_dodge_on_diagonal_sprint"] then
                if character_state == "sprinting" and same_dodge_jump_bind(self) and player_movement_valid_for_dodge() then
                    return false
                end
            end
        end
        return out
    end

    if action_name == "weapon_reload_pressed" or action_name == "weapon_extra_pressed" then
        if pressed then
            if mod.settings["enable_keep_sprint_after_weapon_action"] then
                empty_action_sprint_check(action_name)
            end
        end
        return out
    end

    if action_name == "sprinting" then
        -- Promise sprinting
        if pressed and not mod.settings["enable_hold_to_sprint"] then
            setPromise("Pressed Sprint")
            last_press_sprinting = time_now()
            if ALLOWED_CHARACTER_STATE[character_state] and not TRAVELING_CHARACTER_STATE[character_state] then
                mod.keep_sprint_press = true
            end
        end
        -- Compatibility with Guarantee Special Action
        if guarantee_special_action then
            if guarantee_special_action.promise_exist and guarantee_special_action.interrupt_sprinting_special then
                return false
            end
        end
        -- Compatibility with ToggleAltFire
        if toggle_alt_fire then
            if action_pressed["action_two_hold"] then
                return false
            end
        end
        -- Prevent sprinting on pressing dodge
        if mod.settings["enable_dodge_on_diagonal_sprint"] then
            if elapsed(last_press_dodge) < DODGE_PRESS_BUFFER then
                return false
            end
        end
        -- Do sprinting if promised
        return out or isPromised()
    end

    return out
end

mod:hook("InputService", "_get", _input_hook)
mod:hook("InputService", "_get_simulate", _input_hook)
