-- Guarantee Ability Activation by KamiUnitY. Ver. 1.2.1

local mod = get_mod("guarantee_ability_activation")
local modding_tools = get_mod("modding_tools")

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

-------------------------
-- MODDING TOOLS DEBUG --
-------------------------

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

local DELAY_ABILITY = 0.3

---------------
-- VARIABLES --
---------------

mod.promise_ability = false

mod.character_state = ""

local current_slot = ""

local remaining_ability_charges = 0

local combat_ability = ""
local weapon_template = ""

local last_set_promise = 0

---------------
-- UTILITIES --
---------------

local time_now = function ()
    return Managers.time and Managers.time:time("main")
end

local elapsed = function(time)
    return time_now() - time
end

-----------------------
-- PROMISE FUNCTIONS --
-----------------------

local function setPromise(from)
    if not mod.promise_ability then
        -- slot_unarmed means player is netted or pounced
        if ALLOWED_CHARACTER_STATE[mod.character_state] and current_slot ~= "slot_unarmed"
            and remaining_ability_charges > 0
            and (mod.character_state ~= "lunging" or not mod.settings["enable_prevent_double_dashing"])
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

local function isPromised()
    local result
    if IS_DASH_ABILITY[combat_ability] then
        result = mod.promise_ability and ALLOWED_DASH_STATE[mod.character_state]
            and elapsed(last_set_promise) > DELAY_ABILITY -- hacky solution for double dashing bug when pressed only once, need can_use_ability function so I can replace this
    else
        result = mod.promise_ability
    end
    if result then
        if modding_tools then debug:print_mod("Attempting to activate combat ability for you") end
    end
    return result
end

----------------
-- ON TRIGGER --
----------------

-- CLEAR PROMISE ON ABILITY USED

mod:hook_safe("PlayerUnitAbilityExtension", "use_ability_charge", function(self, ability_type, optional_num_charges)
    if ability_type == "combat_ability" then
        clearPromise("use_ability_charge")
        if modding_tools then debug:print_mod("Game has successfully initiated the execution of use_ability_charge") end
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
    if action_settings.ability_type == "combat_ability" then
        clearPromise("ability_base_start")
        if modding_tools then debug:print_mod("Game has successfully initiated the execution of ActionAbilityBase:Start") end
    end
end)

-- HANDLE PROMISE ON FINISH HOLDING ABILITY

mod:hook_safe("ActionBase", "finish", function(self, reason, data, t, time_in_action)
    local action_settings = self._action_settings
    if action_settings and action_settings.ability_type == "combat_ability" then
        if IS_AIM_CANCEL[reason] then
            if current_slot ~= "slot_unarmed" then
                if reason == AIM_CANCEL_WITH_SPRINT and mod.settings["enable_prevent_cancel_on_start_sprinting"] then
                    setPromise("AIM_CANCEL_WITH_SPRINT")
                    return
                end
                if mod.settings["enable_prevent_cancel_on_short_ability_press"] and elapsed(last_set_promise) <= PREVENT_CANCEL_DURATION then
                    setPromise("AIM_CANCEL_NORMAL")
                    return
                end
            end
            if modding_tools then debug:print_mod("Player pressed AIM_CANCEL by " .. reason) end
        else
            if IS_AIM_DASH[action_settings.kind] then
                setPromise("promise_dash")
                return
            end
        end
    end
end)

--------------------
-- ON EVERY FRAME --
--------------------

-- REALTIME REMAINING ABILITY CHARGE VARIABLE & CLEAR PROMISE ON EMPTY CHARGE

mod:hook("PlayerUnitAbilityExtension", "remaining_ability_charges", function(func, self, ability_type)
    local out = func(self, ability_type)
    if ability_type == "combat_ability" then
        remaining_ability_charges = out
        if mod.promise_ability and remaining_ability_charges == 0 then
            clearPromise("empty_ability_charges")
        end
    end
    return out
end)

-- REALTIME WEAPON TEMPLATE VARIABLE & CLEAR PROMISE ON UNARMED AND WIELD ABILITY

mod:hook_safe("PlayerUnitWeaponExtension", "_wielded_weapon", function(self, inventory_component, weapons)
    local wielded_slot = inventory_component.wielded_slot
    if wielded_slot ~= nil and wielded_slot ~= current_slot then
        current_slot = wielded_slot
        if weapons[wielded_slot] ~= nil and weapons[wielded_slot].weapon_template ~= nil then
            weapon_template = weapons[wielded_slot].weapon_template.name
        end
        if wielded_slot == "slot_combat_ability" or wielded_slot == "slot_unarmed" then
            clearPromise("on " .. wielded_slot)
            return
        end
    end
end)

-- REALTIME COMBAT ABILITY VARIABLE

mod:hook_safe("PlayerUnitAbilityExtension", "equipped_abilities", function(self)
    if self._equipped_abilities.combat_ability ~= nil then
        combat_ability = self._equipped_abilities.combat_ability.name
    end
end)

-- REALTIME CHARACTER STATE VARIABLE AND CLEAR PROMISE ON UNALLOWED CHARACTER STATE

mod:hook_safe("CharacterStateMachine", "fixed_update", function(self, unit, dt, t, frame, ...)
    if self._unit_data_extension._player.viewport_name == 'player1' then
        mod.character_state = self._state_current.name
        if mod.promise_ability and not ALLOWED_CHARACTER_STATE[mod.character_state] then
            clearPromise("UNALLOWED_CHARACTER_STATE")
        end
    end
end)

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
        if IS_DASH_ABILITY[combat_ability] and mod.character_state == "lunging" and mod.settings["enable_prevent_double_dashing"] then
            return false
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

    if action_name == "sprinting" then
        if pressed and mod.character_state == "lunging" then
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
