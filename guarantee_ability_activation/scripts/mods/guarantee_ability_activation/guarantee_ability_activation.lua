-- Guarantee Ability Activation mod by KamiUnitY. Ver. 1.2.0

local mod = get_mod("guarantee_ability_activation")
local modding_tools = get_mod("modding_tools")

mod.settings = {
    enable_prevent_cancel_on_short_ability_press = true, -- mod:get("enable_prevent_cancel_on_short_ability_press")
    enable_prevent_cancel_on_start_sprinting     = true, -- mod:get("enable_prevent_cancel_on_start_sprinting")
    enable_prevent_double_dashing                = mod:get("enable_prevent_double_dashing"),
    enable_prevent_ability_aiming                = mod:get("enable_prevent_ability_aiming"),
    enable_debug_modding_tools                   = mod:get("enable_debug_modding_tools"),
}

mod.on_setting_changed = function(setting_id)
    mod.settings[setting_id] = mod:get(setting_id)
end

mod.on_all_mods_loaded = function()
    -- modding_tools:watch("promise_ability",mod,"promise_ability")
    -- modding_tools:watch("character_state",mod,"character_state")
end

local debug = {
    is_enabled = function(self)
        return mod.settings["enable_debug_modding_tools"] and modding_tools and modding_tools:is_enabled()
    end,
    print = function(self, text)
        pcall(function() modding_tools:console_print(text) end)
    end,
    print_if_enabled = function(self, text)
        if self:is_enabled() then
            self:print(text)
        end
    end,
}

local function contains(str, substr)
    if type(str) ~= "string" or type(substr) ~= "string" then
        return false
    end
    return string.find(str, substr) ~= nil
end

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

local DELAY_DASH = 0.3

mod.promise_ability = false

mod.character_state = nil

local current_slot = ""

local remaining_ability_charges = 0

local combat_ability = nil
local weapon_template = nil

local last_set_promise = os.clock()

local elapsed = function(time)
    return os.clock() - time
end

local function setPromise(from)
    if not mod.promise_ability then
        -- slot_unarmed means player is netted or pounced
        if ALLOWED_CHARACTER_STATE[mod.character_state] and current_slot ~= "slot_unarmed"
            and remaining_ability_charges > 0
            and (mod.character_state ~= "lunging" or not mod.settings["enable_prevent_double_dashing"])
            then
            mod.promise_ability = true
            last_set_promise = os.clock()
            if modding_tools then debug:print_if_enabled("Guarantee Ability Activation: setPromiseFrom: " .. from) end
        end
    end
end

local function clearPromise(from)
    if mod.promise_ability then
        mod.promise_ability = false
        if modding_tools then debug:print_if_enabled("Guarantee Ability Activation: clearPromiseFrom: " .. from) end
    end
end

local function isPromised()
    local result
    if IS_DASH_ABILITY[combat_ability] then
        result = mod.promise_ability and ALLOWED_DASH_STATE[mod.character_state]
            and elapsed(last_set_promise) > DELAY_DASH -- preventing pressing too early which sometimes could result in double dashing (hacky solution, need can_use_ability function so I can replace this)
    else
        result = mod.promise_ability
    end
    if result then
        if modding_tools then debug:print_if_enabled("Guarantee Ability Activation: Attempting to activate combat ability for you") end
    end
    return result
end

mod:hook_safe("CharacterStateMachine", "fixed_update", function(self, unit, dt, t, frame, ...)
    if self._unit_data_extension._player.viewport_name == 'player1' then
        mod.character_state = self._state_current.name
        if not ALLOWED_CHARACTER_STATE[mod.character_state] then
            clearPromise("UNALLOWED_CHARACTER_STATE")
        end
    end
end)

mod:hook_safe("PlayerUnitAbilityExtension", "equipped_abilities", function(self)
    if self._equipped_abilities.combat_ability ~= nil then
        combat_ability = self._equipped_abilities.combat_ability.name
    end
end)

mod:hook("PlayerUnitAbilityExtension", "remaining_ability_charges", function(func, self, ability_type)
    local out = func(self, ability_type)
    remaining_ability_charges = out
    if ability_type == "combat_ability" and remaining_ability_charges == 0 then
        clearPromise("empty_ability_charges")
    end
    return out
end)

