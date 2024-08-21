-- Guarantee Special Action by KamiUnitY. Ver. 1.0.0

local mod = get_mod("guarantee_special_action")
local modding_tools = get_mod("modding_tools")

---------------
-- CONSTANTS --
---------------

local PROMISE_ACTION_MAP = {
    weapon_extra_pressed = "action_special",
    weapon_reload        = "action_reload",
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

local DEFAULT_PROMISE_BUFFER = 0.5

local WEAPONS = mod:io_dofile("guarantee_special_action/scripts/mods/guarantee_special_action/guarantee_special_action_weapons")

---------------
-- VARIABLES --
---------------

mod.promise_exist = false

mod.is_toggle_special = false
mod.is_ammo_special = false

mod.ignore_active_special = false
mod.interrupt_sprinting_special = false

mod.promise_buffer = DEFAULT_PROMISE_BUFFER

mod.promises = {
    action_special = false,
    action_reload  = false,
}

local character_state = ""

local current_action = ""
local previous_action = ""

local allowed_chain_special = true

local doing_special = false
local doing_reload = false
local doing_melee_start = false
local doing_push = false

local prevent_attack_while_parry = false

local allowed_set_promise = {
    action_special = false,
    action_reload  = false,
}

local do_special_release = {
    action_one = false,
    action_two = false,
}

local current_slot = ""
local weapon_template = nil

local last_set_promise = {
    action_special = 0,
    action_reload  = 0,
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
    -- WATCHER
    -- modding_tools:watch("promise_exist",mod,"promise_exist")
    -- modding_tools:watch("character_state",mod,"character_state")
    -- modding_tools:watch("doing_reload",mod,"doing_reload")
    -- modding_tools:watch("doing_special",mod,"doing_special")
    -- modding_tools:watch("current_action",mod,"current_action")
    -- modding_tools:watch("promise_buffer",mod,"promise_buffer")
    -- modding_tools:watch("allowed_chain_special",mod,"allowed_chain_special")
    -- modding_tools:watch("prevent_attack_while_parry",mod,"prevent_attack_while_parry")
end

-----------------------
-- PROMISE FUNCTIONS --
-----------------------

local function setPromise(action, from)
    local unit = Managers.player:local_player(1).player_unit
    if unit then
        local visual_loadout_system = ScriptUnit.extension(unit, "visual_loadout_system")
        if visual_loadout_system then
            local wieldable_component = visual_loadout_system._wieldable_slot_components[current_slot]
            if action == "action_special" then
                if not mod.ignore_active_special and not mod.is_toggle_special and wieldable_component.special_active then
                    return
                end
                if mod.is_ammo_special and wieldable_component.current_ammunition_reserve == 0 then
                    return
                end
            elseif action == "action_reload" then
                if wieldable_component.current_ammunition_reserve == 0 or wieldable_component.current_ammunition_clip == wieldable_component.max_ammunition_clip then
                    return
                end
            end
        end
    end
    if not mod.promises[action] and allowed_set_promise[action] then
        if doing_reload and action == "action_reload" then
            return
        elseif doing_special and action == "action_special" then
            return
        end
        mod.promises[action] = true
        mod.promise_exist = true
        last_set_promise[action] = time_now()
        if action == "action_special" and mod.is_parry_special then
            prevent_attack_while_parry = true
        end
        if modding_tools then debug:print_mod("Set " .. action .. " promise from " .. from) end
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
        if action == "action_special" and from ~= "start_action" then
            prevent_attack_while_parry = false
        end
        if modding_tools then debug:print_mod("Clear " .. action .. " promise from " .. from) end
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
end

local function isPromised(action, promise)
    if elapsed(last_set_promise[action]) >= mod.promise_buffer then
        clearPromise(action, "buffer_timeout")
        return false
    end
    if doing_melee_start or doing_push then
        return false
    end
    if promise then
        if modding_tools then debug:print_mod("Attempting to do " .. action .. " action !!!") end
    end
    return promise
end

----------------
-- ON TRIGGER --
----------------

-- ONLY ALLOW PROMISE ON WEAPON THAT HAVE THE ACTION AND CLEAR PROMISE ON CHANGE WEAPON

local function _on_slot_wielded(self, slot_name)
    current_slot = slot_name
    local slot_weapon = self._weapons[slot_name]
    if slot_weapon ~= nil and slot_weapon.weapon_template ~= nil then
        weapon_template = slot_weapon.weapon_template
        local _weapon_data = WEAPONS[weapon_template.name]
        allowed_set_promise.action_special = false
        do_special_release.action_one = false
        do_special_release.action_two = false
        mod.ignore_active_special = false
        mod.interrupt_sprinting_special = false
        mod.is_ammo_special = false
        mod.is_parry_special = false
        mod.promise_buffer = DEFAULT_PROMISE_BUFFER
        if _weapon_data then
            allowed_set_promise.action_special = _weapon_data.action_special or false
            do_special_release.action_one = _weapon_data.special_releases_action_one or false
            do_special_release.action_two = _weapon_data.special_releases_action_two or false
            mod.ignore_active_special = _weapon_data.ignore_active_special or false
            mod.interrupt_sprinting_special = _weapon_data.interrupt_sprinting_special or false
            mod.is_ammo_special = _weapon_data.special_ammo or false
            mod.is_parry_special = _weapon_data.special_parry or false
            mod.promise_buffer = _weapon_data.promise_buffer or DEFAULT_PROMISE_BUFFER
        end
        local action_input_hierarchy = weapon_template.action_input_hierarchy
        allowed_set_promise.action_reload = false
        if action_input_hierarchy.reload then
            allowed_set_promise.action_reload = true
        end
        mod.is_toggle_special = false
        for _, action in pairs(weapon_template.actions) do
            if action.kind == "toggle_special" then
                mod.is_toggle_special = true
                break
            end
        end
    end
end

mod:hook_safe("PlayerUnitWeaponExtension", "_wielded_weapon", function(self, inventory_component, weapons)
    if current_slot ~= "" and weapon_template ~= nil then
        mod:hook_disable("PlayerUnitWeaponExtension", "_wielded_weapon")
    end
    if self._player.viewport_name == "player1" then
        local wielded_slot = inventory_component.wielded_slot
        if wielded_slot ~= nil and wielded_slot ~= current_slot then
            _on_slot_wielded(self, wielded_slot)
        end
    end
end)

mod:hook_safe("PlayerUnitWeaponExtension", "on_slot_wielded", function(self, slot_name, t, skip_wield_action)
    if self._player.viewport_name == "player1" then
        clearAllPromises("on_slot_wielded")
        _on_slot_wielded(self, slot_name)
    end
end)

-- CLEAR PROMISE ON START ACTION

mod:hook_safe("ActionHandler", "start_action", function(self, id, action_objects, action_name, action_params, action_settings, used_input, t, transition_type, condition_func_params, automatic_input, reset_combo_override)
        if self._unit_data_extension._player.viewport_name == 'player1' then
            current_action = action_name

            local chain_special = weapon_template
                and weapon_template.actions
                and weapon_template.actions[action_name]
                and weapon_template.actions[action_name].allowed_chain_actions
                and weapon_template.actions[action_name].allowed_chain_actions["special_action"]
            allowed_chain_special = chain_special ~= nil

            if used_input and string.find(used_input, "weapon_extra") then
                clearPromise("action_special", "start_action")
                doing_special = true
            elseif used_input and string.find(used_input, "weapon_reload") then
                clearPromise("action_reload", "start_action")
                doing_reload = true
            end

            if string.find(action_name, "action_melee_start") then
                doing_melee_start = true
            elseif action_name == "action_push" then
                doing_push = true
            end

            if modding_tools then debug:print_mod("START " .. action_name) end
        end
    end)

mod:hook_safe("ActionHandler", "_finish_action", function(self, handler_data, reason, data, t, next_action_params)
    if self._unit_data_extension._player.viewport_name == 'player1' then
        if current_action == "action_parry_special" then
            prevent_attack_while_parry = false
        end

        allowed_chain_special = true

        doing_special = false
        doing_reload = false
        doing_melee_start = false
        doing_push = false

        previous_action = current_action
        current_action = "none"

        if modding_tools then debug:print_mod("END " .. previous_action) end
    end
end)

-- UPDATE CHARACTER STATE VARIABLE AND CLEAR PROMISE ON UNALLOWED CHARACTER STATE

local _update_character_state = function(self)
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
        _update_character_state(self)
    end
end)

mod:hook_safe("CharacterStateMachine", "_change_state", function(self, unit, dt, t, next_state, ...)
    if self._unit_data_extension._player.viewport_name == 'player1' then
        _update_character_state(self)
    end
end)

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

    local promise_action = PROMISE_ACTION_MAP[action_name]
    if promise_action then
        if pressed then
            clearAllPromises("Input pressed")
            if ALLOWED_CHARACTER_STATE[character_state] and ALLOWED_SLOT[current_slot] then
                setPromise(promise_action, "Input pressed")
            end
        end
        local promise = mod.promises[promise_action]
        return out or (promise and isPromised(promise_action, promise))
    end

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

    if action_name == "weapon_extra_hold" then
        if mod.promises.action_special then
            return true
        end
        return out
    end

    if prevent_attack_while_parry then
        if action_name == "action_one_pressed" then
            if pressed then
                prevent_attack_while_parry = false
            end
        elseif action_name == "action_one_hold" then
            return false
        end
    end

    if mod.promise_exist then
        if mod.interrupt_sprinting_special then
            if action_name == "sprinting" then
                return false
            end
        end

        if doing_push or (doing_melee_start and allowed_chain_special) then
            return out
        end

        if do_special_release.action_one then
            if action_name == "action_one_pressed" or action_name == "action_one_hold" then
                return false
            end
        end

        if do_special_release.action_two then
            if action_name == "action_two_pressed" or action_name == "action_two_hold" then
                return false
            end
        end
    end

    return out
end

mod:hook("InputService", "_get", _input_hook)
mod:hook("InputService", "_get_simulate", _input_hook)
