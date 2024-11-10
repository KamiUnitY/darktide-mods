-- Immersive Evasion by KamiUnitY. Ver. 1.1.1

local mod = get_mod("immersive_evasion")
local modding_tools = get_mod("modding_tools")

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

local START_RECOVERY_DODGE_AT_DISTANCE = 1
local START_RECOVERY_SLIDE_AT_SPEED = 3

local CURVE_RECOVERY_FACTOR = 2

local ROLL_OFFSET_THRESHOLD = 0.001

---------------
-- VARIABLES --
---------------

mod.roll_offset_damping = DAMPING_MOVE

mod.roll_offset = 0
mod.roll_offset_target = 0

mod.tilt_factor = 0

local look_direction_box = Vector3Box()
local move_direction_box = Vector3Box()

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

--------------------------
-- MOD SETTINGS CACHING --
--------------------------

mod.settings = {
    invert_dodge_angle         = mod:get("invert_dodge_angle"),
    invert_dodging_slide_angle = mod:get("invert_dodging_slide_angle"),
    tilt_factor_dodge          = mod:get("tilt_factor_dodge"),
    tilt_factor_dodging_slide  = mod:get("tilt_factor_dodging_slide"),
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
    -- modding_tools:watch("roll_offset", mod, "roll_offset")
    -- modding_tools:watch("roll_offset_target", mod, "roll_offset_target")
end

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

local calculate_smooth_recovery = function(roll_offset, remaining, start_recovery)
    local capped_remaining = math.min(remaining, start_recovery) / start_recovery
    local adjusted_roll_offset = roll_offset * capped_remaining ^ CURVE_RECOVERY_FACTOR
    return adjusted_roll_offset
end

-------------------------
-- DODGE RELATED HOOKS --
-------------------------

-- SET TILT FACTOR
mod:hook_safe("PlayerCharacterStateDodging", "on_enter", function(self, unit, dt, t, previous_state, params)
    if self._player.viewport_name == "player1" then
        mod.tilt_factor = mod.settings["tilt_factor_dodge"]
    end
end)

-- SET ROLL OFFSET WHILE DODGING
mod:hook_safe("PlayerCharacterStateDodging", "_check_transition", function(self, unit, t, input_extension, next_state_params, still_dodging, wants_slide)
    if self._player.viewport_name == "player1" then
        local dodge_character_state_component = self._dodge_character_state_component
        local unit_rotation = self._first_person_component.rotation
        local flat_unit_rotation = Quaternion.look(Vector3.normalize(Vector3.flat(Quaternion.forward(unit_rotation))), Vector3.up())
        local move_direction = Quaternion.rotate(flat_unit_rotation, dodge_character_state_component.dodge_direction)
        if not mod.settings["invert_dodge_angle"] then
            move_direction = move_direction * -1
        end
        move_direction_box:store(move_direction)
        if modding_tools then debug:print_mod("DODGE!!!  " .. tostring(move_direction)) end
        if move_direction_box and look_direction_box then
            -- Calculate roll_offset using the stored vectors
            local roll_offset = calculate_roll_offset(mod.tilt_factor)
            -- Smooth ending roll offset based on distance_left
            roll_offset = calculate_smooth_recovery(roll_offset, dodge_character_state_component.distance_left, START_RECOVERY_DODGE_AT_DISTANCE)

            mod.roll_offset_damping = DAMPING_MOVE
            mod.roll_offset_target = roll_offset
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

-- STORE SLIDE DIRECTION ON ENTER SLIDING
mod:hook_safe("PlayerCharacterStateSliding", "on_enter", function(self, unit, dt, t, previous_state, params)
    if self._player.viewport_name == "player1" then
        local move_input = self._input_extension:get("move")
        local rotation = self._first_person_component.rotation
        local move_direction = Quaternion.rotate(rotation, move_input)
        if previous_state == "dodging" then
            mod.tilt_factor = mod.settings["tilt_factor_dodging_slide"]
            if not mod.settings["invert_dodging_slide_angle"] then
                move_direction = move_direction * -1
            end
        else
            mod.tilt_factor = mod.settings["tilt_factor_slide"]
        end
        move_direction_box:store(move_direction)
        if modding_tools then debug:print_mod("SLIDE!!!  " .. tostring(move_direction)) end
    end
end)

-- SET ROLL OFFSET WHILE SLIDING
mod:hook_safe("PlayerCharacterStateSliding", "_check_transition", function(self, unit, t, next_state_params, input_source, is_crouching, commit_period_over, max_mass_hit, current_speed)
    if self._player.viewport_name == "player1" then
        if move_direction_box and look_direction_box then
            -- Calculate roll_offset using the stored vectors
            local roll_offset = calculate_roll_offset(mod.tilt_factor)
            -- Smooth ending roll offset based on current_speed
            roll_offset = calculate_smooth_recovery(roll_offset, current_speed, START_RECOVERY_SLIDE_AT_SPEED)

            mod.roll_offset_damping = DAMPING_MOVE
            mod.roll_offset_target = roll_offset
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

local _on_character_state_change = function (self)
    local character_state = self._state_current.name
    if not ALLOWED_CHARACTER_STATE[character_state] then
        mod.roll_offset_damping = DAMPING_RECOVER
        mod.roll_offset_target = 0
    end
end

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

-----------------
-- CAMERA HOOK --
-----------------

mod:hook("CameraManager", "update", function(func, self, dt, t, viewport_name, yaw, pitch, roll)
    if viewport_name == "player1" and (mod.roll_offset ~= 0 or mod.roll_offset_target ~= 0) then
        -- Create the initial rotation quaternion without roll offset
        local initial_rotation = Quaternion.from_yaw_pitch_roll(yaw, pitch, roll)

        -- Calculate the look direction and full direction without roll offset
        local look_direction = Vector3.normalize(Vector3.flat(Quaternion.forward(initial_rotation)))
        look_direction_box:store(look_direction)

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