local function isWieldBugCombo()
    return contains(weapon_template, "combatsword_p2") and contains(combat_ability, "zealot_relic")
end

local _input_hook = function(func, self, action_name)
    local out = func(self, action_name)
    local type_str = type(out)
    local pressed = (type_str == "boolean" and out == true) or (type_str == "number" and out == 1)

    if action_name == "combat_ability_pressed" then
        if pressed then
            setPromise("pressed")
            if modding_tools then debug:print_if_enabled("Guarantee Ability Activation: Player pressed " .. action_name) end
        end
        if IS_DASH_ABILITY[combat_ability] and mod.character_state == "lunging" and mod.settings["enable_prevent_double_dashing"] then
            return false
        end
        return out or isPromised()
    end

    if action_name == "combat_ability_release" then
        if pressed then
            if modding_tools then debug:print_if_enabled("Guarantee Ability Activation: Player pressed " .. action_name) end
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

    if action_name == "action_two_pressed" or action_name == "action_two_hold" then
        if mod.promise_ability and isWieldBugCombo() then
            return true
        end
        return out
    end

    return out
end

mod:hook("InputService", "_get", _input_hook)
mod:hook("InputService", "_get_simulate", _input_hook)

mod:hook_safe("PlayerUnitAbilityExtension", "use_ability_charge", function(self, ability_type, optional_num_charges)
    if ability_type == "combat_ability" then
        clearPromise("use_ability_charge")
        if modding_tools then debug:print_if_enabled("Guarantee Ability Activation: Game has successfully initiated the execution of use_ability_charge") end
    end
end)

mod:hook_safe("PlayerUnitWeaponExtension", "_wielded_weapon", function(self, inventory_component, weapons)
    local wielded_slot = inventory_component.wielded_slot
    if wielded_slot ~= nil and wielded_slot ~= current_slot then
        current_slot = wielded_slot
        if current_slot == "slot_unarmed" then
            clearPromise("on_slot_unarmed")
        end
        if current_slot == "slot_combat_ability" then
            clearPromise("on_slot_wielded")
        end
        if weapons[wielded_slot] ~= nil and weapons[wielded_slot].weapon_template ~= nil then
            weapon_template = weapons[wielded_slot].weapon_template.name
        end
    end
end)

local AIM_CANCEL_NORMAL      = "hold_input_released"
local AIM_CANCEL_WITH_SPRINT = "started_sprint"
local AIM_RELASE             = "new_interrupting_action"

local IS_AIM_CANCEL = {
    [AIM_CANCEL_NORMAL]      = true,
    [AIM_CANCEL_WITH_SPRINT] = true
}

local IS_AIM_DASH = {
    targeted_dash_aim    = true,
    directional_dash_aim = true,
}

local PREVENT_CANCEL_DURATION = 0.3

local _action_ability_base_start_hook = function(self, action_settings, t, time_scale, action_start_params)
    if action_settings.ability_type == "combat_ability" then
        clearPromise("ability_base_start")
        if modding_tools then debug:print_if_enabled("Guarantee Ability Activation: Game has successfully initiated the execution of ActionAbilityBase:Start") end
    end
end

local _action_ability_base_finish_hook = function(self, reason, data, t, time_in_action)
    local action_settings = self._action_settings
    if action_settings and action_settings.ability_type == "combat_ability" then
        if IS_AIM_CANCEL[reason] then
            if current_slot ~= "slot_unarmed" then
                if reason == AIM_CANCEL_WITH_SPRINT and mod.settings["enable_prevent_cancel_on_start_sprinting"] then
                    return setPromise("AIM_CANCEL_WITH_SPRINT")
                end
                if mod.settings["enable_prevent_cancel_on_short_ability_press"] and elapsed(last_set_promise) <= PREVENT_CANCEL_DURATION then
                    return setPromise("AIM_CANCEL_NORMAL")
                end
            end
            if modding_tools then debug:print_if_enabled("Guarantee Ability Activation: Player pressed AIM_CANCEL by " .. reason) end
        else
            if IS_AIM_DASH[action_settings.kind] then
                return setPromise("promise_dash")
            end
        end
    end
end

mod:hook_require("scripts/extension_systems/weapon/actions/action_base", function(instance)
    instance.start = _action_ability_base_start_hook
    instance.finish = _action_ability_base_finish_hook
end)
