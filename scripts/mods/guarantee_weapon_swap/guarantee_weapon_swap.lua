-- Guarantee Weapon Swap mod by KamiUnitY. Ver. 1.1.3

local mod = get_mod("guarantee_weapon_swap")
local PlayerCharacterConstants = require("scripts/settings/player_character/player_character_constants")
local ability_configuration = PlayerCharacterConstants.ability_configuration

mod._can_wield_grenade = nil
mod._current_slot = ""
mod._previous_slot = ""

mod._promises = {
    quick = false,
    primary = false,
    secondary = false,
    grenade = false,
    pocketable = false,
    pocketable_small = false,
    device = false
}

mod._promise_slot_map = {
    slot_primary = "primary",
    slot_secondary = "secondary",
    slot_grenade_ability = "grenade",
    slot_pocketable = "pocketable",
    slot_pocketable_small = "pocketable_small",
    slot_device = "device",
}

mod._promise_action_map = {
    quick_wield = "quick",
    wield_1 = "primary",
    wield_2 = "secondary",
    grenade_ability_pressed = "grenade",
    wield_3 = "pocketable",
    wield_4 = "pocketable_small",
    wield_5 = "device"
}

mod._action_slot_map = {
    wield_1 = "slot_primary",
    wield_2 = "slot_secondary",
    grenade_ability_pressed = "slot_grenade_ability",
    wield_3 = "slot_pocketable",
    wield_4 = "slot_pocketable_small",
    wield_5 = "slot_device"
}

local function isPromised(action)
    -- if mod._promises[action] and mod._current_slot ~= "" then
    --     mod:echo("mod:                                        " .. mod._current_slot .. " -> " .. action)
    -- end
    return mod._promises[action]
end

local function setPromise(action_name)
    mod._promises[mod._promise_action_map[action_name]] = true
end

local function clearAllPromises()
    for key in pairs(mod._promises) do
        mod._promises[key] = false
    end
end

mod:hook_safe("PlayerUnitWeaponExtension", "on_slot_wielded", function(self, slot_name, t, skip_wield_action)
    mod._promises.quick = false
    mod._promises[mod._promise_slot_map[slot_name] or ""] = false
    mod._previous_slot = mod._current_slot
    mod._current_slot = slot_name
    -- if mod._current_slot ~= "" and mod._previous_slot ~= "" then
    --     mod:echo("game:                                        " .. mod._previous_slot .. " -> " .. mod._current_slot)
    -- end
end)

local _input_hook = function(func, self, action_name)
    local out = func(self, action_name)
    local type_str = type(out)

    if mod._promise_action_map[action_name] then
        if (type_str == "boolean" and out == true) or (type_str == "number" and out == 1) then
            clearAllPromises()
            if mod._current_slot ~= mod._action_slot_map[action_name] then
                setPromise(action_name)
            end
        end
        return func(self, action_name) or isPromised(mod._promise_action_map[action_name])
    end

    return out
end

mod:hook("InputService", "_get", _input_hook)
mod:hook("InputService", "_get_simulate", _input_hook)

mod:hook_safe("HudElementPlayerWeaponHandler", "_weapon_scan", function (self, extensions, ui_renderer)
    if (self._player_weapons.slot_pocketable_small == nil) then
        mod._promises.pocketable_small = false
    end
    if (self._player_weapons.slot_pocketable == nil) then
        mod._promises.pocketable = false
    end
    if (self._player_weapons.slot_device == nil) then
        mod._promises.device = false
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

            mod._can_wield_grenade = not not (can_use_ability and can_be_previously_wielded_to or can_be_wielded_when_depleted and can_be_previously_wielded_to)

            if mod._can_wield_grenade ~= true then
                mod._promises.grenade = false
            end

            if self._equipped_abilities.grenade_ability.name == "zealot_throwing_knives" then
                mod._promises.grenade = false
            end
		end
	end
end)