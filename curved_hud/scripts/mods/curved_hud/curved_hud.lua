local mod = get_mod("curved_hud")

local HudElementBase = require("scripts/ui/hud/elements/hud_element_base")
local HudElementPlayerPanelBase = require("scripts/ui/hud/elements/player_panel_base/hud_element_player_panel_base")
local HudElementPlayerBuffs = require("scripts/ui/hud/elements/player_buffs/hud_element_player_buffs_polling")
local UIRenderer = require("scripts/managers/ui/ui_renderer")
local UIWidget = require("scripts/managers/ui/ui_widget")

local _excluded_element_names = {
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
    ConstantElementSoftwareCursor = true
}

local hud_scenegraphs = setmetatable({}, { __mode = "k" })
local hud_elements = setmetatable({}, { __mode = "k" })
local player_name_widgets = setmetatable({}, { __mode = "k" })
local player_name_values = setmetatable({}, { __mode = "k" })
local panel_numeric_widgets = setmetatable({}, { __mode = "k" })
local drawing_player_name = nil
local drawing_panel_numeric = false
local widget_graphic_anchor = nil
local drawing_center_anchored_widget = false
local drawing_hud_element_group = false
local renderer_group_stacks = setmetatable({}, { __mode = "k" })
local recent_container_nodes = setmetatable({}, { __mode = "k" })
local hud_frame = 0
local CAMERA_FOLLOW_DELAY_MS = 20
---@type number?
local smoothed_camera_yaw = nil
---@type number?
local smoothed_camera_pitch = nil
---@type number?
local smoothed_camera_x = nil
---@type number?
local smoothed_camera_y = nil
---@type number?
local smoothed_camera_z = nil
local camera_lag_x = 0.0
local camera_lag_y = 0.0

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

local function update_camera_lag(dt)
	if not dt or dt <= 0 then
		reset_camera_lag()
		return
	end

	local player_manager = Managers.player
	local camera_manager = Managers.state and Managers.state.camera

	-- Mod updates begin before the game has created its connection and camera
	-- managers. PlayerManager:local_player calls Network.peer_id directly and
	-- can therefore crash during these startup frames.
	if not player_manager or not camera_manager then
		reset_camera_lag()
		return
	end

	local player = player_manager:local_player_safe(1)
	local viewport_name = player and player.viewport_name

	if not viewport_name or not camera_manager:has_camera(viewport_name) then
		reset_camera_lag()
		return
	end

	local rotation = camera_manager:camera_rotation(viewport_name)
	local position = camera_manager:camera_position(viewport_name)

	if not rotation or not Quaternion.is_valid(rotation) or not position or not Vector3.is_valid(position) then
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
	if math.abs(yaw_delta) > math.degrees_to_radians(45) or math.abs(pitch_delta) > math.degrees_to_radians(45) or position_delta_distance > 5 then
		set_camera_lag_origin(yaw, pitch, position_x, position_y, position_z)
		return
	end

	local delay_seconds = CAMERA_FOLLOW_DELAY_MS * 0.001
	local follow_fraction = 1 - math.exp(-dt / delay_seconds)

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
	local world_pixels_per_meter = height * 0.08
	local target_lag_x = lag_yaw * width * 0.55 + lag_right * world_pixels_per_meter
	local target_lag_y = -lag_pitch * height * 0.7 - lag_up * world_pixels_per_meter
	local movement_distance = math.sqrt(target_lag_x * target_lag_x + target_lag_y * target_lag_y)
	local limited_lag_x = 0.0
	local limited_lag_y = 0.0

	if movement_limit <= 0 then
		camera_lag_x = 0.0
		camera_lag_y = 0.0
		return
	elseif movement_distance > movement_limit then
		local limit_scale = movement_limit / movement_distance

		limited_lag_x = target_lag_x * limit_scale
		limited_lag_y = target_lag_y * limit_scale
	else
		limited_lag_x = target_lag_x
		limited_lag_y = target_lag_y
	end

	-- Smooth the final screen-space movement as well as the tracked camera
	-- angles. This removes the rigid start/stop response without making the
	-- configured delay substantially longer.
	local movement_smoothing_time = math.max(delay_seconds * 0.5, 0.05)
	local movement_fraction = 1 - math.exp(-dt / movement_smoothing_time)

	camera_lag_x = camera_lag_x + (limited_lag_x - camera_lag_x) * movement_fraction
	camera_lag_y = camera_lag_y + (limited_lag_y - camera_lag_y) * movement_fraction

	local smoothed_distance = math.sqrt(camera_lag_x * camera_lag_x + camera_lag_y * camera_lag_y)

	if smoothed_distance > movement_limit then
		local limit_scale = movement_limit / smoothed_distance

		camera_lag_x = camera_lag_x * limit_scale
		camera_lag_y = camera_lag_y * limit_scale
	end
