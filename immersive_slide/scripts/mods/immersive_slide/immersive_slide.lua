local mod = get_mod("immersive_slide")
local modding_tools = get_mod("modding_tools")

local debug = {
    is_enabled = function(self)
        return modding_tools and modding_tools:is_enabled()
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

mod.on_all_mods_loaded = function()
    -- WATCHER
    modding_tools:watch("full_direction", mod, "full_direction")
    modding_tools:watch("look_direction", mod, "look_direction")
    modding_tools:watch("roll_offset", mod, "roll_offset")
    modding_tools:watch("yaw", mod, "yaw")
    modding_tools:watch("pitch", mod, "pitch")
    modding_tools:watch("roll", mod, "roll")
end

mod.roll_offset = 0
mod.move_direction = nil
mod.look_direction = nil
mod.roll_offset_target = 0 -- Target roll offset for smooth transitions

local DAMPING_SLIDE = 10
local DAMPING_RECOVER = 5
mod.roll_offset_damping = DAMPING_SLIDE -- Damping factor

mod.tilt_factor = 0.15

local look_direction_box = Vector3Box()
local move_direction_box = Vector3Box()

mod:hook("PlayerCharacterStateDodging", "_check_transition", function(func, self, unit, t, input_extension, next_state_params, still_dodging, wants_slide)
    local out = func(self, unit, t, input_extension, next_state_params, still_dodging, wants_slide)
    if self._player.viewport_name == "player1" then
        if out == "sliding" then
            local dodge_character_state_component = self._dodge_character_state_component
            local unit_rotation = self._first_person_component.rotation
            local flat_unit_rotation = Quaternion.look(Vector3.normalize(Vector3.flat(Quaternion.forward(unit_rotation))), Vector3.up())
            local move_direction = Quaternion.rotate(flat_unit_rotation, dodge_character_state_component.dodge_direction)
            
            move_direction_box:store(move_direction)
            debug:print("SLIDE!!!  " .. tostring(move_direction))
        end
    end
    return out
end)

mod:hook("PlayerCharacterStateSprinting", "_check_transition", function(func, self, unit, t, next_state_params, input_source, decreasing_speed, action_move_speed_modifier, sprint_momentum, wants_slide, wants_to_stop, has_weapon_action_input, weapon_action_input, move_direction, move_speed_without_weapon_actions)
    local out = func(self, unit, t, next_state_params, input_source, decreasing_speed, action_move_speed_modifier, sprint_momentum, wants_slide, wants_to_stop, has_weapon_action_input, weapon_action_input, move_direction, move_speed_without_weapon_actions)
    if self._player.viewport_name == "player1" then
        if out == "sliding" then
            -- Store the move_direction in the box
            move_direction_box:store(move_direction)
            debug:print("SLIDE!!!  " .. tostring(move_direction))
        end
    end
    return out
end)

local calculate_roll_offset = function(look_direction_box, move_direction_box)
    -- Unbox the vectors
    local look_direction = look_direction_box:unbox()
    local move_direction = move_direction_box:unbox()

    -- Ensure the vectors are normalized
    look_direction = Vector3.normalize(look_direction)
    move_direction = Vector3.normalize(move_direction)

    -- Project move_direction onto look_direction to get the forward component
    local forward_component = Vector3.dot(move_direction, look_direction) * look_direction

    -- Calculate the perpendicular component
    local perpendicular_component = move_direction - forward_component

    -- Calculate the magnitude of the perpendicular component
    local magnitude = Vector3.length(perpendicular_component)

    -- Determine the roll offset based on the magnitude
    local roll_offset = magnitude

    -- Determine the direction of the tilt using the cross product
    local cross = Vector3.cross(look_direction, move_direction)
    if cross.z < 0 then
        roll_offset = -roll_offset
    end

    -- Map the roll_offset to the range
    roll_offset = roll_offset * mod.tilt_factor

    return roll_offset
end

mod:hook("PlayerCharacterStateSliding", "_check_transition", function(func, self, unit, t, next_state_params, input_source, is_crouching, commit_period_over, max_mass_hit, current_speed)
    local out = func(self, unit, t, next_state_params, input_source, is_crouching, commit_period_over, max_mass_hit, current_speed)
    if self._player.viewport_name == "player1" then
        if move_direction_box and look_direction_box then
            -- Calculate roll_offset using the stored vectors
            mod.roll_offset_damping = DAMPING_SLIDE
            mod.roll_offset_target = calculate_roll_offset(look_direction_box, move_direction_box)
        end
    end
    return out
end)

mod:hook_safe("PlayerCharacterStateSliding", "on_exit", function(self, unit, t, next_state)
    mod.roll_offset_damping = DAMPING_RECOVER
    mod.roll_offset_target = 0
end)

mod:hook("CameraManager", "update", function(func, self, dt, t, viewport_name, yaw, pitch, roll)
    local out = func(self, dt, t, viewport_name, yaw, pitch, roll)
    if Managers and Managers.player then
        local unit = Managers.player:local_player(1).player_unit
        if unit then
            local unit_data = ScriptUnit.extension(unit, "unit_data_system")
            local first_person_component = unit_data:read_component("first_person")
            mod.look_rotation = first_person_component.rotation
            mod.look_direction = Vector3.normalize(Vector3.flat(Quaternion.forward(mod.look_rotation)))
            look_direction_box:store(mod.look_direction)

            mod.full_direction = Vector3.normalize(Quaternion.forward(mod.look_rotation))

            -- mod.roll_offset = mod.roll_offset + (mod.roll_offset_target - mod.roll_offset) * dt * mod.roll_offset_damping
            mod.roll_offset = 0.15

            local modified_roll = roll + mod.roll_offset

            out = func(self, dt, t, viewport_name, yaw, pitch, modified_roll)
            return out
        end
    end
    return out
end)
