-- Guarantee Ability Activation mod by KamiUnitY. Ver. 1.0.0

local mod = get_mod("guarantee_ability_activation")
local modding_tools = get_mod("modding_tools")

mod.debug = {
    is_enabled = function()
        return modding_tools and modding_tools:is_enabled() and mod:get("enable_debug_modding_tools")
    end,
    print = function(text)
        modding_tools:console_print(text)
    end
}

mod.promise_ability = false

local function isPromised()
    return mod.promise_ability
end

local function setPromise()
    mod.promise_ability = true
end

local function clearPromises()
    mod.promise_ability = false
end

local function getCombatAbilityNumCharges()
    local unit = Managers.player:local_player(1).player_unit
    if unit then
        local unit_data = ScriptUnit.extension(unit, "unit_data_system")
        local num_charges = unit_data._components.combat_ability[1].num_charges
        if num_charges ~= nil then
            return num_charges
        end
    end
    return 0
end

local _input_hook = function(func, self, action_name)
    local out = func(self, action_name)
    local type_str = type(out)

    if (type_str == "boolean" and out == true) or (type_str == "number" and out == 1) then
        if action_name == "combat_ability_pressed" or action_name == "combat_ability_hold" or action_name == "combat_ability_release" then
            if mod.debug.is_enabled() then
                mod.debug.print("Guarantee Ability Activation: player pressed " .. action_name)
            end
        end
        if action_name == "combat_ability_pressed" and mod._current_slot ~= "slot_unarmed" and getCombatAbilityNumCharges() > 0 then
            setPromise()
        end

        if action_name == "combat_ability_hold" and not mod:get("enable_combat_ability_hold") then
            return false
        end
    end

    if action_name == "combat_ability_pressed" then
        return out or isPromised()
    end

    return out
end

mod:hook("InputService", "_get", _input_hook)
mod:hook("InputService", "_get_simulate", _input_hook)

local _action_aim_force_field_hook = function(self, dt, t)
    clearPromises()
    if mod.debug.is_enabled() then
        mod.debug.print("Guarantee Ability Activation: " .. "ActionAimForceField:Start")
        mod.debug.print("________________________________")
    end
end

local _action_ability_base_hook = function(self, action_settings, t, time_scale, action_start_params)
    if action_settings.ability_type == "combat_ability" then
        clearPromises()
        if mod.debug.is_enabled() then
            mod.debug.print("Guarantee Ability Activation: " .. "ActionAbilityBase:Start")
            mod.debug.print(action_settings)
            mod.debug.print("________________________________")
        end
    end
end

mod:hook_require("scripts/extension_systems/weapon/actions/action_aim_force_field", function(ActionAimForceField)
    ActionAimForceField.start = _action_aim_force_field_hook
end)

mod:hook_require("scripts/extension_systems/weapon/actions/action_base", function(ActionAbilityBase)
    ActionAbilityBase.start = _action_ability_base_hook
end)

mod._current_slot = ""
mod:hook_safe("PlayerUnitWeaponExtension", "on_slot_wielded", function(self, slot_name, t, skip_wield_action)
    mod._current_slot = slot_name
end)