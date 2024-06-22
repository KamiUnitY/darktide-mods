-- Guarantee Weapon Swap mod by KamiUnitY. Ver. 1.1.1

local mod = get_mod("guarantee_weapon_swap")
local PlayerCharacterConstants = require("scripts/settings/player_character/player_character_constants")
local ability_configuration = PlayerCharacterConstants.ability_configuration

mod._can_wield_grenade = nil
mod._current_slot = nil

mod._promises = {
    quick = false,
    primary = false,
    secondary = false,
    grenade = false,
    pocketable = false,
    pocketable_small = false
}

local function isPromised(action)
    if mod._promises[action] then
        -- if mod._current_slot ~= nil then
        --     mod:echo(mod._current_slot .. " -> " .. action)
        -- end
        return true
    end
    return false
end

local function clearAllPromises()
    for key in pairs(mod._promises) do
        mod._promises[key] = false
    end
end

mod:hook_safe("PlayerUnitWeaponExtension", "on_slot_wielded", function(self, slot_name, t, skip_wield_action)
    mod._promises.quick = false
    if slot_name == "slot_primary" then
        mod._promises.primary = false
    elseif slot_name == "slot_secondary" then
        mod._promises.secondary = false
    elseif slot_name == "slot_grenade_ability" then
        mod._promises.grenade = false
    elseif slot_name == "slot_pocketable" then
        mod._promises.pocketable = false
    elseif slot_name == "slot_pocketable_small" then
        mod._promises.pocketable_small = false
    end
    mod._current_slot = slot_name
end)

local _input_hook = function(func, self, action_name)
    local out = func(self, action_name)
    local type_str = type(out)

    if (type_str == "boolean" and out == true) or (type_str == "number" and out == 1) then
        if action_name == "quick_wield" then
            clearAllPromises()
            mod._promises.quick = true
        elseif action_name == "wield_1" and mod._current_slot ~= "slot_primary" then
            clearAllPromises()
            mod._promises.primary = true
        elseif action_name == "wield_2" and mod._current_slot ~= "slot_secondary" then
            clearAllPromises()
            mod._promises.secondary = true
        elseif action_name == "grenade_ability_pressed" and mod._current_slot ~= "slot_grenade_ability" and mod._can_wield_grenade == true then
            clearAllPromises()
            mod._promises.grenade = true
        elseif action_name == "wield_3" and mod._current_slot ~= "slot_pocketable" then
            clearAllPromises()
            mod._promises.pocketable = true
        elseif action_name == "wield_4" and mod._current_slot ~= "slot_pocketable_small" then
            clearAllPromises()
            mod._promises.pocketable_small = true
        end
    end

    if action_name == "quick_wield" then
        return func(self, "quick_wield") or isPromised("quick")
    elseif action_name == "wield_1" then
        return func(self, "wield_1") or isPromised("primary")
    elseif action_name == "wield_2" then
        return func(self, "wield_2") or isPromised("secondary")
    elseif action_name == "grenade_ability_pressed" then
        return func(self, "grenade_ability_pressed") or isPromised("grenade")
    elseif action_name == "wield_3" then
        return func(self, "wield_3") or isPromised("pocketable")
    elseif action_name == "wield_4" then
        return func(self, "wield_4") or isPromised("pocketable_small")
    end

    return out
end

mod:hook("InputService", "_get", _input_hook)


mod:hook_safe("HudElementPlayerWeaponHandler", "_weapon_scan", function (self, extensions, ui_renderer)
    if (self._player_weapons.slot_pocketable_small == nil) then
        mod._promises.pocketable_small = false
    end
    if (self._player_weapons.slot_pocketable == nil) then
        mod._promises.pocketable = false
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
            mod._can_wield_grenade = can_use_ability and can_be_previously_wielded_to or can_be_wielded_when_depleted and can_be_previously_wielded_to

            if mod._can_wield_grenade ~= true then
                mod._promises.grenade = false
            end

            if self._equipped_abilities.grenade_ability.name == "zealot_throwing_knives" then
                mod._promises.grenade = false
            end
		end
	end
end)

