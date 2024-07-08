-- Guarantee Ability Activation mod by KamiUnitY. Ver. 1.0.3

local mod = get_mod("guarantee_ability_activation")
local modding_tools = get_mod("modding_tools")

mod.debug = {
    is_enabled = function()
        return modding_tools and modding_tools:is_enabled() and mod:get("enable_debug_modding_tools")
    end,
    print = function(text)
        pcall(function() modding_tools:console_print(text) end)
    end,
    print_separator = function()
        mod.debug.print("________________________________")
    end}

local function contains(str, substr)
    if type(str) ~= "string" or type(substr) ~= "string" then
        return false
    end
    return string.find(str, substr) ~= nil
end

mod._num_charges = 0

mod:hook_safe("HudElementPlayerAbility", "update", function(self, dt, t, ui_renderer, render_settings, input_service)
	local player = self._data.player
	local parent = self._parent
    local ability_extension = parent:get_player_extension(player, "ability_system")
    local ability_id = self._ability_id
    local remaining_ability_charges = ability_extension:remaining_ability_charges(ability_id)
    mod._num_charges = remaining_ability_charges
end)

local function getUnitData()
    local unit = Managers.player:local_player(1).player_unit
    if unit then
        local unit_data = ScriptUnit.extension(unit, "unit_data_system")
        if unit_data ~= nil then
            return unit_data
        end
    end
    return nil
end

local function isWieldBugCombo()
    local unit_data = getUnitData()
    if unit_data then
        local weapon = unit_data._components.weapon_action[1].template_name
        local ability = unit_data._components.equipped_abilities[1].combat_ability
        if contains(weapon, "combatsword_p2") and contains(ability, "zealot_relic") then
            return true
        end
    end
    return false
end

mod.promise_ability = false

local function setPromise()
    mod.promise_ability = true
end

local function clearPromise()
    mod.promise_ability = false
end

local function isPromised()
    if mod.promise_ability then
        if mod._num_charges == 0 then
            clearPromise()
        end
        if mod.debug.is_enabled() then
            mod.debug.print("Guarantee Ability Activation: " .. "Attempting to activate combat ability for you")
        end
    end
    return mod.promise_ability
end

local _input_hook = function(func, self, action_name)
    local out = func(self, action_name)
    local type_str = type(out)

    if (type_str == "boolean" and out == true) or (type_str == "number" and out == 1) then
        if action_name == "combat_ability_pressed" or action_name == "combat_ability_release" then
            if mod.debug.is_enabled() then
                mod.debug.print("Guarantee Ability Activation: Player pressed " .. action_name)
            end
        end
        if action_name == "combat_ability_pressed" and mod._current_slot ~= "slot_unarmed" and mod._num_charges > 0 then
            setPromise()
        end

        if action_name == "combat_ability_hold" and not mod:get("enable_combat_ability_hold") then
            return false
        end

        if action_name == "combat_ability_release" then
            if mod.debug.is_enabled() then
                mod.debug.print_separator()
            end
        end
    end

    if mod.promise_ability and (action_name == "action_two_pressed" or action_name == "action_two_hold") and isWieldBugCombo() then
        return true
    end

    if action_name == "combat_ability_pressed" then
        return out or isPromised()
    end

    return out
end

mod:hook("InputService", "_get", _input_hook)
mod:hook("InputService", "_get_simulate", _input_hook)

mod:hook_safe("PlayerUnitAbilityExtension", "use_ability_charge", function(self, ability_type, optional_num_charges)
    if ability_type == "combat_ability" then
        clearPromise()
        if mod.debug.is_enabled() then
            mod.debug.print("Guarantee Ability Activation: " .. "Game has successfully initiated the execution of PlayerUnitAbilityExtension:use_ability_charge")
        end
    end
end)

mod._current_slot = ""
mod:hook_safe("PlayerUnitWeaponExtension", "on_slot_wielded", function(self, slot_name, t, skip_wield_action)
    if slot_name == "slot_combat_ability" then
        clearPromise()
        if mod.debug.is_enabled() then
            mod.debug.print("Guarantee Ability Activation: " .. "Game has successfully initiated the execution of PlayerUnitWeaponExtension:on_slot_wielded(slot_combat_ability)")
        end
    end
    mod._current_slot = slot_name
end)

local _action_ability_base_hook = function(self, action_settings, t, time_scale, action_start_params)
    if action_settings.ability_type == "combat_ability" then
        mod.debug.print(action_settings)
        clearPromise()
        if mod.debug.is_enabled() then
            mod.debug.print("Guarantee Ability Activation: " .. "Game has successfully initiated the execution of ActionAbilityBase:Start")
        end
    end
end

mod:hook_require("scripts/extension_systems/weapon/actions/action_base", function(ActionAbilityBase)
    ActionAbilityBase.start = _action_ability_base_hook
end)