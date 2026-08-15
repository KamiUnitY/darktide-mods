local mod = get_mod("curved_hud")

local HudElementBase = require("scripts/ui/hud/elements/hud_element_base")
local HudElementPlayerBuffs = require("scripts/ui/hud/elements/player_buffs/hud_element_player_buffs_polling")
local UIRenderer = require("scripts/managers/ui/ui_renderer")
local UIWidget = require("scripts/managers/ui/ui_widget")

local EXCLUDED_ELEMENT_NAMES = {
	HudElementPrologueTutorialSequenceTransitionEnd = true,
	HudElementPrologueTutorialInfoBox = true,
	HudElementCrosshair = true,
	HudElementInteraction = true,
	HudElementWorldMarkers = true,
	HudElementEmoteWheel = true,
	HudElementSmartTagging = true,
	HudElementDamageIndicator = true,
	ConstantElementWatermark = true,
	ConstantElementPopupHandler = true,
	ConstantElementSoftwareCursor = true,
}

local CAMERA_FOLLOW_DELAY_SECONDS = 0.02
local CAMERA_CUT_ANGLE = math.degrees_to_radians(45)
local CAMERA_CUT_DISTANCE = 5
local CAMERA_SWAY_SCALE = 0.1
local WORLD_SWAY_SCALE = 1.0
local WORLD_PIXELS_PER_SCREEN_HEIGHT = 0.16
local HUD_EDGE_MARGIN = 2

-- HUD ownership and draw-pass state.
local hud_scenegraphs = setmetatable({}, { __mode = "k" })
local corner_curve_scenegraphs = setmetatable({}, { __mode = "k" })
local horizontally_centered_scenegraphs = setmetatable({}, { __mode = "k" })
local hud_elements = setmetatable({}, { __mode = "k" })
local recent_container_nodes = setmetatable({}, { __mode = "k" })
local renderer_group_stacks = setmetatable({}, { __mode = "k" })
local widget_graphic_anchor
local drawing_widget = false
local drawing_corner_anchored_widget = false
local drawing_screen_centered_widget = false
local drawing_hud_element_group = false
local buff_curve_suppressed = false
local gameplay_hooks_enabled = true
local hud_frame = 0

-- Smoothed camera state used by HUD sway.
---@type number?
local smoothed_camera_yaw
---@type number?
local smoothed_camera_pitch
---@type number?
local smoothed_camera_x
---@type number?
local smoothed_camera_y
---@type number?
local smoothed_camera_z
local camera_lag_x = 0.0
local camera_lag_y = 0.0

-- Camera sway ---------------------------------------------------------------

local function shortest_angle_delta(target, current)
	return (target - current + math.pi) % (math.pi * 2) - math.pi
end

local function reset_camera_lag()
	smoothed_camera_yaw = nil
	smoothed_camera_pitch = nil
	smoothed_camera_x = nil
	smoothed_camera_y = nil
	smoothed_camera_z = nil
	camera_lag_x = 0.0
	camera_lag_y = 0.0
end

local function set_camera_lag_origin(yaw, pitch, position_x, position_y, position_z)
	smoothed_camera_yaw = yaw
	smoothed_camera_pitch = pitch
	smoothed_camera_x = position_x
	smoothed_camera_y = position_y
	smoothed_camera_z = position_z
	camera_lag_x = 0.0
	camera_lag_y = 0.0
end

local function current_camera_pose()
	local player_manager = Managers.player
	local camera_manager = Managers.state and Managers.state.camera

	-- Mod updates begin before the game has created its connection and camera
	-- managers. PlayerManager:local_player calls Network.peer_id directly and
	-- can therefore crash during these startup frames.
	if not player_manager or not camera_manager then
		return nil, nil
	end

	local player = player_manager:local_player_safe(1)
	local viewport_name = player and player.viewport_name

	if not viewport_name or not camera_manager:has_camera(viewport_name) then
		return nil, nil
	end

	local rotation = camera_manager:camera_rotation(viewport_name)
	local position = camera_manager:camera_position(viewport_name)

	if not rotation or not Quaternion.is_valid(rotation) or not position or not Vector3.is_valid(position) then
		return nil, nil
	end

	return rotation, position
end

local function clamp_screen_offset(offset_x, offset_y, limit)
	local distance = math.sqrt(offset_x * offset_x + offset_y * offset_y)

	if distance <= limit then
		return offset_x, offset_y
	end

	local scale = limit / distance

	return offset_x * scale, offset_y * scale
end

