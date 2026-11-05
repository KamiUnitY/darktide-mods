---@class mod : DL_Mod
local mod = get_mod("curve_your_hud")

if mod.curve_your_hud_camera_sway then
	return mod.curve_your_hud_camera_sway
end

local Block = mod:core(mod.curve_your_hud_block, "blocks/block")
local Player = mod.dl.player

local PI = math.pi
local TWO_PI = PI * 2
local exp = math.exp
local player_ext, get_local_player = Player.extensions, Player.local_player_unit
local alive, has_node, node, local_pose = Unit.alive, Unit.has_node, Unit.node, Unit.local_pose
local matrix_rotation, yaw, pitch = Matrix4x4.rotation, Quaternion.yaw, Quaternion.pitch

---@class CameraSway
local CameraSway = {}

CameraSway.CAMERA_PX_PER_RAD = 15

CameraSway.MAX_RATE = 15

CameraSway.CAMERA_DELAY = 0.15

CameraSway.MOTION_PX_PER_RAD = 1500

local CAMERA_BONE = "ap_camera_node"

local yaw_rate, pitch_rate = 0, 0
local last_yaw, last_pitch

local motion_x, motion_y = 0, 0
local motion_sampled = false

local camera_sampled = false

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

---@param follow BlockCameraSway
---@param key string
---@param default any
---@return any
local function read(follow, key, default)
	local value = follow[key]
	if type(value) ~= type(default) then
		return default
	end
	return value
end
CameraSway.read = read

---@param dt number
function CameraSway.sample_camera(dt)
	camera_sampled = true
	local player = Player.local_player()
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

local function sample_motion()
	motion_sampled = true
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
CameraSway.sample_motion = sample_motion

---@param block Block
---@param follow BlockCameraSway
---@param dt number
---@return number lag_x, number lag_y
local function step_camera(block, follow, dt)
	local strength = read(follow, "camera_strength", Block.FOLLOW_STRENGTH_DEFAULT)
	local delay = read(follow, "camera_delay", CameraSway.CAMERA_DELAY)
	local scale = CameraSway.CAMERA_PX_PER_RAD * strength
	local target_x, target_y = yaw_rate * scale, pitch_rate * scale
	local blend = delay > 0 and (1 - exp(-dt / delay)) or 1
	local lag_x, lag_y = block._camera_lag_x or 0, block._camera_lag_y or 0
	lag_x = lag_x + (target_x - lag_x) * blend
	lag_y = lag_y + (target_y - lag_y) * blend
	block._camera_lag_x, block._camera_lag_y = lag_x, lag_y
	return lag_x, lag_y
end

---@param blocks Block[]
---@param evaluated table<integer, any>
---@param dt number
function CameraSway.update(blocks, evaluated, dt)
	camera_sampled, motion_sampled = false, false
	for b = 1, #blocks do
		local block = blocks[b]
		local follow = block.follow
		local dx, dy = 0, 0
		local any = false
		if follow and evaluated[b] ~= false then
			if follow.camera == true then
				if not camera_sampled then
					CameraSway.sample_camera(dt)
				end
				dx, dy = step_camera(block, follow, dt)
				any = true
			else
				block._camera_lag_x, block._camera_lag_y = nil, nil
			end

			if follow.motion == true then
				if not motion_sampled then
					sample_motion()
				end
				dx, dy = dx + motion_x, dy + motion_y
				any = true
			end
		elseif block._camera_lag_x then
			block._camera_lag_x, block._camera_lag_y = nil, nil
		end
		if any then
			block._follow_x, block._follow_y = dx, dy
		elseif block._follow_x then
			block._follow_x, block._follow_y = nil, nil
		end
	end

	if not camera_sampled then
		last_yaw, last_pitch = nil, nil
	end
end

mod.curve_your_hud_camera_sway = CameraSway

return CameraSway
