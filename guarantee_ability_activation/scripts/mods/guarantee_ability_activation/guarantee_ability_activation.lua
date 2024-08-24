-- Guarantee Ability Activation by KamiUnitY. Ver. 1.3.0

local mod = get_mod("guarantee_ability_activation")
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
}

local ALLOWED_DASH_STATE = {
    sprinting = true,
    walking   = true,
}

local IS_DASH_ABILITY = {
    zealot_targeted_dash                 = true,
    zealot_targeted_dash_improved        = true,
    zealot_targeted_dash_improved_double = true,
    ogryn_charge                         = true,
    ogryn_charge_increased_distance      = true,
}

local DELAY_ABILITY = 0.2

---------------
-- VARIABLES --
---------------

mod.promise_ability = false

local character_state = ""

local current_slot = ""

local combat_ability = ""
local weapon_template = ""

local last_set_promise = 0

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

local time_now = function ()
    return Managers.time and Managers.time:time("main")
end

local elapsed = function(time)
    return time_now() - time
end

--------------------------
-- MOD SETTINGS CACHING --
--------------------------

mod.settings = {
    enable_prevent_cancel_on_short_ability_press = true,
    enable_prevent_cancel_on_start_sprinting     = true,
    enable_prevent_double_dashing                = mod:get("enable_prevent_double_dashing"),
    enable_prevent_ability_aiming                = mod:get("enable_prevent_ability_aiming"),
    enable_debug_modding_tools                   = mod:get("enable_debug_modding_tools"),
}

mod.on_setting_changed = function(setting_id)
    mod.settings[setting_id] = mod:get(setting_id)
end

------------------------
-- ON ALL MODS LOADED --
------------------------

mod.on_all_mods_loaded = function()
    -- WATCHER
    -- modding_tools:watch("promise_ability",mod,"promise_ability")
    -- modding_tools:watch("character_state",mod,"character_state")
end

-----------------------
-- PROMISE FUNCTIONS --
-----------------------

local function setPromise(from)
    local unit = Managers.player:local_player(1).player_unit
    if unit then
        if ScriptUnit.extension(unit, "ability_system"):remaining_ability_charges("combat_ability") == 0 then
            return
        end
    end
    if not mod.promise_ability then
        if ALLOWED_CHARACTER_STATE[character_state]
            and (character_state ~= "lunging" or not mod.settings["enable_prevent_double_dashing"])
        then
            mod.promise_ability = true
            last_set_promise = time_now()
            if modding_tools then debug:print_mod("setPromiseFrom: " .. from) end
        end
    end
end

local function clearPromise(from)
    if mod.promise_ability then
        mod.promise_ability = false
        if modding_tools then debug:print_mod("clearPromiseFrom: " .. from) end
    end
end

local function isPromised(promise)
    if not promise then
        return false
    end
    if IS_DASH_ABILITY[combat_ability] then
        -- DELAY_ABILITY is a hacky solution for double dashing bug when pressed only once, need can_use_ability function so I can replace this
        if not (ALLOWED_DASH_STATE[character_state] and elapsed(last_set_promise) > DELAY_ABILITY) then
            return false
        end
    end
    if modding_tools then debug:print_mod("Attempting to activate combat ability for you !!!") end
    return true
end

----------------
-- ON TRIGGER --
----------------

-- CLEAR PROMISE ON ABILITY USED

mod:hook_safe("PlayerUnitAbilityExtension", "use_ability_charge", function(self, ability_type, optional_num_charges)
    if self._player.viewport_name == "player1" then
        if ability_type == "combat_ability" then
            clearPromise("use_ability_charge")
            if modding_tools then debug:print_mod("Game has successfully initiated the execution of use_ability_charge") end
        end
    end
end)

-- CONSTATNS FOR HANDLE PROMISE ON HOLDING ABILITY

local AIM_CANCEL_NORMAL      = "hold_input_released"
local AIM_CANCEL_WITH_SPRINT = "started_sprint"
local AIM_RELASE             = "new_interrupting_action"

local IS_AIM_CANCEL = {
    [AIM_CANCEL_NORMAL]      = true,
    [AIM_CANCEL_WITH_SPRINT] = true,
}

local IS_AIM_DASH = {
    targeted_dash_aim    = true,
    directional_dash_aim = true,
}

local PREVENT_CANCEL_DURATION = 0.3

-- HANDLE PROMISE ON START HOLDING ABILITY