local function update_camera_lag(dt)
	if not dt or dt <= 0 then
		reset_camera_lag()
		return
	end

	local rotation, position = current_camera_pose()

	if not rotation then
		reset_camera_lag()
		return
	end

	local yaw, pitch = Quaternion.to_yaw_pitch_roll(rotation)
	local position_x = position[1]
	local position_y = position[2]
	local position_z = position[3]

	if not smoothed_camera_yaw or not smoothed_camera_pitch or not smoothed_camera_x or not smoothed_camera_y or not smoothed_camera_z then
		set_camera_lag_origin(yaw, pitch, position_x, position_y, position_z)
		return
	end

	local yaw_delta = shortest_angle_delta(yaw, smoothed_camera_yaw)
	local pitch_delta = shortest_angle_delta(pitch, smoothed_camera_pitch)
	local position_delta_x = position_x - smoothed_camera_x
	local position_delta_y = position_y - smoothed_camera_y
	local position_delta_z = position_z - smoothed_camera_z
	local position_delta_distance = math.sqrt(
		position_delta_x * position_delta_x +
		position_delta_y * position_delta_y +
		position_delta_z * position_delta_z
	)

	-- Camera cuts and viewpoint changes should never fling the HUD across the
	-- screen. Treat a large rotation or world-position jump as a new camera.
	if math.abs(yaw_delta) > CAMERA_CUT_ANGLE or math.abs(pitch_delta) > CAMERA_CUT_ANGLE or position_delta_distance > CAMERA_CUT_DISTANCE then
		set_camera_lag_origin(yaw, pitch, position_x, position_y, position_z)
		return
	end

	local follow_fraction = 1 - math.exp(-dt / CAMERA_FOLLOW_DELAY_SECONDS)

	smoothed_camera_yaw = smoothed_camera_yaw + yaw_delta * follow_fraction
	smoothed_camera_pitch = smoothed_camera_pitch + pitch_delta * follow_fraction
	smoothed_camera_x = smoothed_camera_x + position_delta_x * follow_fraction
	smoothed_camera_y = smoothed_camera_y + position_delta_y * follow_fraction
	smoothed_camera_z = smoothed_camera_z + position_delta_z * follow_fraction

	local lag_yaw = shortest_angle_delta(smoothed_camera_yaw, yaw)
	local lag_pitch = shortest_angle_delta(smoothed_camera_pitch, pitch)
	local world_lag_x = smoothed_camera_x - position_x
	local world_lag_y = smoothed_camera_y - position_y
	local world_lag_z = smoothed_camera_z - position_z
	local camera_right = Quaternion.right(rotation)
	local camera_up = Quaternion.up(rotation)
	local lag_right = world_lag_x * camera_right[1] + world_lag_y * camera_right[2] + world_lag_z * camera_right[3]
	local lag_up = world_lag_x * camera_up[1] + world_lag_y * camera_up[2] + world_lag_z * camera_up[3]
	local width = RESOLUTION_LOOKUP.width or 1920
	local height = RESOLUTION_LOOKUP.height or 1080
	local movement_limit_percent = math.clamp(tonumber(mod:get("camera_follow_limit")) or 1.0, 0.0, 2.0)
	local movement_limit = math.min(width, height) * movement_limit_percent * 0.01
	local world_pixels_per_meter = height * WORLD_PIXELS_PER_SCREEN_HEIGHT
	local camera_lag_pixels_x = -lag_yaw * width * 0.5 * CAMERA_SWAY_SCALE
	local camera_lag_pixels_y = -lag_pitch * height * 0.7 * CAMERA_SWAY_SCALE
	local world_lag_pixels_x = lag_right * world_pixels_per_meter * WORLD_SWAY_SCALE
	local world_lag_pixels_y = -lag_up * world_pixels_per_meter * WORLD_SWAY_SCALE
	local target_lag_x = camera_lag_pixels_x + world_lag_pixels_x
	local target_lag_y = camera_lag_pixels_y + world_lag_pixels_y

	if movement_limit <= 0 then
		camera_lag_x = 0.0
		camera_lag_y = 0.0
		return
	end

	local limited_lag_x, limited_lag_y = clamp_screen_offset(target_lag_x, target_lag_y, movement_limit)

	-- Smooth the final screen-space movement as well as the tracked camera
	-- angles. This removes the rigid start/stop response without making the
	-- configured delay substantially longer.
	local movement_smoothing_time = math.max(CAMERA_FOLLOW_DELAY_SECONDS * 0.5, 0.05)
	local movement_fraction = 1 - math.exp(-dt / movement_smoothing_time)

	camera_lag_x = camera_lag_x + (limited_lag_x - camera_lag_x) * movement_fraction
	camera_lag_y = camera_lag_y + (limited_lag_y - camera_lag_y) * movement_fraction

	camera_lag_x, camera_lag_y = clamp_screen_offset(camera_lag_x, camera_lag_y, movement_limit)
end

-- Curve and widget grouping -------------------------------------------------

local function top_level_screen_alignment(node, scenegraph)
	local parent_id = node and node.parent
	local parent = parent_id and rawget(scenegraph, parent_id)

	if parent and not parent.parent then
		return node.horizontal_alignment, node.vertical_alignment
	end

	return nil, nil
