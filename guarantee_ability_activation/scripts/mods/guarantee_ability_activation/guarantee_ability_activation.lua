-- Guarantee Ability Activation by KamiUnitY. Ver. 1.3.10

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
    adamant_charge                       = true,
}

local IS_WEAPON_ABILITY = {
    zealot_relic               = true,
    psyker_force_field         = true,
    psyker_force_field_dome    = true,
    adamant_area_buff_drone    = true,
    broker_ability_stimm_field = true,
}

local INTERVAL_DO_PROMISE = 0.05

---------------
-- VARIABLES --
---------------

mod.promise_ability = false

mod.last_do_promise = 0

local is_in_hub = false

local character_state = ""

local current_slot = ""

local combat_ability = ""
local grenade_ability = ""

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

local check_is_in_hub = function()
    local game_mode_manager = Managers.state.game_mode
    local game_mode_name = game_mode_manager and game_mode_manager:game_mode_name()
    return game_mode_name == "hub"
end

local time_now = function ()
    return Managers.time and Managers.time:time("main")
end

local elapsed = function(time)
    return time_now() - time
end

local is_available_ability_charges = function()
    local unit = Managers.player:local_player(1).player_unit
    if unit then
        if ScriptUnit.extension(unit, "ability_system"):remaining_ability_charges("combat_ability") > 0 then
            return true
        end
    end
    return false
end

--------------------------
-- MOD SETTINGS CACHING --
--------------------------

mod.settings = {
    enable_prevent_relic_cancel   = mod:get("enable_prevent_relic_cancel"),
    enable_prevent_ability_aiming = mod:get("enable_prevent_ability_aiming"),
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
    is_in_hub = check_is_in_hub()

    -- WATCHER
    -- modding_tools:watch("promise_ability",mod,"promise_ability")
    -- modding_tools:watch("character_state",mod,"character_state")
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

local function setPromise(from)
    if not is_available_ability_charges() then
        return
    end
    if not mod.promise_ability then
        if ALLOWED_CHARACTER_STATE[character_state] then
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

local function isPromised()
    local promise = mod.promise_ability

    if promise then
        if elapsed(mod.last_do_promise) < INTERVAL_DO_PROMISE then
            return false
        end
        if not is_available_ability_charges() then
            clearPromise("empty_ability_charges")
            return false
        end
        if IS_DASH_ABILITY[combat_ability] then
            if not ALLOWED_DASH_STATE[character_state] then
                return false
            end
        end
        mod.last_do_promise = time_now()
        if modding_tools then debug:print_mod("Attempting to activate combat ability for you !!!") end
    end

    return promise
end

----------------
-- ON TRIGGER --
----------------

-- CLEAR PROMISE ON ENTER OR EXIT GAMEPLAY

mod:hook_safe("GameplayStateRun", "on_enter", function(...)
    clearPromise("ENTER_GAMEPLAY")
end)

mod:hook_safe("GameplayStateRun", "on_exit", function(...)
    clearPromise("EXIT_GAMEPLAY")
end)

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
                if action_settings.start_input then
                    if reason == AIM_CANCEL_WITH_SPRINT then
                        setPromise("AIM_CANCEL_WITH_SPRINT")
                        return
                    end
                    if elapsed(last_set_promise) <= PREVENT_CANCEL_DURATION then
                        setPromise("AIM_CANCEL_NORMAL")
                        return
                    end
                end
                if modding_tools then debug:print_mod("Player pressed AIM_CANCEL by " .. reason) end
            end
        end
    end
end)

-- SET PROMISE ON ABILITY FAILING TO CHANGE CHARACTER STATE

mod:hook("ActionCharacterStateChange", "finish", function(func, self, reason, data, t, time_in_action)
    if self._player.viewport_name == "player1" then
        local action_settings = self._action_settings
        if action_settings and action_settings.ability_type == "combat_ability" then
            local current_state = self._character_sate_component.state_name
            local wanted_state = self._wanted_state_name
            local is_in_wanted_state = current_state == wanted_state

            local use_ability_charge = action_settings.use_ability_charge
            local ability_interrupted_reasons = action_settings.ability_interrupted_reasons
            local should_use_charge = (not ability_interrupted_reasons or not ability_interrupted_reasons[reason]) and is_in_wanted_state

            if not (use_ability_charge and should_use_charge) then
                setPromise("state_change_failed")
            end
        end
    end
    func(self, reason, data, t, time_in_action)
end)

-- UPDATE CHARACTER STATE VARIABLE AND CLEAR PROMISE ON UNALLOWED CHARACTER STATE

local function _on_character_state_change(self)
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

-- UPDATE WEAPON TEMPLATE VARIABLE & CLEAR PROMISE ON WIELDING ABILITY

local function _on_slot_wielded(self)
    local inventory_component = self._inventory_component
    local wielded_slot = inventory_component.wielded_slot

    if wielded_slot ~= current_slot then
        current_slot = wielded_slot
        if current_slot == "slot_combat_ability" then
            clearPromise("on " .. current_slot)
        end
    end
end

mod:hook_safe("PlayerUnitWeaponExtension", "fixed_update", function(self, unit, dt, t, fixed_frame)
    if current_slot ~= "" then
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

-- UPDATE CHARACTER ABILITY VARIABLE

local _on_ability_equip = function (self)
    local _equipped_abilities = self._equipped_abilities
    if _equipped_abilities then
        combat_ability = _equipped_abilities.combat_ability and _equipped_abilities.combat_ability.name
        grenade_ability = _equipped_abilities.grenade_ability and _equipped_abilities.grenade_ability.name
    end
end

mod:hook_safe("PlayerUnitAbilityExtension", "fixed_update", function(self, unit, dt, t, fixed_frame)
    if combat_ability ~= "" and grenade_ability ~= "" then
        mod:hook_disable("PlayerUnitAbilityExtension", "fixed_update")
    end
    if self._player.viewport_name == "player1" then
        _on_ability_equip(self)
    end
end)

mod:hook_safe("PlayerUnitAbilityExtension", "_equip_ability", function(self, ability_type, ability, fixed_t, from_server_correction)
    if self._player.viewport_name == "player1" then
        _on_ability_equip(self)
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

    if action_name == "combat_ability_pressed" then
        if pressed then
            if mod.settings["enable_prevent_relic_cancel"] and combat_ability == "zealot_relic" and current_slot == "slot_combat_ability" then
                return false
            end
            if IS_DASH_ABILITY[combat_ability] and character_state == "lunging" then
                return false
            end
            setPromise("pressed")
            if modding_tools then debug:print_mod("Player pressed " .. action_name) end
        end
        return out or isPromised()
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

    -- Release Mouse on using Weapon Ability
    if mod.promise_ability and IS_WEAPON_ABILITY[combat_ability] then
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