mod:hook_safe("ActionBase", "start", function(self, action_settings, t, time_scale, action_start_params)
    if self._player.viewport_name == "player1" then
        if action_settings.ability_type == "combat_ability" then
            clearPromise("ability_base_start")
            if modding_tools then debug:print_mod("Game has successfully initiated the execution of ActionAbilityBase:Start") end
        end
    end
end)

-- HANDLE PROMISE ON FINISH HOLDING ABILITY

mod:hook_safe("ActionBase", "finish", function(self, reason, data, t, time_in_action)
    if self._player.viewport_name == "player1" then
        local action_settings = self._action_settings
        if action_settings and action_settings.ability_type == "combat_ability" then
            if IS_AIM_CANCEL[reason] then
                if reason == AIM_CANCEL_WITH_SPRINT and mod.settings["enable_prevent_cancel_on_start_sprinting"] then
                    setPromise("AIM_CANCEL_WITH_SPRINT")
                    return
                end
                if mod.settings["enable_prevent_cancel_on_short_ability_press"] and elapsed(last_set_promise) <= PREVENT_CANCEL_DURATION then
                    setPromise("AIM_CANCEL_NORMAL")
                    return
                end
                if modding_tools then debug:print_mod("Player pressed AIM_CANCEL by " .. reason) end
            else
                if IS_AIM_DASH[action_settings.kind] then
                    setPromise("promise_dash")
                    return
                end
            end
        end
    end
end)

-- UPDATE CHARACTER STATE VARIABLE AND CLEAR PROMISE ON UNALLOWED CHARACTER STATE

local function _update_character_state(self)
    character_state = self._state_current.name
    if not ALLOWED_CHARACTER_STATE[character_state] then
        clearPromise("UNALLOWED_CHARACTER_STATE")
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

-- UPDATE WEAPON TEMPLATE VARIABLE & CLEAR PROMISE ON WIELDING ABILITY

local function _on_slot_wielded(self, slot_name)
    current_slot = slot_name
    local slot_weapon = self._weapons[slot_name]
    if slot_weapon ~= nil and slot_weapon.weapon_template ~= nil then
        weapon_template = slot_weapon.weapon_template.name
    end
    if slot_name == "slot_combat_ability" then
        clearPromise("on " .. slot_name)
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
        _on_slot_wielded(self, slot_name)
    end
end)


-- UPDATE COMBAT ABILITY VARIABLE

mod:hook_safe("PlayerUnitAbilityExtension", "update", function(self, unit, dt, t, fixed_frame)
    if combat_ability ~= "" then
        mod:hook_disable("PlayerUnitAbilityExtension", "update")
    end
    if self._player.viewport_name == "player1" then
        local _combat_ability = self._equipped_abilities.combat_ability
        if _combat_ability ~= nil then
            combat_ability = _combat_ability.name
        end
    end
end)

mod:hook_safe("PlayerUnitAbilityExtension", "equip_ability", function(self, ability_type, ability, fixed_t)
    if self._player.viewport_name == "player1" then
        if ability_type == "combat_ability" then
            combat_ability = ability.name
        end
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

    if action_name == "combat_ability_pressed" then
        if pressed then
            setPromise("pressed")
            if modding_tools then debug:print_mod("Player pressed " .. action_name) end
        end
        if IS_DASH_ABILITY[combat_ability] and character_state == "lunging" and mod.settings["enable_prevent_double_dashing"] then
            return false
        end
        local promise = mod.promise_ability
        return out or (promise and isPromised(promise))
    end

    if action_name == "combat_ability_release" then
        if pressed then
            if modding_tools then debug:print_mod("Player pressed " .. action_name) end
        end
        return out
    end

    if action_name == "combat_ability_hold" then
        if pressed and mod.settings["enable_prevent_ability_aiming"] then
            return false
        end
        return out
    end

    if action_name == "sprinting" then
        -- Vanilla workaround bugfix for 2nd dash ability not seemlessly continues
        if character_state == "lunging" then
            return false
        end
        return out
    end

    -- Fixing Heavy Sword + Relic Bug
    if action_name == "action_two_pressed" or action_name == "action_two_hold" then
        if mod.promise_ability and string.find(weapon_template, "combatsword_p2") and string.find(combat_ability, "zealot_relic") then
            return true
        end
        return out
    end

    return out
end

mod:hook("InputService", "_get", _input_hook)
mod:hook("InputService", "_get_simulate", _input_hook)