end

local function is_center_anchored_widget(widget, renderer)
	local scenegraph = renderer and renderer.ui_scenegraph
	local scenegraph_id = widget and widget.scenegraph_id

	while scenegraph and scenegraph_id do
		local node = rawget(scenegraph, scenegraph_id)

		if not node then
			break
		end

		local parent_id = node.parent
		local parent = parent_id and rawget(scenegraph, parent_id)

		-- Only treat alignment as screen-centering when this node is anchored
		-- directly below the scenegraph root. Child nodes commonly use center /
		-- center to align inside an edge HUD slot and must inherit that slot's
		-- curve.
		if parent and not parent.parent and node.horizontal_alignment == "center" and node.vertical_alignment == "center" then
			return true
		end

		scenegraph_id = parent_id
	end

	return false
end

local function hud_curve(renderer, position, size, force_hud_element)
	if drawing_center_anchored_widget or not mod:is_enabled() or not force_hud_element and not hud_scenegraphs[renderer.ui_scenegraph] then
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
	local strength = math.degrees_to_radians(mod:get("curve_strength") or 0)
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
	local margin = 2
	local min_center_x = extent_x + margin
	local max_center_x = width - extent_x - margin
	local min_center_y = extent_y + margin
	local max_center_y = height - extent_y - margin

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
	local angle, offset_x, offset_y = hud_curve(renderer, position, size, true)

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

local function local_rotation_transform(position, size, angle)
	local transform = Rotation2D(Vector3.zero(), angle, Vector2(size[1] * 0.5, size[2] * 0.5))
	local translation = Matrix4x4.translation(transform)

	translation.x = translation.x + position[1]
	translation.z = translation.z + position[2]
	Matrix4x4.set_translation(transform, translation)

	return transform
end

local function grouped_position(position, anchor)
	local pivot = Vector2(
		anchor.position[1] + anchor.size[1] * 0.5 - position[1],
		anchor.position[2] + anchor.size[2] * 0.5 - position[2]
	)
	local render_position = Vector3(position[1] + anchor.offset_x, position[2] + anchor.offset_y, position[3] or 0)
	local transform = Rotation2D(Vector3.zero(), anchor.angle, pivot)
	local translation = Matrix4x4.translation(transform)

	translation.x = translation.x + render_position[1]
	translation.z = translation.z + render_position[2]
	Matrix4x4.set_translation(transform, translation)

	local transformed = Matrix4x4.transform(transform, Vector3.zero())

	return Vector3(transformed[1], transformed[3], position[3] or 0)
end

local function formatted_characters(text, base_font_size, base_color, scale)
	local characters = {}
	local current_font_size = base_font_size
	local current_color = base_color
	local cursor = 1

	local function append_visible(value)
		for character in string.gmatch(value, "[%z\1-\127\194-\244][\128-\191]*") do
			characters[#characters + 1] = {
				text = character,
				font_size = current_font_size,
				color = current_color,
			}
		end
	end

	while cursor <= #text do
		local tag_start, tag_end, directive = string.find(text, "{#(.-)}", cursor)

		if not tag_start then
			append_visible(string.sub(text, cursor))
			break
		end

		if tag_start > cursor then
			append_visible(string.sub(text, cursor, tag_start - 1))
		end

		local red, green, blue = string.match(directive, "^color%((%d+),(%d+),(%d+)%)$")
		local inline_size = string.match(directive, "^size%(([%d%.]+)%)$")

		if red then
			current_color = Color(base_color and base_color[1] or 255, tonumber(red), tonumber(green), tonumber(blue))
		elseif inline_size then
			current_font_size = math.max(tonumber(inline_size) * scale, 1)
		elseif string.match(directive, "^reset%(%)$") then
			current_font_size = base_font_size
			current_color = base_color
		end

		cursor = tag_end + 1
	end

	return characters
