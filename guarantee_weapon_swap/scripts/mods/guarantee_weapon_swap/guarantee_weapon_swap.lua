-- Guarantee Weapon Swap by KamiUnitY. Ver. 1.4.1

local mod = get_mod("guarantee_weapon_swap")
local modding_tools = get_mod("modding_tools")

---------------
-- CONSTANTS --
---------------

local PROMISE_ACTION_MAP = {
    quick_wield             = "quick",
    wield_1                 = "primary",
    wield_2                 = "secondary",
    wield_3                 = "pocketable",
    wield_4                 = "pocketable_small",
    wield_5                 = "device",
    grenade_ability_pressed = "grenade",
}

local PROMISE_SLOT_MAP = {
    slot_primary          = "primary",
    slot_secondary        = "secondary",
    slot_pocketable       = "pocketable",
    slot_pocketable_small = "pocketable_small",
    slot_device           = "device",
    slot_grenade_ability  = "grenade",
}

local SLOT_ACTION_MAP = {
    primary          = "slot_primary",
    secondary        = "slot_secondary",
    pocketable       = "slot_pocketable",
    pocketable_small = "slot_pocketable_small",
    device           = "slot_device",
    grenade          = "slot_grenade_ability",
}

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

local INTERVAL_DO_PROMISE = 0.05

---------------
-- VARIABLES --
---------------

mod.promise_exist = false

mod.promises = {}

mod.last_do_promise = 0

local is_attack_prevent_weapon = false

local is_in_hub = false

local combat_ability = ""
local grenade_ability = ""

local current_slot = ""
local previous_slot = ""

local character_state = ""

---------------
-- UTILITIES --
---------------

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

local check_is_in_hub = function()
    local game_mode_manager = Managers.state.game_mode
    local game_mode_name = game_mode_manager and game_mode_manager:game_mode_name()
    return game_mode_name == "hub"
end

local time_now = function()
    return Managers.time and Managers.time:time("main")
end

local elapsed = function(time)
    return time_now() - time
end

--------------------------
-- MOD SETTINGS CACHING --
--------------------------

mod.settings = {
    queue_limit                     = mod:get("queue_limit"),
    enable_zealot_throwing_knives   = mod:get("enable_zealot_throwing_knives"),
    enable_debug_modding_tools      = mod:get("enable_debug_modding_tools"),
}

mod.on_setting_changed = function(setting_id)
    mod.settings[setting_id] = mod:get(setting_id)
end

------------------------
-- ON ALL MODS LOADED --
------------------------

mod.on_all_mods_loaded = function()
    -- Update is_in_hub
    is_in_hub = check_is_in_hub()

    -- WATCHER
    -- modding_tools:watch("promise_exist",mod,"promise_exist")
    -- modding_tools:watch("character_state",mod,"character_state")
end

---------------------------
-- ON GAME STATE CHANGED --
---------------------------

mod.on_game_state_changed = function(status, state_name)
    -- Update is_in_hub
    is_in_hub = check_is_in_hub()
end

-----------------------
-- PROMISE FUNCTIONS --
-----------------------

local function setPromise(action)
    table.insert(mod.promises, action)

    if #mod.promises > mod.settings["queue_limit"] then
        table.remove(mod.promises, 1)
    end

    mod.promise_exist = true
end

local function clearPromise(action)
    for i, promise in ipairs(mod.promises) do
        if promise == action then
            table.remove(mod.promises, i)
            mod.promise_exist = #mod.promises > 0
            return
        end
    end
end

local function clearAllPromises()
    if mod.promise_exist then
        table.clear(mod.promises)
        mod.promise_exist = false
    end
end

local function isPromised(action)
    if mod.promises[1] == action then
        if elapsed(mod.last_do_promise) < INTERVAL_DO_PROMISE then
            return false
        end
        if current_slot == SLOT_ACTION_MAP[action] then
            clearPromise(action)
            return false
        end
        mod.last_do_promise = time_now()
        if modding_tools then debug:print_mod("Attempting to switch weapon !!!") end
        return true
    end

    return false
end

----------------
-- ON TRIGGER --
----------------

-- CLEAR PROMISE ON ENTER OR EXIT GAMEPLAY

mod:hook_safe("GameplayStateRun", "on_enter", function(...)
    clearAllPromises()
end)

mod:hook_safe("GameplayStateRun", "on_exit", function(...)
    clearAllPromises()
end)

-- CLEAR PROMISE ON SUCCESSFULLY CHANGE WEAPON

local function _on_slot_wielded(self)
    local inventory_component = self._inventory_component
    local wielded_slot = inventory_component.wielded_slot

    if wielded_slot ~= current_slot then
        previous_slot = current_slot
        current_slot = wielded_slot

        local slot_weapon = self._weapons[current_slot]
        local weapon_template = slot_weapon and slot_weapon.weapon_template
        local weapon_keywords = weapon_template and weapon_template.keywords
        is_attack_prevent_weapon = weapon_keywords and (
            table.contains(weapon_keywords, "psyker") or
            table.contains(weapon_keywords, "force_staff")
        )

        clearPromise("quick")
        clearPromise(PROMISE_SLOT_MAP[current_slot])

        if current_slot ~= "" and previous_slot ~= "" then
            if modding_tools then debug:print_mod(previous_slot .. " -> " .. current_slot) end
        end
    end
