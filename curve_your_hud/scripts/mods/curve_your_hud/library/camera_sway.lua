--this file is originally from Hud Studio mod all credit goes to the original author, malevhf.

local mod = get_mod("curve_your_hud")

local PI = math.pi
local TWO_PI = PI * 2
local exp = math.exp
local alive, has_node, node, local_pose = Unit.alive, Unit.has_node, Unit.node, Unit.local_pose
local matrix_rotation, yaw, pitch = Matrix4x4.rotation, Quaternion.yaw, Quaternion.pitch

---@class CameraSway
local CameraSway = {}

CameraSway.CAMERA_PX_PER_RAD = 10
CameraSway.MAX_RATE = 15
CameraSway.CAMERA_DELAY = 0.1
CameraSway.MOTION_PX_PER_RAD = 1500

local CAMERA_BONE = "ap_camera_node"

local yaw_rate, pitch_rate = 0, 0
local last_yaw, last_pitch

local camera_lag_x, camera_lag_y = 0, 0
local motion_x, motion_y = 0, 0
local offset_x, offset_y = 0, 0

local bone_unit, bone_index

---@param delta number
---@return number
local function wrap(delta)
	return (delta + PI) % TWO_PI - PI
end

---@param rate number
---@return number
local function clamp_rate(rate)
	local max = CameraSway.MAX_RATE
	return rate > max and max or (rate < -max and -max or rate)
end

local function local_player()
	local player_manager = Managers.player
	return player_manager and player_manager:local_player_safe(1)
end

local function get_local_player()
	local player = local_player()
	return player and player.player_unit
end

local function player_ext(unit, extension_name)
	return unit and alive(unit) and ScriptUnit.has_extension(unit, extension_name)
end

---@param dt number
function CameraSway.sample_camera(dt)
	local player = local_player()
	local orientation = player and player:get_orientation()
	if not orientation or dt <= 0 then
		last_yaw, last_pitch = nil, nil
		yaw_rate, pitch_rate = 0, 0
		return
	end
	local look_yaw, look_pitch = orientation.yaw, orientation.pitch
	if last_yaw then
		yaw_rate = clamp_rate(wrap(look_yaw - last_yaw) / dt)
		pitch_rate = clamp_rate(wrap(look_pitch - last_pitch) / dt)
	else
		yaw_rate, pitch_rate = 0, 0
	end
	last_yaw, last_pitch = look_yaw, look_pitch
end

---@return number
function CameraSway.sway_intensity()
	local save = Managers.save
	local account = save and save:account_data()
	local settings = account and account.interface_settings
	local value = settings and settings.camera_movement_offset_sway_intensity
	return type(value) == "number" and value / 100 or 1
end

function CameraSway.sample_motion()
	motion_x, motion_y = 0, 0
	local first_person = player_ext(get_local_player(), "first_person_system")
	local fp_unit = first_person and first_person:first_person_unit()
	if not (fp_unit and alive(fp_unit)) then
		return
	end
	if fp_unit ~= bone_unit then
		bone_unit = fp_unit
		bone_index = has_node(fp_unit, CAMERA_BONE) and node(fp_unit, CAMERA_BONE) or nil
	end
	if not bone_index then
		return
	end
	local bone_rotation = matrix_rotation(local_pose(fp_unit, bone_index))
	local scale = CameraSway.MOTION_PX_PER_RAD * CameraSway.sway_intensity()
	motion_x = wrap(yaw(bone_rotation)) * scale
	motion_y = wrap(pitch(bone_rotation)) * scale
end

function CameraSway.reset()
	yaw_rate, pitch_rate = 0, 0
	last_yaw, last_pitch = nil, nil
	camera_lag_x, camera_lag_y = 0, 0
	motion_x, motion_y = 0, 0
	offset_x, offset_y = 0, 0
	bone_unit, bone_index = nil, nil
end

---@param dt number
---@return number offset_x, number offset_y
function CameraSway.update(dt)
	local camera_strength = mod.settings.camera_sway
	local motion_strength = mod.settings.motion_sway
	
	if camera_strength ~= 0 then
		CameraSway.sample_camera(dt)
		local delay = CameraSway.CAMERA_DELAY
		local scale = CameraSway.CAMERA_PX_PER_RAD * camera_strength
		local target_x, target_y = yaw_rate * scale, pitch_rate * scale
		local blend = delay > 0 and (1 - exp(-dt / delay)) or 1
		camera_lag_x = camera_lag_x + (target_x - camera_lag_x) * blend
		camera_lag_y = camera_lag_y + (target_y - camera_lag_y) * blend
	else
		yaw_rate, pitch_rate = 0, 0
		last_yaw, last_pitch = nil, nil
		camera_lag_x, camera_lag_y = 0, 0
	end

	if motion_strength ~= 0 then
		CameraSway.sample_motion()
	else
		motion_x, motion_y = 0, 0
	end

	offset_x = camera_lag_x + motion_x * motion_strength
	offset_y = camera_lag_y + motion_y * motion_strength
	return offset_x, offset_y
end

---@return number offset_x, number offset_y
function CameraSway.offset()
	return offset_x, offset_y
end

return CameraSway
