-- Guarantee Ability Activation mod by KamiUnitY. Ver. 1.1.0

local mod = get_mod("guarantee_ability_activation")
local modding_tools = get_mod("modding_tools")

mod.promise_ability = false

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

local CHARACTER_STATE_PROMISE_MAP = {
	dodging = true,
	ladder_top_leaving = true,
	ledge_vaulting = true,
    lunging = true,
	sliding = true,
	sprinting = true,
	stunned = true,
	walking = true,
}

local ALLOWED_DASH_STATE = {
	sprinting = true,
	walking = true,
}

local IS_DASH_ABILITY = {
    zealot_targeted_dash = true,
    zealot_targeted_dash_improved = true,
    zealot_targeted_dash_improved_double = true,
    ogryn_charge = true,
    ogryn_charge_increased_distance = true,
}

local character_state = {
    name = nil,
}

local current_slot = ""
local ability_num_charges = 0
local combat_ability
local weapon_template

local DELAY_DASH = 0.2 --second
local last_set_promise = os.clock()

mod.on_all_mods_loaded = function()
    modding_tools:watch("character_state",character_state,"name")
end


local function setPromise(from)
    if mod.debug.is_enabled() then
        mod.debug.print("Guarantee Ability Activation: setPromiseFrom: " .. from)
    end
    mod.promise_ability = true
    last_set_promise = os.clock()
end

local function clearPromise(from)
    if mod.debug.is_enabled() then
        mod.debug.print("Guarantee Ability Activation: clearPromiseFrom: " .. from)
    end
    mod.promise_ability = false
end

local function isPromised()
    local result
    -- local unit = Managers.player:local_player(1).player_unit
    -- if unit then
    --     local ability_system = ScriptUnit.extension(unit, "ability_system")
    --     mod.debug.print(ability_system:can_use_ability("combat_ability"))
    -- end
    if IS_DASH_ABILITY[combat_ability] then 
        result = mod.promise_ability and ALLOWED_DASH_STATE[character_state.name]
            and os.clock() - last_set_promise > DELAY_DASH -- preventing pressing too early which sometimes could result in double dashing (hacky solution, need can_use_ability function so I can replace this)
    else
        result = mod.promise_ability
    end
    if result then
        if mod.debug.is_enabled() then
            mod.debug.print("Guarantee Ability Activation: " .. "Attempting to activate combat ability for you")
        end
    end
    return result
end

mod:hook_safe("CharacterStateMachine", "fixed_update", function (self, unit, dt, t, frame, ...)
    character_state.name = self._state_current.name
end)

mod:hook_safe("PlayerUnitWeaponExtension", "_wielded_weapon", function(self, inventory_component, weapons)
	local wielded_slot = inventory_component.wielded_slot
    weapon_template = weapons[wielded_slot].weapon_template.name
end)

mod:hook_safe("PlayerUnitDataExtension", "fixed_update", function (self, unit, dt, t, fixed_frame)
    local unit_data = ScriptUnit.extension(unit, "unit_data_system")
    combat_ability = unit_data._components.equipped_abilities[1].combat_ability
end)

mod:hook_safe("HudElementPlayerAbility", "update", function(self, dt, t, ui_renderer, render_settings, input_service)
	local player = self._data.player
	local parent = self._parent
    local ability_extension = parent:get_player_extension(player, "ability_system")
    local ability_id = self._ability_id
    local remaining_ability_charges = ability_extension:remaining_ability_charges(ability_id)
    ability_num_charges = remaining_ability_charges
    if ability_num_charges == 0 then
        mod.promise_ability = false
    end
end)

local function isWieldBugCombo()
    return contains(weapon_template, "combatsword_p2") and contains(combat_ability, "zealot_relic")
end

local is_human_pressed = false
local _input_hook = function(func, self, action_name)
    local out = func(self, action_name)
    local type_str = type(out)

    if (type_str == "boolean" and out == true) or (type_str == "number" and out == 1) then
        if action_name == "combat_ability_pressed" or action_name == "combat_ability_release" then
            if mod.debug.is_enabled() then
                mod.debug.print("Guarantee Ability Activation: Player pressed " .. action_name)
            end
        end
        -- slot_unarmed means player is netted or pounced
        if action_name == "combat_ability_pressed" and current_slot ~= "slot_unarmed" and ability_num_charges > 0 and not IS_DASH_ABILITY[combat_ability] then
            setPromise("pressed")
        end

        if action_name == "combat_ability_hold" then
            is_human_pressed = true
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
        clearPromise("use_ability_charge")
        if mod.debug.is_enabled() then
            mod.debug.print("Guarantee Ability Activation: " .. "Game has successfully initiated the execution of PlayerUnitAbilityExtension:use_ability_charge")
        end
    end
end)

mod:hook_safe("PlayerUnitWeaponExtension", "on_slot_wielded", function(self, slot_name, t, skip_wield_action)
    if slot_name == "slot_combat_ability" then
        clearPromise("on_slot_wielded")
        if mod.debug.is_enabled() then
            mod.debug.print("Guarantee Ability Activation: " .. "Game has successfully initiated the execution of PlayerUnitWeaponExtension:on_slot_wielded(slot_combat_ability)")
        end
    end
    current_slot = slot_name
end)

local _action_ability_base_start_hook = function(self, action_settings, t, time_scale, action_start_params)
    if action_settings.ability_type == "combat_ability" and not IS_DASH_ABILITY[combat_ability] then
        clearPromise("ability_base_start")
        if mod.debug.is_enabled() then
            mod.debug.print("Guarantee Ability Activation: " .. "Game has successfully initiated the execution of ActionAbilityBase:Start")
        end
    end
end

local AIM_CANCEL = "hold_input_released"
local AIM_RELASE = "new_interrupting_action"
local AIM_RELASE_WHILE_DASH = "started_sprint"

local is_aim_dash = {
    targeted_dash_aim = true,
    directional_dash_aim = true,
}

local _action_ability_base_finish_hook = function (self, reason, data, t, time_in_action)
    local _is_human_pressed = is_human_pressed
    is_human_pressed = false
    local action_settings = self._action_settings
    if action_settings and action_settings.ability_type == "combat_ability" then
        -- mod.debug.print("is_human_pressed: " .. tostring(_is_human_pressed))
        if (reason == AIM_RELASE or reason == AIM_RELASE_WHILE_DASH) and _is_human_pressed then
            if is_aim_dash[action_settings.kind] then
                local state = character_state.name
                if CHARACTER_STATE_PROMISE_MAP[state] then
                    setPromise("finishaction")
                end
            end
        end
    end
end

mod:hook_require("scripts/extension_systems/weapon/actions/action_base", function(instance)
    instance.start = _action_ability_base_start_hook
    instance.finish = _action_ability_base_finish_hook
end)