end

local function is_corner_alignment(horizontal_alignment, vertical_alignment)
	local horizontal_edge = horizontal_alignment == "left" or horizontal_alignment == "right"
	local vertical_edge = vertical_alignment == "top" or vertical_alignment == "bottom"

	return horizontal_edge and vertical_edge
end

local function classify_scenegraph_anchors(scenegraph)
	if not scenegraph then
		return false, false, false
	end

	local corner_anchored = false
	local screen_centered = false
	local horizontally_centered = false
	local other_anchored = false

	for _, node in pairs(scenegraph) do
		if type(node) == "table" then
			local horizontal_alignment, vertical_alignment = top_level_screen_alignment(node, scenegraph)

			if horizontal_alignment == "center" then
				horizontally_centered = true
			end

			if is_corner_alignment(horizontal_alignment, vertical_alignment) then
				corner_anchored = true
			elseif horizontal_alignment == "center" and vertical_alignment == "center" then
				screen_centered = true
			elseif horizontal_alignment then
				other_anchored = true
			end
		end
	end

	return corner_anchored,
		screen_centered and not corner_anchored and not other_anchored,
		horizontally_centered
end

local function classify_widget_anchor(widget, renderer)
	local scenegraph = renderer and renderer.ui_scenegraph
	local scenegraph_id = widget and widget.scenegraph_id

	while scenegraph and scenegraph_id do
		local node = rawget(scenegraph, scenegraph_id)

		if not node then
			break
		end

		-- A widget attached directly to the scenegraph root is a screen-wide
		-- overlay rather than a positioned HUD container. Leave overlays such as
		-- cinematic bars and fades completely untouched by curve and sway.
		if not node.parent then
			return false, true
		end

		-- Only the first container below the screen root describes the widget's
		-- screen anchor. Inner nodes often use center alignment within that
		-- container and must not be mistaken for screen-centered widgets.
		local horizontal_alignment, vertical_alignment = top_level_screen_alignment(node, scenegraph)

		if horizontal_alignment then
			local corner_anchored = is_corner_alignment(horizontal_alignment, vertical_alignment)
			local screen_centered = horizontal_alignment == "center" and vertical_alignment == "center"

			return corner_anchored, screen_centered
		end

		scenegraph_id = node.parent
	end

	return false, false
end

local function refresh_hud_element_anchor_profile(element)
	if EXCLUDED_ELEMENT_NAMES[element.__class_name] then
		return
	end

	local scenegraph = element._ui_scenegraph

	if not scenegraph then
		return
	end

	local corner_anchored, screen_centered, horizontally_centered = classify_scenegraph_anchors(scenegraph)

	-- A horizontally centered owner is authoritative for the complete element.
	-- Auxiliary compass nodes, for example, use left/top alignment internally
	-- but must not promote their shared scenegraph into the corner curve set.
	horizontally_centered_scenegraphs[scenegraph] = horizontally_centered and true or nil
	corner_curve_scenegraphs[scenegraph] = corner_anchored and not horizontally_centered and true or nil

	if screen_centered then
		hud_scenegraphs[scenegraph] = nil
		hud_elements[element] = nil
	else
		hud_scenegraphs[scenegraph] = true
		hud_elements[element] = true
	end
end

