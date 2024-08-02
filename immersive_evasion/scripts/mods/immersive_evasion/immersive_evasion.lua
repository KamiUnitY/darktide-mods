-- Immersive Evasion by KamiUnitY. Ver. 1.0.1

local mod = get_mod("immersive_evasion")
local modding_tools = get_mod("modding_tools")

--------------------------
-- MOD SETTINGS CACHING --
--------------------------

mod.settings = {
    tilt_factor_dodge          = mod:get("tilt_factor_dodge"),
    tilt_factor_slide          = mod:get("tilt_factor_slide"),
    enable_debug_modding_tools = mod:get("enable_debug_modding_tools"),
}

mod.on_setting_changed = function(setting_id)
    mod.settings[setting_id] = mod:get(setting_id)
end

------------------------
-- ON ALL MODS LOADED --
------------------------

mod.on_all_mods_loaded = function()
    -- WATCHER
    -- modding_tools:watch("look_rotation", mod, "look_rotation")
    -- modding_tools:watch("look_direction", mod, "look_direction")
    -- modding_tools:watch("roll_offset", mod, "roll_offset")
    -- modding_tools:watch("roll_offset_target", mod, "roll_offset_target")
end

-------------------------
-- MODDING TOOLS DEBUG --
-------------------------

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

---------------
-- CONSTANTS --
---------------

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

local DAMPING_MOVE = 10
local DAMPING_RECOVER = 7

local ROLL_OFFSET_THRESHOLD = 0.001

---------------
-- VARIABLES --
---------------

mod.roll_offset_damping = DAMPING_MOVE

mod.roll_offset = 0
mod.roll_offset_target = 0

mod.move_direction = nil
mod.look_direction = nil

local look_direction_box = Vector3Box()
local move_direction_box = Vector3Box()

--------------------------------------
-- ROLL OFFSET CALCULATION FUNCTION --
--------------------------------------

local calculate_roll_offset = function(tilt_factor)
    -- Unbox the vectors and normalize
    local look_direction = Vector3.normalize(look_direction_box:unbox())
    local move_direction = Vector3.normalize(move_direction_box:unbox())

    -- Project move_direction onto look_direction to get the forward component
    local forward_component = Vector3.dot(move_direction, look_direction) * look_direction

    -- Calculate the perpendicular component
    local perpendicular_component = move_direction - forward_component

    -- Determine the roll offset based on the magnitude
    local roll_offset = Vector3.length(perpendicular_component)

    -- Determine the direction of the tilt using the cross product
    local cross = Vector3.cross(look_direction, move_direction)
    if cross.z < 0 then
        roll_offset = -roll_offset
    end

    -- Map the roll_offset to the range
    roll_offset = roll_offset * tilt_factor

    return roll_offset
end

-------------------------
-- DODGE RELATED HOOKS --
-------------------------

-- SET ROLL OFFSET WHILE DODGING
mod:hook_safe("PlayerCharacterStateDodging", "_update_dodge", function(self, unit, dt, time_in_dodge, has_slide_input)
    if self._player.viewport_name == "player1" then
        local dodge_character_state_component = self._dodge_character_state_component
        local unit_rotation = self._first_person_component.rotation
        local flat_unit_rotation = Quaternion.look(Vector3.normalize(Vector3.flat(Quaternion.forward(unit_rotation))), Vector3.up())
        local move_direction = Quaternion.rotate(flat_unit_rotation, dodge_character_state_component.dodge_direction)
        local inverted_move_direction = move_direction * -1
        move_direction_box:store(inverted_move_direction)
        if modding_tools then debug:print_mod("DODGE!!!  " .. tostring(move_direction)) end
        if move_direction_box and look_direction_box then
            -- Calculate roll_offset using the stored vectors
            mod.roll_offset_damping = DAMPING_MOVE
            mod.roll_offset_target = calculate_roll_offset(mod.settings["tilt_factor_dodge"])
        end
    end
end)

-- CLEAR ROLL OFFSET WHEN EXITING DODGE
mod:hook_safe("PlayerCharacterStateDodging", "on_exit", function(self, unit, t, next_state)
    if self._player.viewport_name == "player1" then
        mod.roll_offset_damping = DAMPING_RECOVER
        mod.roll_offset_target = 0
    end
end)

-------------------------
-- SLIDE RELATED HOOKS --
-------------------------