end

mod:hook(HudElementBase, "init", function(func, self, ...)
	func(self, ...)

	if not _excluded_element_names[self.__class_name] then
		hud_scenegraphs[self._ui_scenegraph] = true
		hud_elements[self] = true
	end

	local widgets_by_name = self._widgets_by_name

	if widgets_by_name and widgets_by_name.ability_bar and not widgets_by_name.ability_bar_widget then
		widgets_by_name.ability_bar_widget = widgets_by_name.ability_bar
	end
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
	}

	local result = func(self, ui_scenegraph, ...)

	drawing_hud_element_group = mod:is_enabled() and hud_scenegraphs[ui_scenegraph] == true

	if drawing_hud_element_group then
		widget_graphic_anchor = nil
	end

	return result
end)

mod:hook(UIRenderer, "end_pass", function(func, self, ...)
	local result = func(self, ...)
	local stack = renderer_group_stacks[self]
	local state = stack and stack[#stack]

	if state then
		stack[#stack] = nil
		drawing_hud_element_group = state.grouped
		widget_graphic_anchor = state.anchor
	else
		drawing_hud_element_group = false
		widget_graphic_anchor = nil
	end

	return result
end)

mod.update = function(dt)
	hud_frame = hud_frame + 1

	if not mod:is_enabled() then
		reset_camera_lag()
		return
	end

	update_camera_lag(dt)

	-- Match the working player-name path: keep every gameplay HUD widget live
	-- so its individually submitted glyphs are redrawn instead of relying on a
	-- retained ID belonging to the original whole string.
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

	drawing_hud_element_group = false
	widget_graphic_anchor = nil

	local result = func(self, ...)

	drawing_hud_element_group = was_drawing_hud_element_group
	widget_graphic_anchor = previous_widget_graphic_anchor

	return result
end)

mod:hook(HudElementPlayerPanelBase, "_draw_widgets", function(func, self, ...)
	local widgets_by_name = self._widgets_by_name
	local player_name = widgets_by_name and widgets_by_name.player_name

	-- NumericUI  has a typo in its panel destroy hook: it checks
	-- `ability_bar` but then accesses `ability_bar_widget`. Supply the expected
	-- alias without replacing or modifying NumericUI's actual widget.
	if widgets_by_name and widgets_by_name.ability_bar and not widgets_by_name.ability_bar_widget then
		widgets_by_name.ability_bar_widget = widgets_by_name.ability_bar
	end

	if player_name then
		player_name_widgets[player_name] = true
		player_name_values[player_name] = player_name.content and player_name.content.text or self._current_player_name
		player_name.dirty = true
	end

	for _, widget_name in ipairs({ "health_text", "toughness_text", "bonus_toughness_text" }) do
		local widget = widgets_by_name and widgets_by_name[widget_name]

		if widget then
			panel_numeric_widgets[widget] = true
		end
	end

	return func(self, ...)
end)

mod:hook(UIWidget, "draw", function(func, widget, ...)
	local previous_player_name = drawing_player_name
	local was_drawing_panel_numeric = drawing_panel_numeric
	local previous_widget_graphic_anchor = widget_graphic_anchor
	local was_drawing_center_anchored_widget = drawing_center_anchored_widget
	local renderer = select(1, ...)

	drawing_center_anchored_widget = is_center_anchored_widget(widget, renderer)
	widget_graphic_anchor = drawing_hud_element_group and not drawing_center_anchored_widget and widget_scenegraph_anchor(renderer, widget) or nil

	if player_name_widgets[widget] then
		drawing_player_name = player_name_values[widget]
	end

	if panel_numeric_widgets[widget] then
		drawing_panel_numeric = true
	end

	local result = func(widget, ...)
	drawing_player_name = previous_player_name
	drawing_panel_numeric = was_drawing_panel_numeric

	widget_graphic_anchor = previous_widget_graphic_anchor
	drawing_center_anchored_widget = was_drawing_center_anchored_widget
	return result
end)

mod:hook(UIRenderer, "script_draw_bitmap", function(func, self, material, position, size, color, retained_id)
	local angle, offset_x, offset_y = hud_curve(self, position, size)

	if not angle then
		return func(self, material, position, size, color, retained_id)
	end

	if widget_graphic_anchor then
		local anchor = widget_graphic_anchor
		local pivot = Vector2(
			anchor.position[1] + anchor.size[1] * 0.5 - position[1],
			anchor.position[2] + anchor.size[2] * 0.5 - position[2]
		)
		local render_position = Vector3(position[1] + anchor.offset_x, position[2] + anchor.offset_y, position[3] or 0)
		local transform = Rotation2D(Vector3.zero(), anchor.angle, pivot)
		local translation = Matrix4x4.translation(transform)

		translation.x = translation.x + render_position[1]
		translation.z = translation.z + render_position[2]
		Matrix4x4.set_translation(transform, translation)

		return UIRenderer.script_draw_bitmap_3d(self, material, transform, nil, position[3] or 0, size, color, nil, retained_id)
	else
		widget_graphic_anchor = {
			position = Vector3(position[1], position[2], position[3] or 0),
			size = Vector3(size[1], size[2], size[3] or 0),
			angle = angle,
			offset_x = offset_x,
			offset_y = offset_y,
		}
	end

	local render_position = Vector3(position[1] + offset_x, position[2] + offset_y, position[3] or 0)
	local transform = local_rotation_transform(render_position, size, angle)
	local layer = position[3] or 0

	return UIRenderer.script_draw_bitmap_3d(self, material, transform, nil, layer, size, color, nil, retained_id)
end)

mod:hook(UIRenderer, "script_draw_bitmap_uv", function(func, self, material, position, size, uvs, color, retained_id)
	local angle, offset_x, offset_y = hud_curve(self, position, size)

	if not angle then
		return func(self, material, position, size, uvs, color, retained_id)
	end

	if widget_graphic_anchor then
		local anchor = widget_graphic_anchor
		local pivot = Vector2(
			anchor.position[1] + anchor.size[1] * 0.5 - position[1],
			anchor.position[2] + anchor.size[2] * 0.5 - position[2]
		)
		local render_position = Vector3(position[1] + anchor.offset_x, position[2] + anchor.offset_y, position[3] or 0)
		local transform = Rotation2D(Vector3.zero(), anchor.angle, pivot)
		local translation = Matrix4x4.translation(transform)

		translation.x = translation.x + render_position[1]
		translation.z = translation.z + render_position[2]
		Matrix4x4.set_translation(transform, translation)

		return UIRenderer.script_draw_bitmap_3d(self, material, transform, nil, position[3] or 0, size, color, uvs, retained_id)
	else
		widget_graphic_anchor = {
			position = Vector3(position[1], position[2], position[3] or 0),
			size = Vector3(size[1], size[2], size[3] or 0),
			angle = angle,
			offset_x = offset_x,
			offset_y = offset_y,
		}
	end

	local render_position = Vector3(position[1] + offset_x, position[2] + offset_y, position[3] or 0)
	local transform = local_rotation_transform(render_position, size, angle)
	local layer = position[3] or 0

	return UIRenderer.script_draw_bitmap_3d(self, material, transform, nil, layer, size, color, uvs, retained_id)
end)

mod:hook(UIRenderer, "script_draw_text", function(func, self, text, font_size, font_type, position, size, color, options, retained_id)
	local render_text_position = position
	local render_text_size = size
	local render_text_options = options

	if drawing_panel_numeric and size then
		local text_width = UIRenderer.text_size(self, text, font_type, font_size, nil, options)
		local aligned_x = position[1]
		local alignment = options and options.horizontal_alignment

		if alignment == Gui.HorizontalAlignRight then
			aligned_x = aligned_x + size[1] - text_width
		elseif alignment == Gui.HorizontalAlignCenter then
			aligned_x = aligned_x + (size[1] - text_width) * 0.5
		end

		render_text_position = Vector3(aligned_x, position[2], position[3] or 0)
		render_text_size = Vector3(math.max(text_width + font_size, 1), size[2], size[3] or 0)
		render_text_options = {}

		for key, value in pairs(options or {}) do
			render_text_options[key] = value
		end

		render_text_options.horizontal_alignment = Gui.HorizontalAlignLeft
	end

	local text_size = render_text_size or Vector3.zero()
	local anchor = widget_graphic_anchor
	local angle, text_offset_x, offset_y

	if anchor then
		angle = anchor.angle
	else
		angle, text_offset_x, offset_y = hud_curve(self, render_text_position, text_size)
	end

	if not angle then
		return func(self, text, font_size, font_type, render_text_position, render_text_size, color, render_text_options, retained_id)
	end

	if type(text) == "string" and text ~= "" and not string.find(text, "\n", 1, true) then
		local displayed_text = drawing_player_name or text
		local characters = formatted_characters(displayed_text, font_size, color, self.scale or 1)

		if #characters > 0 then
			local total_width = 0

			for i = 1, #characters do
				local character = characters[i]
				local visible_width, _, _, caret = UIRenderer.text_size(self, character.text, font_type, character.font_size, nil, options)
				local caret_advance = caret and caret[1] or 0

				character.width = math.max(visible_width, caret_advance, character.font_size * 0.35)
				character.spacing = 0
				total_width = total_width + character.width
			end

			local start_x = render_text_position[1]
			local available_width = render_text_size and render_text_size[1] or total_width
			local alignment = render_text_options and render_text_options.horizontal_alignment

			if alignment == Gui.HorizontalAlignCenter then
				start_x = start_x + (available_width - total_width) * 0.5
			elseif alignment == Gui.HorizontalAlignRight then
				start_x = start_x + available_width - total_width
			end

			local character_options = {}

			for key, value in pairs(render_text_options or {}) do
				character_options[key] = value
			end

			character_options.horizontal_alignment = Gui.HorizontalAlignLeft

			local cursor_x = start_x
			local vertical_alignment = render_text_options and render_text_options.vertical_alignment
			local line_height = render_text_size and render_text_size[2] or font_size
			local visible_line_height = math.min(font_size, line_height)
			local line_curve_y = render_text_position[2]

			if vertical_alignment == Gui.VerticalAlignCenter then
				line_curve_y = line_curve_y + (line_height - visible_line_height) * 0.5
			elseif vertical_alignment == Gui.VerticalAlignBottom then
				line_curve_y = line_curve_y + line_height - visible_line_height
			end

			local line_curve_position = Vector3(start_x, line_curve_y, render_text_position[3] or 0)
			local line_curve_size = Vector3(total_width, visible_line_height, 0)
			local line_offset_x = 0.0

			if not anchor then
				local _, computed_line_offset_x = hud_curve(self, line_curve_position, line_curve_size)

				line_offset_x = tonumber(computed_line_offset_x) or 0.0
			end

			for i = 1, #characters do
				local character = characters[i]
				local character_width = character.width
				local character_position = Vector3(cursor_x, render_text_position[2], render_text_position[3] or 0)
				local character_height = render_text_size and render_text_size[2] or character.font_size
				local visible_height = math.min(character.font_size, character_height)
				local curve_y = character_position[2]

				if vertical_alignment == Gui.VerticalAlignCenter then
					curve_y = curve_y + (character_height - visible_height) * 0.5
				elseif vertical_alignment == Gui.VerticalAlignBottom then
					curve_y = curve_y + character_height - visible_height
				end

				local draw_size = Vector3(math.max(available_width, character_width + character.font_size * 2), character_height, 0)
				local curved_position

				if anchor then
					curved_position = grouped_position(character_position, anchor)
				else
					local curve_position = Vector3(character_position[1], curve_y, character_position[3])
					local curve_size = Vector3(character_width, visible_height, 0)
					local _, _, character_offset_y = hud_curve(self, curve_position, curve_size)

					curved_position = Vector3(character_position[1] + line_offset_x, character_position[2] + character_offset_y, character_position[3])
				end

				func(self, character.text, character.font_size, font_type, curved_position, draw_size, character.color, character_options, nil)
				cursor_x = cursor_x + character_width
			end

			return nil
		end
	end

	local render_position = anchor and grouped_position(render_text_position, anchor) or Vector3(
		render_text_position[1] + text_offset_x,
		render_text_position[2] + offset_y,
		render_text_position[3] or 0
	)

	return func(self, text, font_size, font_type, render_position, render_text_size, color, render_text_options, retained_id)
end)

mod:hook(UIRenderer, "draw_rect", function(func, self, position, size, color, retained_id)
	if drawing_center_anchored_widget then
		return func(self, position, size, color, retained_id)
	end

	local scale = self.scale or 1
	local scaled_position = Vector3(position[1] * scale, position[2] * scale, position[3] or 0)
	local scaled_size = Vector3(size[1] * scale, size[2] * scale, size[3] or 0)

	-- Every graphical pass in one widget shares the transform established by
	-- its first graphical pass. This preserves the widget's internal layout.
	if widget_graphic_anchor then
		local anchor = widget_graphic_anchor
		local pivot = Vector2(
			(anchor.position[1] + anchor.size[1] * 0.5 - scaled_position[1]) / scale,
			(anchor.position[2] + anchor.size[2] * 0.5 - scaled_position[2]) / scale
		)
		local render_position = Vector3(
			position[1] + anchor.offset_x / scale,
			position[2] + anchor.offset_y / scale,
			position[3] or 0
		)

		return UIRenderer.draw_rect_rotated(self, size, render_position, anchor.angle, pivot, color)
	end

	local angle, offset_x, offset_y = hud_curve(self, scaled_position, scaled_size)

	if not angle then
		return func(self, position, size, color, retained_id)
	end

	if not widget_graphic_anchor then
		widget_graphic_anchor = {
			position = scaled_position,
			size = scaled_size,
			angle = angle,
			offset_x = offset_x,
			offset_y = offset_y,
		}
	end

	local render_position = Vector3(position[1] + offset_x / scale, position[2] + offset_y / scale, position[3] or 0)
	local pivot = Vector2(size[1] * 0.5, size[2] * 0.5)

	return UIRenderer.draw_rect_rotated(self, size, render_position, angle, pivot, color)
end)

mod:hook(UIRenderer, "draw_slug_icon", function(func, self, resource, index, position, size, color, optional_material, material_flags, retained_id)
	local scale = self.scale or 1
	local scaled_position = Vector3(position[1] * scale, position[2] * scale, position[3] or 0)
	local scaled_size = Vector3(size[1] * scale, size[2] * scale, size[3] or 0)
	local angle, offset_x, offset_y = hud_curve(self, scaled_position, scaled_size)

	if not angle then
		return func(self, resource, index, position, size, color, optional_material, material_flags, retained_id)
	end

	if widget_graphic_anchor then
		local anchor = widget_graphic_anchor
		local pivot = Vector2(
			(anchor.position[1] + anchor.size[1] * 0.5 - scaled_position[1]) / scale,
			(anchor.position[2] + anchor.size[2] * 0.5 - scaled_position[2]) / scale
		)
		local render_position = Vector3(
			position[1] + anchor.offset_x / scale,
			position[2] + anchor.offset_y / scale,
			position[3] or 0
		)

		return UIRenderer.draw_slug_icon_rotated(self, resource, index, size, render_position, anchor.angle, pivot, color, optional_material, retained_id)
	else
		widget_graphic_anchor = {
			position = scaled_position,
			size = scaled_size,
			angle = angle,
			offset_x = offset_x,
			offset_y = offset_y,
		}
	end

	local render_position = Vector3(position[1] + offset_x / scale, position[2] + offset_y / scale, position[3] or 0)
	local unscaled_pivot = Vector2(size[1] * 0.5, size[2] * 0.5)

	return UIRenderer.draw_slug_icon_rotated(self, resource, index, size, render_position, angle, unscaled_pivot, color, optional_material, retained_id)
end)

mod:hook(UIRenderer, "draw_slug_multi_icon", function(func, self, resource, index, position, size, color, axis, spacing, direction, draw_count, optional_material, retained_ids)
	axis = axis or 1
	direction = direction or 1
	spacing = spacing or 0

	local retained_mode = not not retained_ids
	local existing_ids = retained_ids == true and nil or retained_ids
	local resources_are_array = type(resource) == "table"
	local output_ids = {}

	for i = 1, draw_count do
		local item_position = Vector3(position[1], position[2], position[3] or 0)

		item_position[axis] = item_position[axis] + (size[axis] + spacing) * (i - 1) * direction
		local item_resource = resources_are_array and resource[i] or resource
		local retained_id = existing_ids and existing_ids[i] or retained_mode

		output_ids[i] = UIRenderer.draw_slug_icon(
			self,
			item_resource,
			index,
			item_position,
			size,
			color,
			optional_material,
			nil,
			retained_id
		)
	end

	return retained_mode and output_ids or nil
end)