local function hud_curve(renderer, position, size)
	local scenegraph = renderer.ui_scenegraph

	if drawing_screen_centered_widget or not mod:is_enabled() or not hud_scenegraphs[scenegraph] then
		return nil
	end

	local scale = renderer.scale or 1
	-- Renderer positions are already in scaled GUI/back-buffer coordinates.
	-- `renderer.scale` may also contain the user's HUD-scale multiplier, so
	-- 1920 * scale is not necessarily the viewport width and shifts the curve's
	-- symmetry axis. Always mirror around the actual render surface instead.
	local width = RESOLUTION_LOOKUP.width or 1920 * scale
	local height = RESOLUTION_LOOKUP.height or 1080 * scale
	local primitive_width = size and size[1] or 0
	local primitive_height = size and size[2] or 0
	local half_width = width * 0.5
	local half_height = height * 0.5
	local primitive_center_x = position[1] + primitive_width * 0.5
	local primitive_center_y = position[2] + primitive_height * 0.5
	local dx = primitive_center_x - half_width
	local dy = primitive_center_y - half_height
	local u = math.clamp(dx / half_width, -1, 1)
	local v = math.clamp(dy / half_height, -1, 1)
	local suppress_curve = buff_curve_suppressed
		or horizontally_centered_scenegraphs[scenegraph]
		or not corner_curve_scenegraphs[scenegraph]
		or (drawing_widget and not drawing_corner_anchored_widget)
	local strength = suppress_curve and 0 or math.degrees_to_radians(mod:get("curve_strength") or 0)
	local tangent = math.tan(strength)

	-- A separable concave-screen projection matching the reference grid:
	-- horizontal rows pinch toward the vertical center at the side edges, while
	-- vertical columns spread slightly outward near the top and bottom. Both
	-- terms are even quadratics, so each half is monotonic with no waves.
	local vertical_curve = tangent * half_width / (2 * half_height)
	local horizontal_curve = tangent * half_height / (2 * half_width)
	-- Compress only an axis whose curve expands its outermost points. This
	-- preserves the requested curve direction for both positive and negative
	-- strengths while keeping the warped layout inside the render surface.
	local horizontal_fit = 1 / math.max(1, 1 + horizontal_curve)
	local vertical_fit = 1 / math.max(1, 1 - vertical_curve)
	local mapped_center_x = half_width + dx * (1 + horizontal_curve * v * v) * horizontal_fit + camera_lag_x
	local mapped_center_y = half_height + dy * (1 - vertical_curve * u * u) * vertical_fit + camera_lag_y

	-- Rotate along the tangent of the same y(x) curve used above. At the
	-- horizontal center the derivative is zero; toward either edge it changes
	-- smoothly and its sign also correctly depends on the row's vertical side.
	local horizontal_slope_y = -2 * vertical_curve * dy * u / half_width * vertical_fit
	local horizontal_slope_x = (1 + horizontal_curve * v * v) * horizontal_fit
	-- Use one horizontal-row tangent for every primitive. A widget's first pass
	-- can be a tall divider, especially on the right-hand weapon and objective
	-- panels; choosing the tangent from its aspect ratio made those widgets use
	-- a different curve from the left-hand HUD. Rotation2D maps HUD Y onto
	-- matrix Z, whose visible rotation direction is opposite to HUD XY.
	local angle = -math.atan2(horizontal_slope_y, horizontal_slope_x)

	-- Rotation enlarges a rectangle's axis-aligned bounds. Clamp the transformed
	-- center using those rotated extents so corners, dividers, and text do not
	-- disappear even at high curve strengths.
	local cosine = math.abs(math.cos(angle))
	local sine = math.abs(math.sin(angle))
	local extent_x = cosine * primitive_width * 0.5 + sine * primitive_height * 0.5
	local extent_y = sine * primitive_width * 0.5 + cosine * primitive_height * 0.5
	local min_center_x = extent_x + HUD_EDGE_MARGIN
	local max_center_x = width - extent_x - HUD_EDGE_MARGIN
	local min_center_y = extent_y + HUD_EDGE_MARGIN
	local max_center_y = height - extent_y - HUD_EDGE_MARGIN

	if min_center_x <= max_center_x then
		mapped_center_x = math.clamp(mapped_center_x, min_center_x, max_center_x)
	else
		mapped_center_x = half_width
	end

	if min_center_y <= max_center_y then
		mapped_center_y = math.clamp(mapped_center_y, min_center_y, max_center_y)
	else
		mapped_center_y = half_height
	end

	local offset_x = mapped_center_x - primitive_center_x
	local offset_y = mapped_center_y - primitive_center_y

	return angle, offset_x, offset_y
end

local function widget_container_node(renderer, widget)
	local scenegraph = renderer and renderer.ui_scenegraph
	local scenegraph_id = widget and widget.scenegraph_id

	if not scenegraph or not scenegraph_id then
		return nil, nil
	end

	-- Find the first container below the scenegraph root. Every widget in the
	-- same HUD container resolves to this node, so they all receive one stable
	-- transform without knowing the element's class or widget names.
	local node = rawget(scenegraph, scenegraph_id)

	while node and node.parent do
		local parent = rawget(scenegraph, node.parent)

		if not parent or not parent.parent then
			break
		end

		node = parent
	end

	-- Dynamic HUD contents are often attached to a zero-sized root pivot and
	-- positioned later through widget offsets. Such a pivot is not a visual
	-- container, so let it inherit the largest real top-level container in the
	-- same scenegraph. This keeps moving contents and their surrounding frame on
	-- one transform without relying on element or widget names.
	local node_size = node and node.size

	if node_size and ((node_size[1] or 0) <= 0 or (node_size[2] or 0) <= 0) then
		local largest_node
		local largest_area = 0

		for _, candidate in pairs(scenegraph) do
			if type(candidate) == "table" and candidate.parent then
				local parent = rawget(scenegraph, candidate.parent)
				local candidate_size = candidate.size

				if parent and not parent.parent and candidate_size then
					local area = math.max(candidate_size[1] or 0, 0) * math.max(candidate_size[2] or 0, 0)

					if area > largest_area then
						largest_node = candidate
						largest_area = area
					end
				end
			end
		end

		node = largest_node or node
	end

	return scenegraph, node
end

