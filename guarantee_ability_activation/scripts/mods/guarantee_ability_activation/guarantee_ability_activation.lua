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
    return nil
end

local _input_hook = function(func, self, action_name)
    local out = func(self, action_name)
    local type_str = type(out)

    if (type_str == "boolean" and out == true) or (type_str == "number" and out == 1) then
        if action_name == "combat_ability_pressed" or action_name == "combat_ability_hold" or action_name == "combat_ability_release" then
            mod.debug.print(action_name)
        end

        local num_charges = getCombatAbilityNumCharges()
        if action_name == "combat_ability_pressed" and num_charges ~= nil and num_charges > 0 then
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

mod:hook_require("scripts/extension_systems/weapon/actions/action_aim_force_field", function(ActionAimForceField)
    mod:hook_safe(ActionAimForceField, "start", function(self, dt, t)
        clearPromises()
        mod.debug.print("ActionAimForceField: Start")
        mod.debug.print("________________________________")
    end)
end)

mod:hook_require("scripts/extension_systems/weapon/actions/action_base", function(ActionAbilityBase)
    mod:hook_safe(ActionAbilityBase, "start", function(self, action_settings, t, time_scale, action_start_params)
        if action_settings.ability_type == "combat_ability" then
            clearPromises()
            mod.debug.print("ActionAbilityBase: Start")
            mod.debug.print(action_settings)
            mod.debug.print("________________________________")
        end
    end)
end)
