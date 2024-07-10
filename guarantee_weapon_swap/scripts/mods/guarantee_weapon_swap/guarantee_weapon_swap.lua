-- Guarantee Weapon Swap mod by KamiUnitY. Ver. 1.1.5

local mod = get_mod("guarantee_weapon_swap")
local PlayerCharacterConstants = require("scripts/settings/player_character/player_character_constants")
local ability_configuration = PlayerCharacterConstants.ability_configuration
local modding_tools = get_mod("modding_tools")

local grenade_ability
local can_wield_grenade = nil
local current_slot = ""
local previous_slot = ""

local promises = {
    quick = false,
    primary = false,
    secondary = false,
    grenade = false,
    pocketable = false,
    pocketable_small = false,
    device = false
}

local promise_slot_map = {
    slot_primary = "primary",
    slot_secondary = "secondary",
    slot_grenade_ability = "grenade",
    slot_pocketable = "pocketable",
    slot_pocketable_small = "pocketable_small",
    slot_device = "device",
}

local promise_action_map = {
    quick_wield = "quick",
    wield_1 = "primary",
    wield_2 = "secondary",
    grenade_ability_pressed = "grenade",
    wield_3 = "pocketable",
    wield_4 = "pocketable_small",
    wield_5 = "device"
}

local action_slot_map = {
    wield_1 = "slot_primary",
    wield_2 = "slot_secondary",
    grenade_ability_pressed = "slot_grenade_ability",
    wield_3 = "slot_pocketable",
    wield_4 = "slot_pocketable_small",
    wield_5 = "slot_device"
}

mod.debug = {
    is_enabled = function()
        return modding_tools and modding_tools:is_enabled() and mod:get("enable_debug_modding_tools")
    end,
    print = function(text)
        pcall(function() modding_tools:console_print(text) end)
    end
}

local function isPromised(action)
    if promises[action] and current_slot ~= "" then
        if mod.debug.is_enabled() then
            mod.debug.print("Guarantee Weapon Swap: Attempting to switch weapon: " .. current_slot .. " -> " .. action)
        end
    end
    return promises[action]
end

local function setPromise(action_name)
    promises[promise_action_map[action_name]] = true
end

local function clearAllPromises()
    for key in pairs(promises) do
        promises[key] = false
    end
end

mod:hook_safe("PlayerUnitDataExtension", "fixed_update", function (self, unit, dt, t, fixed_frame)
    local unit_data = ScriptUnit.extension(unit, "unit_data_system")
    grenade_ability = unit_data._components.equipped_abilities[1].grenade_ability
end)

mod:hook_safe("PlayerUnitWeaponExtension", "on_slot_wielded", function(self, slot_name, t, skip_wield_action)
    promises.quick = false
    promises[promise_slot_map[slot_name] or ""] = false
    previous_slot = current_slot
    current_slot = slot_name
    if current_slot ~= "" and previous_slot ~= "" then
        if mod.debug.is_enabled() then
            mod.debug.print("Guarantee Weapon Swap: " .. previous_slot .. " -> " .. current_slot)
        end
    end
end)

local _input_hook = function(func, self, action_name)
    local out = func(self, action_name)
    local type_str = type(out)

    if promise_action_map[action_name] then
        if (type_str == "boolean" and out == true) or (type_str == "number" and out == 1) then
            clearAllPromises()
            if current_slot ~= action_slot_map[action_name] and current_slot ~= "slot_unarmed" then
                if not (not mod:get("enable_zealot_throwing_knives") and action_name == "grenade_ability_pressed" and grenade_ability == "zealot_throwing_knives") then
                    setPromise(action_name)
                end
            end
        end
        return out or isPromised(promise_action_map[action_name])
    end

    return out
end

mod:hook("InputService", "_get", _input_hook)
mod:hook("InputService", "_get_simulate", _input_hook)

mod:hook_safe("HudElementPlayerWeaponHandler", "_weapon_scan", function (self, extensions, ui_renderer)
    if (self._player_weapons.slot_pocketable_small == nil) then
        promises.pocketable_small = false
    end
    if (self._player_weapons.slot_pocketable == nil) then
        promises.pocketable = false
    end
    if (self._player_weapons.slot_device == nil) then
        promises.device = false
    end
end)

mod:hook_safe("PlayerUnitAbilityExtension", "can_wield", function (self, slot_name, previous_check)
	for ability_type, ability_slot_name in pairs(ability_configuration) do
            if ability_slot_name == slot_name then
			local equipped_abilities = self._equipped_abilities
			local ability = equipped_abilities[ability_type]
			local can_be_wielded_when_depleted = ability.can_be_wielded_when_depleted
			local can_be_previously_wielded_to = not previous_check or ability.can_be_previously_wielded_to
			local can_use_ability = self:can_use_ability(ability_type)

            can_wield_grenade = not not (can_use_ability and can_be_previously_wielded_to or can_be_wielded_when_depleted and can_be_previously_wielded_to)

            if can_wield_grenade ~= true then
                promises.grenade = false
            end

            if equipped_abilities.grenade_ability.name == "zealot_throwing_knives" then
                promises.grenade = false
            end
		end
	end
end)