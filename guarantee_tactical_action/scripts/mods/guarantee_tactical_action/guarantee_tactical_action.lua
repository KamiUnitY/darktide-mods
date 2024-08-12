-- Guarantee Tactical Action by KamiUnitY. Ver. 0.0.1

local mod = get_mod("guarantee_tactical_action")
local modding_tools = get_mod("modding_tools")

---------------
-- CONSTANTS --
---------------

local PROMISE_ACTION_MAP = {
    action_one_pressed   = "action_one",
    action_two_pressed   = "action_two",
    weapon_extra_pressed = "action_special",
    weapon_reload        = "action_reload",
}

local CLEAR_PROMISE_ACTION = {
    action_one_pressed    = true,
    action_one_hold       = true,
    action_one_released   = true,
    action_two_pressed    = true,
    action_two_hold       = true,
    action_two_released   = true,
    weapon_extra_pressed  = true,
    weapon_extra_hold     = true,
    weapon_extra_released = true,
    weapon_reload         = true,
}

local PROMISE_GROUPS = {
    action_one     = {"action_one_pressed", "action_one_hold", "action_one_released"},
    action_two     = {"action_two_pressed", "action_two_hold", "action_two_released"},
    action_special = {"weapon_extra_pressed", "weapon_extra_hold", "weapon_extra_released"},
    action_reload  = {"weapon_reload"},
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

mod.doing_special = false
mod.doing_reload = false
mod.doing_melee_start = false
mod.doing_push = false

mod.promises = {
    action_one     = false,
    action_two     = false,
    action_special = false,
    action_reload  = false,
}

local allowed_set_promise = {
    action_special = true,
    action_reload  = true,
    action_one     = false,
    action_two     = false,
}

local current_slot = ""
local weapon_template = ""

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

local function setPromise(from, action)
    if not mod.promises[action] and allowed_set_promise[action] then
        if mod.doing_reload and action == "action_reload" then
            return
        elseif mod.doing_special and action == "action_special" then
            return
        end
        mod.promises[action] = true
        mod.promise_exist = true
        if modding_tools then debug:print_mod("Set " .. action .. " promise from " .. from) end
    end
end

local function clearPromise(from, action)
    if mod.promises[action] then
        mod.promises[action] = false
        mod.promise_exist = false -- Every setPromise() got clearAllPromises() first, So this is fine
        if modding_tools then debug:print_mod("Clear " .. action .. " promise from " .. from) end
    end
end

local function clearGroupPromises(from, used_input)
    for group, actions in pairs(PROMISE_GROUPS) do
        for _, action in ipairs(actions) do
            if action == used_input then
                clearPromise(from, group)
                break
            end
        end
    end
end

local function clearAllPromises(from)
    if mod.promise_exist then
        for key in pairs(mod.promises) do
            mod.promises[key] = false
            if modding_tools then debug:print_mod("Clear all promise from " .. from) end
        end
        mod.promise_exist = false
    end
end

local function isPromised(action, promise)
    if mod.doing_melee_start or mod.doing_push then
       return false
    end
    local unit = Managers.player:local_player(1).player_unit
    if unit then
        local weapon_system = ScriptUnit.extension(unit, "weapon_system")
        if weapon_system then
            local base_clip = weapon_system._base_clip_by_slot[current_slot]
            if base_clip.current_ammunition_clip == base_clip.max_ammunition_clip then
                clearPromise("full_ammo", "action_reload")
            end
        end
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
        allowed_set_promise.action_special = false
        for action_name in pairs(weapon_template.actions) do
            if string.find(action_name, "special") then
                allowed_set_promise.action_special = true
                break
            end
        end
        allowed_set_promise.action_reload = false
        if weapon_template.actions["action_reload"] then
            allowed_set_promise.action_reload = true
        end
    end
end


mod:hook_safe("PlayerUnitWeaponExtension", "_wielded_weapon", function(self, inventory_component, weapons)
    if current_slot ~= "" and weapon_template ~= "" then
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
        if action_name:find("action_melee_start") then
            mod.doing_melee_start = true
        elseif action_name == "action_push" then
            mod.doing_push = true
        elseif action_name:find("special") then
            mod.doing_special = true
        elseif action_name == "action_reload" then
            mod.doing_reload = true
        end
        if CLEAR_PROMISE_ACTION[used_input] then
            clearGroupPromises("start_action", used_input)
        end
        if modding_tools then debug:print_mod("START "..action_name) end
    end
end)

mod:hook_safe("ActionHandler", "_finish_action", function(self, handler_data, reason, data, t, next_action_params)
    if self._unit_data_extension._player.viewport_name == 'player1' then
        local component = handler_data.component
        local previous_action = component.previous_action_name or ""
        local current_action = component.current_action_name or ""

        if previous_action:find("action_melee_start") then
            mod.doing_melee_start = false
        elseif previous_action == "action_push" then
            mod.doing_push = false
        elseif previous_action:find("special") then
            mod.doing_special = false
            clearPromise("finish_action", "action_special")
        elseif previous_action == "action_reload" then
            mod.doing_reload = false
            clearPromise("finish_action", "action_reload")
        end
        if modding_tools then debug:print_mod("END "..previous_action) end
    end
end)

-- UPDATE CHARACTER STATE VARIABLE AND CLEAR PROMISE ON UNALLOWED CHARACTER STATE

local _update_character_state = function (self)
    mod.character_state = self._state_current.name
    if not ALLOWED_CHARACTER_STATE[mod.character_state] then
        clearAllPromises("UNALLOWED CHARACTER STATE")
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

mod:hook_safe("ActionReloadState", "start", function(self, action_settings, t, time_scale, ...)
    if self._player.viewport_name == 'player1' then
        clearPromise("action_reload")
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
            clearPromise("Input pressed", promise_action)
            if ALLOWED_CHARACTER_STATE[mod.character_state] then
                setPromise("Input pressed", promise_action)
            end
        end
        local promise = mod.promises[promise_action]
        return out or (promise and isPromised(promise_action, promise))
    end

    if mod.promise_exist  then
        if not mod.doing_push then
            if action_name == "action_one_pressed" or action_name == "action_one_hold" then
                return false
            elseif action_name == "action_one_released" then
                return true
            end
        end
        if action_name == "sprinting" then
            return false
        end
    end

    return out
end

mod:hook("InputService", "_get", _input_hook)
mod:hook("InputService", "_get_simulate", _input_hook)