-- STORE SLIDE DIRECTION AFTER DODGE
mod:hook("PlayerCharacterStateDodging", "_check_transition", function(func, self, unit, t, input_extension, next_state_params, still_dodging, wants_slide)
    local out = func(self, unit, t, input_extension, next_state_params, still_dodging, wants_slide)
    if self._player.viewport_name == "player1" then
        if out == "sliding" then
            local dodge_character_state_component = self._dodge_character_state_component
            local unit_rotation = self._first_person_component.rotation
            local flat_unit_rotation = Quaternion.look(Vector3.normalize(Vector3.flat(Quaternion.forward(unit_rotation))), Vector3.up())
            local move_direction = Quaternion.rotate(flat_unit_rotation, dodge_character_state_component.dodge_direction)
            -- Store the move_direction in the box
            move_direction_box:store(move_direction)
            if modding_tools then debug:print_mod("SLIDE!!!  " .. tostring(move_direction)) end
        end
    end
    return out
end)

-- STORE SLIDE DIRECTION AFTER SPRINT
mod:hook("PlayerCharacterStateSprinting", "_check_transition", function(func, self, unit, t, next_state_params, input_source, decreasing_speed, action_move_speed_modifier, sprint_momentum, wants_slide, wants_to_stop, has_weapon_action_input, weapon_action_input, move_direction, move_speed_without_weapon_actions)
    local out = func(self, unit, t, next_state_params, input_source, decreasing_speed, action_move_speed_modifier, sprint_momentum, wants_slide, wants_to_stop, has_weapon_action_input, weapon_action_input, move_direction, move_speed_without_weapon_actions)
    if self._player.viewport_name == "player1" then
        if out == "sliding" then
            -- Store the move_direction in the box
            move_direction_box:store(move_direction)
            if modding_tools then debug:print_mod("SLIDE!!!  " .. tostring(move_direction)) end
        end
    end
    return out
end)

-- SET ROLL OFFSET WHILE SLIDING
mod:hook_safe("PlayerCharacterStateSliding", "_check_transition", function(self, unit, t, next_state_params, input_source, is_crouching, commit_period_over, max_mass_hit, current_speed)
    if self._player.viewport_name == "player1" then
        if move_direction_box and look_direction_box then
            -- Calculate roll_offset using the stored vectors
            mod.roll_offset_damping = DAMPING_MOVE
            mod.roll_offset_target = calculate_roll_offset(mod.settings["tilt_factor_slide"])
        end
    end
end)

-- CLEAR ROLL OFFSET WHEN EXITING SLIDE
mod:hook_safe("PlayerCharacterStateSliding", "on_exit", function(self, unit, t, next_state)
    if self._player.viewport_name == "player1" then
        mod.roll_offset_damping = DAMPING_RECOVER
        mod.roll_offset_target = 0

    end
end)

--------------------------
-- CHARACTER STATE HOOK --
--------------------------

-- CLEAR ROLL OFFSET WHEN PLAYER GET DISABLED
mod:hook_safe("CharacterStateMachine", "fixed_update", function(self, unit, dt, t, frame, ...)
    if self._unit_data_extension._player.viewport_name == 'player1' then
        local character_state = self._state_current.name
        if not ALLOWED_CHARACTER_STATE[character_state] then
            mod.roll_offset_damping = DAMPING_RECOVER
            mod.roll_offset_target = 0
        end
    end
end)

-----------------
-- CAMERA HOOK --
-----------------

mod:hook("CameraManager", "update", function(func, self, dt, t, viewport_name, yaw, pitch, roll)
    if viewport_name == "player1" and (mod.roll_offset ~= 0 or mod.roll_offset_target ~= 0) then
        -- Create the initial rotation quaternion without roll offset
        local initial_rotation = Quaternion.from_yaw_pitch_roll(yaw, pitch, roll)

        -- Calculate the look direction and full direction without roll offset
        mod.look_rotation = initial_rotation
        mod.look_direction = Vector3.normalize(Vector3.flat(Quaternion.forward(mod.look_rotation)))
        look_direction_box:store(mod.look_direction)

        -- Smoothly update the roll offset
        mod.roll_offset = mod.roll_offset + (mod.roll_offset_target - mod.roll_offset) * dt * mod.roll_offset_damping
        if math.abs(mod.roll_offset_target - mod.roll_offset) < ROLL_OFFSET_THRESHOLD then
            mod.roll_offset = mod.roll_offset_target
        end

        -- Apply the roll offset to the rotation
        local roll_offset_rotation = Quaternion.from_yaw_pitch_roll(0, 0, mod.roll_offset)
        local final_rotation = Quaternion.multiply(initial_rotation, roll_offset_rotation)

        -- Extract the adjusted yaw, pitch, and roll from the final rotation quaternion
        local adjusted_yaw, adjusted_pitch, adjusted_roll = Quaternion.to_yaw_pitch_roll(final_rotation)

        -- Return the adjusted values
        return func(self, dt, t, viewport_name, adjusted_yaw, adjusted_pitch, adjusted_roll)
    end
    return func(self, dt, t, viewport_name, yaw, pitch, roll)
end)