local function same_vertical_column(first, second)
	if first.horizontal_alignment ~= second.horizontal_alignment or first.vertical_alignment ~= second.vertical_alignment then
		return false
	end

	local first_position = first.world_position
	local second_position = second.world_position
	local first_size = first.size
	local second_size = second.size

	if not first_position or not second_position or not first_size or not second_size then
		return false
	end

	local alignment = first.horizontal_alignment
	local first_edge
	local second_edge

	if alignment == "left" then
		first_edge = first_position[1]
		second_edge = second_position[1]
	elseif alignment == "right" then
		first_edge = first_position[1] + first_size[1]
		second_edge = second_position[1] + second_size[1]
	else
		return false
	end

	return math.abs(first_edge - second_edge) <= 4
end

local function widget_scenegraph_anchor(renderer, widget)
	local scenegraph, node = widget_container_node(renderer, widget)
	local world_position = node and node.world_position
	local node_size = node and node.size

	if not world_position or not node_size then
		return nil
	end

	local containers = recent_container_nodes[scenegraph]

	if not containers then
		containers = setmetatable({}, { __mode = "k" })
		recent_container_nodes[scenegraph] = containers
	end

	containers[node] = hud_frame

	-- Separate element scenegraphs can still describe one visual stack. Join
	-- recently drawn containers when they occupy the same left/right column and
	-- their vertical bounds are adjacent. This is based entirely on layout, not
	-- element or widget names.
	local min_x = world_position[1]
	local min_y = world_position[2]
	local max_x = min_x + node_size[1]
	local max_y = min_y + node_size[2]
	local max_gap = math.max(16, math.min(node_size[2] * 0.75, 64))
	local changed = true

	while changed do
		changed = false

		for candidate_scenegraph, candidate_nodes in pairs(recent_container_nodes) do
			if hud_scenegraphs[candidate_scenegraph] then
				for candidate, last_seen_frame in pairs(candidate_nodes) do
					if last_seen_frame >= hud_frame - 1 and same_vertical_column(node, candidate) then
						local candidate_position = candidate.world_position
						local candidate_size = candidate.size
						local candidate_min_y = candidate_position[2]
						local candidate_max_y = candidate_min_y + candidate_size[2]

						if candidate_max_y >= min_y - max_gap and candidate_min_y <= max_y + max_gap then
							local candidate_min_x = candidate_position[1]
							local candidate_max_x = candidate_min_x + candidate_size[1]
							local next_min_x = math.min(min_x, candidate_min_x)
							local next_min_y = math.min(min_y, candidate_min_y)
							local next_max_x = math.max(max_x, candidate_max_x)
							local next_max_y = math.max(max_y, candidate_max_y)

							if next_min_x ~= min_x or next_min_y ~= min_y or next_max_x ~= max_x or next_max_y ~= max_y then
								min_x = next_min_x
								min_y = next_min_y
								max_x = next_max_x
								max_y = next_max_y
								changed = true
							end
						end
					end
				end
			end
		end
	end

	local scale = renderer.scale or 1
	local position = Vector3(min_x * scale, min_y * scale, world_position[3] or 0)
	local size = Vector3((max_x - min_x) * scale, (max_y - min_y) * scale, 0)
	local angle, offset_x, offset_y = hud_curve(renderer, position, size)

	if not angle then
		return nil
	end

	return {
		position = position,
		size = size,
		angle = angle,
		offset_x = offset_x,
		offset_y = offset_y,
	}
end

-- Drawing transforms --------------------------------------------------------

local function create_graphic_anchor(position, size, angle, offset_x, offset_y)
	return {
		position = Vector3(position[1], position[2], position[3] or 0),
		size = Vector3(size[1], size[2], size[3] or 0),
		angle = angle,
		offset_x = offset_x,
		offset_y = offset_y,
	}
end

local function ensure_graphic_anchor(position, size, angle, offset_x, offset_y)
	if not widget_graphic_anchor then
		widget_graphic_anchor = create_graphic_anchor(position, size, angle, offset_x, offset_y)
	end

	return widget_graphic_anchor
end

local function anchor_pivot(anchor, position, scale)
	scale = scale or 1

	return Vector2(
		(anchor.position[1] + anchor.size[1] * 0.5 - position[1]) / scale,
		(anchor.position[2] + anchor.size[2] * 0.5 - position[2]) / scale
	)
end

local function offset_position(position, offset_x, offset_y, scale)
	scale = scale or 1

	return Vector3(
		position[1] + offset_x / scale,
		position[2] + offset_y / scale,
		position[3] or 0
	)
end

local function rotation_transform(position, angle, pivot)
	local transform = Rotation2D(Vector3.zero(), angle, pivot)
	local translation = Matrix4x4.translation(transform)

	translation.x = translation.x + position[1]
	translation.z = translation.z + position[2]
	Matrix4x4.set_translation(transform, translation)

	return transform
