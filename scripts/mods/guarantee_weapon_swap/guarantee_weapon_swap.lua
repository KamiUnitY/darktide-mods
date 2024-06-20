-- Guarantee Weapon Swap mod by KamiUnitY. Ver. 1.0.0

local mod = get_mod("guarantee_weapon_swap")

mod._current_slot = nil
mod._promise_quick_wield = false

local function do_quick_wield()
    if (mod._promise_quick_wield == true) then
        return true
    end
    return false
end

mod:hook_safe("PlayerUnitWeaponExtension", "on_slot_wielded", function(self, slot_name, t, skip_wield_action)
    mod._promise_quick_wield = false;
    mod._current_slot = slot_name
end)

local _input_hook = function(func, self, action_name)
    local out = func(self, action_name)
    local type_str = type(out)

    if (type_str == "boolean" and out == true) or (type_str == "number" and out == 1) then
        if action_name == "quick_wield" then
            mod._promise_quick_wield = true;
        end
        if action_name == "wield_1" and mod._current_slot ~= "slot_primary" then
            mod._promise_quick_wield = true;
        end
        if action_name == "wield_2" and mod._current_slot ~= "slot_secondary" then
            mod._promise_quick_wield = true;
        end
    end

    if action_name == "quick_wield" then
        return func(self, "quick_wield") or do_quick_wield()
    end

    return out
end

mod:hook("InputService", "_get", _input_hook)