end

mod:hook_safe("PlayerUnitWeaponExtension", "fixed_update", function(self, unit, dt, t, fixed_frame)
    if current_slot ~= "" then
        mod:hook_disable("PlayerUnitWeaponExtension", "fixed_update")
    end
    if self._player.viewport_name == "player1" then
        _on_slot_wielded(self)
    end
end)

mod:hook_safe("PlayerUnitWeaponExtension", "on_slot_wielded", function(self, slot_name, t, skip_wield_action)
    if self._player.viewport_name == "player1" then
        _on_slot_wielded(self)
    end
end)

mod:hook_safe("PlayerUnitWeaponExtension", "server_correction_occurred", function(self, unit)
    if self._player.viewport_name == "player1" then
        _on_slot_wielded(self)
    end
end)

-- CLEAR PROMISE ON FAILING TO WIELD GRENADE

mod:hook("PlayerUnitAbilityExtension", "can_wield", function(func, self, slot_name, previous_check)
    local can_wield = func(self, slot_name, previous_check)
    if self._player.viewport_name == "player1" then
        if slot_name == "slot_grenade_ability" then
            if not can_wield then
                clearPromise("grenade")
            elseif self._equipped_abilities.grenade_ability.name == "zealot_throwing_knives" then
                clearPromise("grenade")
            end
        end
    end
    return can_wield
end)

-- CLEAR PROMISE FOR NOT AVAILABLE ITEMS

mod:hook("PlayerUnitWeaponExtension", "can_wield", function(func, self, slot_name)
    local can_wield = func(self, slot_name)
    if self._player.viewport_name == "player1" then
        if not can_wield then
            clearPromise(PROMISE_SLOT_MAP[slot_name])
        end
    end
    return can_wield
end)

-- UPDATE CHARACTER STATE VARIABLE AND CLEAR PROMISE ON UNALLOWED CHARACTER STATE

local _on_character_state_change = function (self)
    character_state = self._state_current.name
    if not ALLOWED_CHARACTER_STATE[character_state] then
        clearAllPromises()
    end
end

mod:hook_safe("CharacterStateMachine", "fixed_update", function(self, unit, dt, t, frame, ...)
    if character_state ~= "" then
        mod:hook_disable("CharacterStateMachine", "fixed_update")
    end
    if self._unit_data_extension._player.viewport_name == 'player1' then
        _on_character_state_change(self)
    end
end)

mod:hook_safe("CharacterStateMachine", "_change_state", function(self, unit, dt, t, next_state, ...)
    if self._unit_data_extension._player.viewport_name == 'player1' then
        _on_character_state_change(self)
    end
end)

mod:hook_safe("CharacterStateMachine", "server_correction_occurred", function(self, unit)
    if self._unit_data_extension._player.viewport_name == 'player1' then
        _on_character_state_change(self)
    end
end)

-- UPDATE CHARACTER ABILITY VARIABLE

local _on_ability_equip = function (self)
    local _equipped_abilities = self._equipped_abilities
    if _equipped_abilities then
        combat_ability = _equipped_abilities.combat_ability and _equipped_abilities.combat_ability.name
        grenade_ability = _equipped_abilities.grenade_ability and _equipped_abilities.grenade_ability.name
    end
end

mod:hook_safe("PlayerUnitAbilityExtension", "fixed_update", function(self, unit, dt, t, fixed_frame)
    if combat_ability ~= "" and grenade_ability ~= "" then
        mod:hook_disable("PlayerUnitAbilityExtension", "fixed_update")
    end
    if self._player.viewport_name == "player1" then
        _on_ability_equip(self)
    end
end)

mod:hook_safe("PlayerUnitAbilityExtension", "_equip_ability", function(self, ability_type, ability, fixed_t, from_server_correction)
    if self._player.viewport_name == "player1" then
        _on_ability_equip(self)
    end
end)

--------------------
-- ON EVERY FRAME --
--------------------

----------------
-- INPUT HOOK --
----------------

local _input_hook = function(func, self, action_name)
    local out = func(self, action_name)
    local pressed = (out == true) or (type(out) == "number" and out > 0)

    if is_in_hub then
        return out
    end

    local promise_action = PROMISE_ACTION_MAP[action_name]
    if promise_action then
        if pressed then
            if ALLOWED_CHARACTER_STATE[character_state] then
                if (
                    action_name ~= "grenade_ability_pressed" or
                    (
                        (grenade_ability ~= "zealot_throwing_knives" or mod.settings["enable_zealot_throwing_knives"]) and
                        current_slot ~= "slot_luggable"
                    )
                )
                then
                    setPromise(promise_action)
                end
            end
        end
        return out or isPromised(promise_action)
    end

    if mod.promise_exist and is_attack_prevent_weapon then
        if action_name == "action_one_pressed" or action_name == "action_one_hold" then
            return false
        end

        if action_name == "action_two_pressed" or action_name == "action_two_hold" then
            return false
        end
    end

    return out
end

mod:hook("InputService", "_get", _input_hook)
mod:hook("InputService", "_get_simulate", _input_hook)
