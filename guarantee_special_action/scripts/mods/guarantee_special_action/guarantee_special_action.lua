-- Guarantee Special Action by KamiUnitY. Ver. 1.1.11

local mod = get_mod("guarantee_special_action")
local modding_tools = get_mod("modding_tools")

local Ammo = require("scripts/utilities/ammo")

---------------
-- CONSTANTS --
---------------

local PROMISE_ACTION_MAP = {
    weapon_extra_pressed  = "action_special",
    weapon_reload_pressed = "action_reload",
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

local ALLOWED_SLOT = {
    slot_primary   = true,
    slot_secondary = true,
}

local DEFAULT_INTERVAL_DO_PROMISE = 0.05

local DEFAULT_PROMISE_BUFFER = 1.0

local WEAPONS = mod:io_dofile("guarantee_special_action/scripts/mods/guarantee_special_action/guarantee_special_action_weapons")

---------------
-- VARIABLES --
---------------

mod.promise_exist = false

mod.is_toggle_special = false
mod.is_parry_special = false

mod.special_requires_ammo = false
mod.special_needs_charges = nil
mod.ignore_active_special = false

mod.special_releases_action_one = false
mod.special_releases_action_two = false
mod.reload_releases_action_one  = false
mod.reload_releases_action_two  = false

mod.pressing_buffer = nil
mod.promise_buffer = DEFAULT_PROMISE_BUFFER

mod.interval_do_promise = DEFAULT_INTERVAL_DO_PROMISE

mod.promises = {
    action_special = false,
    action_reload  = false,
}

local is_in_hub = false

local character_state = ""

local current_action = ""
local previous_action = ""

local current_slot = ""
local weapon_template = nil

local allowed_chain_special = true

local doing_special = false
local doing_reload = false
local doing_melee_start = false
local doing_push = false

local prevent_attack_while_parry = false

local action_states = {
    action_special = {
        last_set_promise = 0,
        last_do_promise = 0,
        last_press_action = 0,
        allowed_set_promise = false,
    },
    action_reload = {
        last_set_promise = 0,
        last_do_promise = 0,
        last_press_action = 0,
        allowed_set_promise = false,
    },
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

local has_key_containing = function(table, pattern)
    for key, _ in pairs(table) do
        if string.find(key, pattern) then
            return true
        end
    end
    return false
end

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

--------------------------
-- MOD SETTINGS CACHING --
--------------------------

mod.settings = {
    enable_blocking_cancel_special = mod:get("enable_blocking_cancel_special"),
    enable_ads_cancel_special      = mod:get("enable_ads_cancel_special"),
    enable_debug_modding_tools     = mod:get("enable_debug_modding_tools"),
}

mod.on_setting_changed = function(setting_id)
    mod.settings[setting_id] = mod:get(setting_id)
end

------------------------
-- ON ALL MODS LOADED --
------------------------

mod.on_all_mods_loaded = function()
    -- Update is_in_hub
    is_in_hub = check_is_in_hub()

    -- WATCHER
    -- modding_tools:watch("promise_exist",mod,"promise_exist")
    -- modding_tools:watch("character_state",mod,"character_state")
    -- modding_tools:watch("doing_reload",mod,"doing_reload")
    -- modding_tools:watch("doing_special",mod,"doing_special")
    -- modding_tools:watch("previous_action",mod,"previous_action")
    -- modding_tools:watch("current_action",mod,"current_action")
    -- modding_tools:watch("promise_buffer",mod,"promise_buffer")
    -- modding_tools:watch("allowed_chain_special",mod,"allowed_chain_special")
    -- modding_tools:watch("prevent_attack_while_parry",mod,"prevent_attack_while_parry")
    -- modding_tools:watch("promise_prevent_attack_while_parry",mod,"promise_prevent_attack_while_parry")
end

---------------------------
-- ON GAME STATE CHANGED --
---------------------------

mod.on_game_state_changed = function(status, state_name)
    -- Update is_in_hub
    is_in_hub = check_is_in_hub()
end

-----------------------
-- PROMISE FUNCTIONS --
-----------------------

local function setPromise(action, from)
    if not mod.promises[action] and action_states[action].allowed_set_promise then
        local unit = Managers.player:local_player(1).player_unit
        if not unit then return end

	    local unit_data_extension = ScriptUnit.extension(unit, "unit_data_system")
        if not unit_data_extension then return end

	    local inventory_slot_component = unit_data_extension:read_component(current_slot)
        if not inventory_slot_component then return end

        local visual_loadout_system = ScriptUnit.extension(unit, "visual_loadout_system")
        if not visual_loadout_system then return end

        local wieldable_component = visual_loadout_system._wieldable_slot_components[current_slot]
        if not wieldable_component then return end

        if action == "action_special" then
            if doing_special then
                return
            end
            if not mod.ignore_active_special and not mod.is_toggle_special and wieldable_component.special_active then
                return
            end
            if mod.special_requires_ammo and wieldable_component.current_ammunition_reserve == 0 then
                return
            end
            if wieldable_component.overheat_state == "lockout" then
                return
            end
            if mod.special_needs_charges and wieldable_component.num_special_charges < mod.special_needs_charges then
                return
            end
        elseif action == "action_reload" then
            local current_ammunition_clip = Ammo.current_ammo_in_clips(inventory_slot_component)
            local max_ammunition_clip = Ammo.max_ammo_in_clips(inventory_slot_component)

            if doing_reload then
                return
            end
            if wieldable_component.current_ammunition_reserve == 0 or current_ammunition_clip == max_ammunition_clip then
                return
            end
        else
            return
        end

        mod.promises[action] = true
        mod.promise_exist = true
        action_states[action].last_set_promise = time_now()
        if modding_tools then debug:print_mod("Set " .. action .. " promise from " .. from) end
    end

    if mod.is_parry_special and action == "action_special" then
        prevent_attack_while_parry = true
    end
end

local function clearPromise(action, from)
    if mod.promises[action] then
        mod.promises[action] = false
        mod.promise_exist = false
        for _, promise in pairs(mod.promises) do
            if promise then
                mod.promise_exist = true
                break
            end
        end
        if modding_tools then debug:print_mod("Clear " .. action .. " promise from " .. from) end
    end

    if from ~= "start_action" then
        prevent_attack_while_parry = false
    end
end

local function clearAllPromises(from)
    if mod.promise_exist then
        for key in pairs(mod.promises) do
            clearPromise(key, from)
        end
        mod.promise_exist = false
        if modding_tools then debug:print_mod("Clear all promise from " .. from) end
    end

    if from ~= "start_action" then
        prevent_attack_while_parry = false
    end
end

local function isPromised(action)
    local promise = mod.promises[action]

    if promise then
        local interval_do_promise = mod.interval_do_promise or DEFAULT_INTERVAL_DO_PROMISE
        if elapsed(action_states[action].last_do_promise) < interval_do_promise then
            return false
        end
        if elapsed(action_states[action].last_set_promise) >= mod.promise_buffer then
            clearPromise(action, "buffer_timeout")
            return false
        end
        action_states[action].last_do_promise = time_now()
        if modding_tools then debug:print_mod("Attempting to do " .. action .. " action !!!") end
    end

    return promise
end

----------------
-- ON TRIGGER --
----------------

-- CLEAR PROMISE ON ENTER OR EXIT GAMEPLAY

mod:hook_safe("GameplayStateRun", "on_enter", function(...)
    clearAllPromises("ENTER_GAMEPLAY")
end)

mod:hook_safe("GameplayStateRun", "on_exit", function(...)
    clearAllPromises("EXIT_GAMEPLAY")
end)

-- ONLY ALLOW PROMISE ON WEAPON THAT HAVE THE ACTION AND CLEAR PROMISE ON CHANGE WEAPON

local function _on_slot_wielded(self)
    local inventory_component = self._inventory_component
    local wielded_slot = inventory_component.wielded_slot

    if wielded_slot ~= current_slot then
        current_slot = wielded_slot
        local slot_weapon = self._weapons[current_slot]
        weapon_template = slot_weapon and slot_weapon.weapon_template
        local _weapon_data = weapon_template and WEAPONS[weapon_template.name] or {}

        clearAllPromises("on_slot_wielded")

        mod.ignore_active_special = _weapon_data.ignore_active_special or false
        mod.special_needs_charges = _weapon_data.special_needs_charges or nil
        mod.special_requires_ammo = _weapon_data.special_requires_ammo or false
        mod.is_parry_special = _weapon_data.special_parry or false
        mod.pressing_buffer = _weapon_data.pressing_buffer or nil
        mod.promise_buffer = _weapon_data.promise_buffer or DEFAULT_PROMISE_BUFFER
        mod.interval_do_promise = _weapon_data.interval_do_promise or DEFAULT_INTERVAL_DO_PROMISE
        mod.special_releases_action_one = _weapon_data.special_releases_action_one or false
        mod.special_releases_action_two = _weapon_data.special_releases_action_two or false
        mod.reload_releases_action_one = _weapon_data.reload_releases_action_one or false
        mod.reload_releases_action_two = _weapon_data.reload_releases_action_two or false

        action_states["action_reload"].allowed_set_promise = _weapon_data.action_reload or false
        action_states["action_special"].allowed_set_promise = _weapon_data.action_special or false

        mod.is_toggle_special = false
        if weapon_template then
            for _, action in pairs(weapon_template.actions or {}) do
                if string.find(action.kind, "toggle_special") then
                    mod.is_toggle_special = true
                    break
                end
            end
        end
    end
end

mod:hook_safe("PlayerUnitWeaponExtension", "fixed_update", function(self, unit, dt, t, fixed_frame)
    if current_slot ~= "" and weapon_template ~= nil then
        mod:hook_disable("PlayerUnitWeaponExtension", "fixed_update")
    end
    if self._player.viewport_name == "player1" then
        _on_slot_wielded(self)
    end
end)

mod:hook_safe("PlayerUnitWeaponExtension", "on_slot_wielded", function(self, slot_name, t, skip_wield_action)
    if self._player.viewport_name == "player1" then
        _on_slot_wielded(self)
    end
end)

mod:hook_safe("PlayerUnitWeaponExtension", "server_correction_occurred", function(self, unit)
    if self._player.viewport_name == "player1" then
        _on_slot_wielded(self)
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

        -- START ACTION
        if current_action ~= "none" then
            local allowed_chain_actions = action_settings.allowed_chain_actions
            allowed_chain_special = allowed_chain_actions and (
                has_key_containing(allowed_chain_actions, "special_action") or
                has_key_containing(allowed_chain_actions, "bash") or
                has_key_containing(allowed_chain_actions, "stab")
            )

            if string.find(current_action, "action_melee_start") then
                doing_melee_start = true
            elseif current_action == "action_push" then
                doing_push = true
            end

            if modding_tools then debug:print_mod("START " .. current_action) end

        -- FINISH ACTION
        else
            if previous_action == "action_parry_special" then
                prevent_attack_while_parry = false
            end

            allowed_chain_special = true
            doing_special = false
            doing_reload = false
            doing_melee_start = false
            doing_push = false

            if modding_tools then debug:print_mod("END " .. previous_action) end
        end

    end
end

mod:hook_safe("ActionHandler", "start_action", function(self, id, action_objects, action_name, action_params, action_settings, used_input, t, ...)
    if self._unit_data_extension._player.viewport_name == 'player1' then
        _on_action_change(self)

        if used_input and string.find(used_input, "weapon_extra") then
            clearPromise("action_special", "start_action")
            doing_special = true
        elseif used_input and string.find(used_input, "weapon_reload") then
            clearPromise("action_reload", "start_action")
            doing_reload = true
        end
    end
end)

mod:hook_safe("ActionHandler", "_finish_action", function(self, handler_data, reason, data, t, ...)
    if self._unit_data_extension._player.viewport_name == 'player1' then
        _on_action_change(self)
    end
end)

mod:hook_safe("ActionHandler", "server_correction_occurred", function(self, id, action_objects, action_params, actions)
    if self._unit_data_extension._player.viewport_name == 'player1' then
        _on_action_change(self)
    end
end)

-- UPDATE CHARACTER STATE VARIABLE AND CLEAR PROMISE ON UNALLOWED CHARACTER STATE

local _on_character_state_change = function(self)
    character_state = self._state_current.name
    if not ALLOWED_CHARACTER_STATE[character_state] then
        clearAllPromises("UNALLOWED CHARACTER STATE")
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

-- UPDATE DOING RELOAD VARIABLE

mod:hook_safe("ActionReloadState", "start", function(self, action_settings, t, time_scale, ...)
    if self._player.viewport_name == 'player1' then
        doing_reload = true
    end
end)

mod:hook_safe("ActionReloadState", "finish", function(self, reason, data, t, time_in_action)
    if self._player.viewport_name == 'player1' then
        doing_reload = false
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
        if ALLOWED_CHARACTER_STATE[character_state] and ALLOWED_SLOT[current_slot] then
            if pressed then
                action_states[promise_action].last_press_action = self._last_time
                clearAllPromises("input_pressed")
                setPromise(promise_action, "input_pressed")
            else
                if mod.pressing_buffer then
                    if self._last_time - action_states[promise_action].last_press_action < mod.pressing_buffer then
                        setPromise(promise_action, "pressing_buffer")
                    end
                end
            end
        end
        if promise_action == "action_special" and not allowed_chain_special then
            return false
        end
        return out or isPromised(promise_action)
    end

    -- Cancel promise on action two pressed
    if action_name == "action_two_pressed" then
        if pressed then
            if current_slot == "slot_primary" and mod.settings["enable_blocking_cancel_special"] then
                clearAllPromises("try_melee_block")
            elseif current_slot == "slot_secondary" and mod.settings["enable_ads_cancel_special"] then
                clearAllPromises("try_ranged_ads")
            end
        end
        return out
    end

    -- Some weapons wont get activated with weapon_extra_pressed
    if action_name == "weapon_extra_hold" then
        if mod.promises.action_special then
            return true
        end
        return out
    end

    -- Prevent parry getting cancel by holding action one
    if mod.is_parry_special then
        if prevent_attack_while_parry then
            if action_name == "action_one_pressed" then
                if pressed then
                    prevent_attack_while_parry = false
                end
            elseif action_name == "action_one_hold" then
                if doing_special or doing_push then
                    return false
                end
            end
        end
        if mod.promises.action_special then
            if character_state ~= "sprinting" then
                if action_name == "action_two_hold" then
                    return true
                end
            end
        end
    end

    -- Auto release weapon holding action on promise_exist
    if mod.promise_exist then
        if doing_push or (doing_melee_start and allowed_chain_special) then
            return out
        end

        if action_name == "action_one_pressed" or action_name == "action_one_hold" then
            if mod.special_releases_action_one and mod.promises.action_special then
                return false
            end
            if mod.reload_releases_action_one and mod.promises.action_reload then
                return false
            end
        end

        if action_name == "action_two_pressed" or action_name == "action_two_hold" then
            if mod.special_releases_action_two and mod.promises.action_special then
                return false
            end
            if mod.reload_releases_action_two and mod.promises.action_reload then
                return false
            end
        end
    end

    return out
end

mod:hook("InputService", "_get", _input_hook)
mod:hook("InputService", "_get_simulate", _input_hook)