end

local function bitmap_transform(position, anchor)
	local pivot = anchor_pivot(anchor, position)
	local render_position = offset_position(position, anchor.offset_x, anchor.offset_y)

	return rotation_transform(render_position, anchor.angle, pivot)
end

local text_3d_options = {}

local function native_text_3d_options(options)
	table.clear(text_3d_options)

	if not options then
		return nil
	end

	local horizontal_alignment = options.horizontal_alignment

	if horizontal_alignment == Gui.HorizontalAlignCenter then
		text_3d_options[#text_3d_options + 1] = "horizontal_align_center"
	elseif horizontal_alignment == Gui.HorizontalAlignRight then
		text_3d_options[#text_3d_options + 1] = "horizontal_align_right"
	else
		text_3d_options[#text_3d_options + 1] = "horizontal_align_left"
	end

	local vertical_alignment = options.vertical_alignment

	if vertical_alignment == Gui.VerticalAlignCenter then
		text_3d_options[#text_3d_options + 1] = "vertical_align_center"
	elseif vertical_alignment == Gui.VerticalAlignBottom then
		text_3d_options[#text_3d_options + 1] = "vertical_align_bottom"
	else
		text_3d_options[#text_3d_options + 1] = "vertical_align_top"
	end

	if type(options.line_spacing) == "number" then
		text_3d_options[#text_3d_options + 1] = "line_spacing"
		text_3d_options[#text_3d_options + 1] = options.line_spacing
	end

	if type(options.character_spacing) == "number" then
		text_3d_options[#text_3d_options + 1] = "character_spacing"
		text_3d_options[#text_3d_options + 1] = options.character_spacing
	end

	if options.shadow then
		text_3d_options[#text_3d_options + 1] = "shadow"
	end

	if options.outline then
		text_3d_options[#text_3d_options + 1] = "outline"
	end

	return text_3d_options
end

local function text_curve_parameters(renderer, text, font_size, font_type, position, size, options)
	local anchor = widget_graphic_anchor

	if anchor then
		return anchor.angle,
			anchor.offset_x,
			anchor.offset_y,
			anchor.position[1] + anchor.size[1] * 0.5 - position[1],
			anchor.position[2] + anchor.size[2] * 0.5 - position[2]
	end

	-- Measuring once preserves the renderer's native kerning, rich text,
	-- Unicode shaping, and multiline layout.
	local width, height, minimum = UIRenderer.text_size(renderer, text, font_type, font_size, size, options, false)
	local minimum_x = minimum and minimum[1] or 0
	local minimum_y = minimum and minimum[2] or 0

	width = tonumber(width) or (size and size[1]) or font_size
	height = tonumber(height) or (size and size[2]) or font_size

	local bounds_position = Vector3(position[1] + minimum_x, position[2] + minimum_y, position[3] or 0)
	local bounds_size = Vector3(width, height, 0)
	local angle, offset_x, offset_y = hud_curve(renderer, bounds_position, bounds_size)

	return angle, offset_x, offset_y, minimum_x + width * 0.5, minimum_y + height * 0.5
end

local function text_rotation_transform(position, angle, offset_x, offset_y, pivot_x, pivot_y)
	-- Rotation2D renders HUD Y through matrix Z. Text uses the matrix XY plane,
	-- so it needs the opposite angle to match the other HUD primitives.
	local text_angle = -angle
	local cosine = math.cos(text_angle)
	local sine = math.sin(text_angle)

	return Matrix4x4.from_elements(
		cosine, sine, 0,
		-sine, cosine, 0,
		0, 0, 1,
		position[1] + offset_x + pivot_x * (1 - cosine) + pivot_y * sine,
		position[2] + offset_y + pivot_y * (1 - cosine) - pivot_x * sine,
		0
	)
end

-- HUD pass scoping ----------------------------------------------------------

-- UIWidget.draw is used by every screen and menu in the game. Hooking it
-- globally makes the curve mod enter the hook chain for unrelated UI. HUD
-- elements already draw inside a UIRenderer begin/end pass, so install this
-- wrapper only for the duration of a curved HUD pass instead.
local scoped_ui_widget_draw

local function draw_curved_hud_widget(widget, ...)
	local previous_widget_graphic_anchor = widget_graphic_anchor
	local was_drawing_widget = drawing_widget
	local was_drawing_corner_anchored_widget = drawing_corner_anchored_widget
	local was_drawing_screen_centered_widget = drawing_screen_centered_widget
	local renderer = select(1, ...)
	local draw_widget = scoped_ui_widget_draw

	drawing_widget = true
	drawing_corner_anchored_widget, drawing_screen_centered_widget = classify_widget_anchor(widget, renderer)

	-- Dynamic child HUD elements can inherit their final corner alignment after
	-- construction without invoking the base layout hook. The widget ancestry
	-- is authoritative at draw time, so promote its scenegraph immediately.
	if drawing_corner_anchored_widget
		and renderer
		and renderer.ui_scenegraph
		and not horizontally_centered_scenegraphs[renderer.ui_scenegraph]
	then
		corner_curve_scenegraphs[renderer.ui_scenegraph] = true
	end

	widget_graphic_anchor = drawing_hud_element_group and drawing_corner_anchored_widget and widget_scenegraph_anchor(renderer, widget) or nil

	local result = draw_widget(widget, ...)

	widget_graphic_anchor = previous_widget_graphic_anchor
	drawing_widget = was_drawing_widget
	drawing_corner_anchored_widget = was_drawing_corner_anchored_widget
	drawing_screen_centered_widget = was_drawing_screen_centered_widget

	return result
end

mod:hook(HudElementBase, "init", function(func, self, ...)
	func(self, ...)
	refresh_hud_element_anchor_profile(self)
end)

mod:hook(HudElementBase, "set_scenegraph_position", function(func, self, ...)
	local result = func(self, ...)

	-- Some HUD elements are created with a neutral alignment and moved into a
	-- corner later. Reclassify after that layout change rather than relying on
	-- the element's construction-time anchor.
	refresh_hud_element_anchor_profile(self)

	return result
end)

mod:hook(UIRenderer, "begin_pass", function(func, self, ui_scenegraph, ...)
	local stack = renderer_group_stacks[self]

	if not stack then
		stack = {}
		renderer_group_stacks[self] = stack
	end

	stack[#stack + 1] = {
		grouped = drawing_hud_element_group,
		anchor = widget_graphic_anchor,
		ui_widget_draw = UIWidget.draw,
		scoped_ui_widget_draw = scoped_ui_widget_draw,
	}

	local result = func(self, ui_scenegraph, ...)

	drawing_hud_element_group = mod:is_enabled() and hud_scenegraphs[ui_scenegraph] == true

	if drawing_hud_element_group then
		widget_graphic_anchor = nil

		if UIWidget.draw ~= draw_curved_hud_widget then
			scoped_ui_widget_draw = UIWidget.draw
			UIWidget.draw = draw_curved_hud_widget
		end
	elseif UIWidget.draw == draw_curved_hud_widget then
		UIWidget.draw = scoped_ui_widget_draw
		scoped_ui_widget_draw = nil
	end

	return result
end)

mod:hook(UIRenderer, "end_pass", function(func, self, ...)
	local result = func(self, ...)
	local stack = renderer_group_stacks[self]
	local state = stack and stack[#stack]

	if state then
		stack[#stack] = nil
		UIWidget.draw = state.ui_widget_draw
		scoped_ui_widget_draw = state.scoped_ui_widget_draw
		drawing_hud_element_group = state.grouped
		widget_graphic_anchor = state.anchor
	else
		drawing_hud_element_group = false
		widget_graphic_anchor = nil
	end

	return result
end)

mod.update = function(dt)
	if not mod:is_enabled() or not gameplay_hooks_enabled then
		return
	end

	hud_frame = hud_frame + 1
	update_camera_lag(dt)

	-- Camera sway requires retained HUD elements to be redrawn with their
	-- current transforms.
	for element in pairs(hud_elements) do
		if hud_scenegraphs[element._ui_scenegraph] then
			element:set_dirty()
		end
	end
end

mod:hook(HudElementPlayerBuffs, "_draw_widgets", function(func, self, ...)
	-- Buff entries are intentionally independent: each icon follows the curve
	-- from its own horizontal position instead of making the whole row rigid.
	local was_drawing_hud_element_group = drawing_hud_element_group
	local previous_widget_graphic_anchor = widget_graphic_anchor
	local was_suppressing_buff_curve = buff_curve_suppressed

	drawing_hud_element_group = false
	widget_graphic_anchor = nil
	buff_curve_suppressed = mod:get("curve_buff_hud") == false

	local result = func(self, ...)

	drawing_hud_element_group = was_drawing_hud_element_group
	widget_graphic_anchor = previous_widget_graphic_anchor
	buff_curve_suppressed = was_suppressing_buff_curve

	return result
end)

-- Curved renderer primitives ------------------------------------------------

mod:hook(UIRenderer, "script_draw_bitmap", function(func, self, material, position, size, color, retained_id)
	local angle, offset_x, offset_y = hud_curve(self, position, size)

	if not angle then
		return func(self, material, position, size, color, retained_id)
	end

	local anchor = ensure_graphic_anchor(position, size, angle, offset_x, offset_y)
	local transform = bitmap_transform(position, anchor)
	local layer = position[3] or 0

	return UIRenderer.script_draw_bitmap_3d(self, material, transform, nil, layer, size, color, nil, retained_id)
end)

mod:hook(UIRenderer, "script_draw_bitmap_uv", function(func, self, material, position, size, uvs, color, retained_id)
	local angle, offset_x, offset_y = hud_curve(self, position, size)

	if not angle then
		return func(self, material, position, size, uvs, color, retained_id)
	end

	local anchor = ensure_graphic_anchor(position, size, angle, offset_x, offset_y)
	local transform = bitmap_transform(position, anchor)
	local layer = position[3] or 0

	return UIRenderer.script_draw_bitmap_3d(self, material, transform, nil, layer, size, color, uvs, retained_id)
end)

mod:hook(UIRenderer, "script_draw_text", function(func, self, text, font_size, font_type, position, size, color, options, retained_id)
	if type(text) == "number" then
		text = tostring(text)
	elseif type(text) ~= "string" or text == "" then
		return func(self, text, font_size, font_type, position, size, color, options, retained_id)
	end

	local angle, offset_x, offset_y, pivot_x, pivot_y = text_curve_parameters(
		self,
		text,
		font_size,
		font_type,
		position,
		size,
		options
	)

	if not angle then
		return func(self, text, font_size, font_type, position, size, color, options, retained_id)
	end

	local transform = text_rotation_transform(position, angle, offset_x, offset_y, pivot_x, pivot_y)

	return UIRenderer.script_draw_text_3d(
		self,
		text,
		font_size,
		font_type,
		transform,
		nil,
		position[3] or 0,
		size,
		color,
		native_text_3d_options(options),
		-- Immediate text is intentional: it follows the changing sway transform
		-- without relying on an incompatible retained 2D text ID.
		nil
	)
end)

mod:hook(UIRenderer, "draw_rect", function(func, self, position, size, color, retained_id)
	local scale = self.scale or 1
	local scaled_position = Vector3(position[1] * scale, position[2] * scale, position[3] or 0)
	local scaled_size = Vector3(size[1] * scale, size[2] * scale, size[3] or 0)

	-- Every graphical pass in one widget shares the transform established by
	-- its first graphical pass. This preserves the widget's internal layout.
	if widget_graphic_anchor then
		local anchor = widget_graphic_anchor
		local pivot = anchor_pivot(anchor, scaled_position, scale)
		local render_position = offset_position(position, anchor.offset_x, anchor.offset_y, scale)

		return UIRenderer.draw_rect_rotated(self, size, render_position, anchor.angle, pivot, color)
	end

	local angle, offset_x, offset_y = hud_curve(self, scaled_position, scaled_size)

	if not angle then
		return func(self, position, size, color, retained_id)
	end

	ensure_graphic_anchor(scaled_position, scaled_size, angle, offset_x, offset_y)

	local render_position = offset_position(position, offset_x, offset_y, scale)
	local pivot = Vector2(size[1] * 0.5, size[2] * 0.5)

	return UIRenderer.draw_rect_rotated(self, size, render_position, angle, pivot, color)
end)


-- Gameplay lifecycle --------------------------------------------------------

local function gameplay_scene_is_active()
	return not not (Managers.state and Managers.state.game_mode)
end

local function reset_draw_scope()
	if UIWidget.draw == draw_curved_hud_widget and scoped_ui_widget_draw then
		UIWidget.draw = scoped_ui_widget_draw
	end

	scoped_ui_widget_draw = nil
	widget_graphic_anchor = nil
	drawing_widget = false
	drawing_corner_anchored_widget = false
	drawing_screen_centered_widget = false
	drawing_hud_element_group = false
	buff_curve_suppressed = false
	reset_camera_lag()
end

local function set_gameplay_hooks_enabled(enabled, force)
	enabled = not not enabled

	if not force and gameplay_hooks_enabled == enabled then
		return
	end

	gameplay_hooks_enabled = enabled

	if not enabled then
		reset_draw_scope()
	end

	if enabled then
		mod:enable_all_hooks()
	else
		mod:disable_all_hooks()
	end
end

-- DMF events remain available when this mod's hooks are disabled, so they can
-- restore every hook before StateGameplay initializes the HUD.
mod.on_game_state_changed = function(status, state_name)
	if state_name == "StateGameplay" then
		set_gameplay_hooks_enabled(status == "enter", true)
	end
end

mod.on_all_mods_loaded = function()
	set_gameplay_hooks_enabled(gameplay_scene_is_active(), true)
end

mod.on_enabled = function()
	-- DMF re-enables every hook when the mod is toggled on, so force the
	-- gameplay-only hooks back off when enabling from a menu.
	set_gameplay_hooks_enabled(gameplay_scene_is_active(), true)
end

mod.on_disabled = function()
	set_gameplay_hooks_enabled(false, true)
end

-- Avoid paying for renderer hooks during the menu frames before the first
-- lifecycle callback is received.
set_gameplay_hooks_enabled(gameplay_scene_is_active(), true)
