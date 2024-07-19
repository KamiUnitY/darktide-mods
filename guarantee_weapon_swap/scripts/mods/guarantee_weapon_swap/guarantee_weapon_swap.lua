-- Guarantee Weapon Swap mod by KamiUnitY. Ver. 1.1.5

local mod = get_mod("guarantee_weapon_swap")
local PlayerCharacterConstants = require("scripts/settings/player_character/player_character_constants")
local ability_configuration = PlayerCharacterConstants.ability_configuration
local modding_tools = get_mod("modding_tools")

local grenade_ability
local current_slot = ""
local previous_slot = ""

mod.promises = {
    quick = false,
    primary = false,
    secondary = false,
    grenade = false,
    pocketable = false,
    pocketable_small = false,
    device = false
}

local PROMISE_SLOT_MAP = {
    slot_primary = "primary",
    slot_secondary = "secondary",
    slot_grenade_ability = "grenade",
    slot_pocketable = "pocketable",
    slot_pocketable_small = "pocketable_small",
    slot_device = "device",
}

local PROMISE_ACTION_MAP = {
    quick_wield = "quick",
    wield_1 = "primary",
    wield_2 = "secondary",
    grenade_ability_pressed = "grenade",
    wield_3 = "pocketable",
    wield_4 = "pocketable_small",
    wield_5 = "device"
}

local ACTION_SLOT_MAP = {
    wield_1 = "slot_primary",
    wield_2 = "slot_secondary",
    grenade_ability_pressed = "slot_grenade_ability",
    wield_3 = "slot_pocketable",
    wield_4 = "slot_pocketable_small",
    wield_5 = "slot_device"
}

mod.character_state = nil

local ALLOWED_CHARACTER_STATE = {
	dodging = true,
	ledge_vaulting = true,
    lunging = true,
	sliding = true,
	sprinting = true,
	stunned = true,
	walking = true,
    jumping = true,
    falling = true,
}

local debug = {
    is_enabled = function(self)
        return modding_tools and modding_tools:is_enabled() and mod:get("enable_debug_modding_tools")
    end,
    print = function(self, text)
        pcall(function() modding_tools:console_print(text) end)
    end
}

local function isPromised(action)
    if mod.promises[action] and current_slot ~= "" then
        if debug:is_enabled() then
            debug:print("Guarantee Weapon Swap: Attempting to switch weapon: " .. current_slot .. " -> " .. action)
        end
    end
    return mod.promises[action]
end

local function setPromise(action_name)
    mod.promises[PROMISE_ACTION_MAP[action_name]] = true
end

local function clearAllPromises()
    for key in pairs(mod.promises) do
        mod.promises[key] = false
    end
end

mod:hook_safe("PlayerUnitDataExtension", "fixed_update", function (self, unit, dt, t, fixed_frame)
    local unit_data = ScriptUnit.extension(unit, "unit_data_system")
    grenade_ability = unit_data._components.equipped_abilities[1].grenade_ability
end)

mod:hook_safe("PlayerUnitWeaponExtension", "on_slot_wielded", function(self, slot_name, t, skip_wield_action)
    mod.promises.quick = false
    mod.promises[PROMISE_SLOT_MAP[slot_name] or ""] = false
end)

mod:hook_safe("PlayerUnitWeaponExtension", "_wielded_weapon", function(self, inventory_component, weapons)
    local wielded_slot = inventory_component.wielded_slot
    if wielded_slot ~= nil then
        if wielded_slot ~= current_slot then
            previous_slot = current_slot
            current_slot = wielded_slot
            if current_slot ~= "" and previous_slot ~= "" then
                if debug:is_enabled() then
                    debug:print("Guarantee Weapon Swap: " .. previous_slot .. " -> " .. current_slot)
                end
            end
        end
    end
end)

local _input_hook = function(func, self, action_name)
    local out = func(self, action_name)
    local type_str = type(out)
    local pressed = (type_str == "boolean" and out == true) or (type_str == "number" and out == 1)

    if PROMISE_ACTION_MAP[action_name] then
        if pressed then
            clearAllPromises()
            if current_slot ~= ACTION_SLOT_MAP[action_name] and ALLOWED_CHARACTER_STATE[mod.character_state] and current_slot ~= "slot_unarmed" then
                if action_name ~= "grenade_ability_pressed" or grenade_ability ~= "zealot_throwing_knives" or (mod:get("enable_zealot_throwing_knives") and current_slot ~= "slot_luggable") then
                    setPromise(action_name)
                end
            end
        end
        return out or isPromised(PROMISE_ACTION_MAP[action_name])
    end

    return out
end

mod:hook("InputService", "_get", _input_hook)
mod:hook("InputService", "_get_simulate", _input_hook)

mod:hook_safe("HudElementPlayerWeaponHandler", "_weapon_scan", function (self, extensions, ui_renderer)
    if (self._player_weapons.slot_pocketable_small == nil) then
        mod.promises.pocketable_small = false
    end
    if (self._player_weapons.slot_pocketable == nil) then
        mod.promises.pocketable = false
    end
    if (self._player_weapons.slot_device == nil) then
        mod.promises.device = false
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

            local can_wield_grenade = not not (can_use_ability and can_be_previously_wielded_to or can_be_wielded_when_depleted and can_be_previously_wielded_to)

            if can_wield_grenade ~= true then
                mod.promises.grenade = false
            end

            if equipped_abilities.grenade_ability.name == "zealot_throwing_knives" then
                mod.promises.grenade = false
            end
		end
	end
end)

mod:hook_safe("CharacterStateMachine", "fixed_update", function (self, unit, dt, t, frame, ...)
    if self._unit_data_extension._player.viewport_name == 'player1' then
        mod.character_state = self._state_current.name
    end
end)