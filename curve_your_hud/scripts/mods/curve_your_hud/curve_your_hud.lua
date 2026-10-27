local mod = get_mod("curve_your_hud")
local custom_assets = get_mod("CustomAssets")

local Managers = Managers
local Quaternion = Quaternion
local Vector3 = Vector3
local math = math
local Color = Color
local Gui = Gui
local Material = Material
local RESOLUTION_LOOKUP = RESOLUTION_LOOKUP
local Gui_slug_text_3d = Gui.slug_text_3d
local Gui_update_slug_text_3d = Gui.update_slug_text_3d

local UIHud = require("scripts/managers/ui/ui_hud")
local UIFonts = require("scripts/managers/ui/ui_fonts")
local UIRenderer = require("scripts/managers/ui/ui_renderer")
local UIWidget = require("scripts/managers/ui/ui_widget")
local UIViewHandler = require("scripts/managers/ui/ui_view_handler")
local WorldManager = require("scripts/foundation/managers/world/world_manager")

---------------
-- CONSTANTS --
---------------

local UNCURVED_ELEMENT_NAMES = {
	ConstantElementWatermark = true,
	ConstantElementPopupHandler = true,
	ConstantElementSoftwareCursor = true,
	HudElementPrologueTutorialSequenceTransitionEnd = true,
	HudElementPrologueTutorialInfoBox = true,
	HudElementCrosshair = true,
	HudElementInteraction = true,
	HudElementWorldMarkers = true,
	HudElementEmoteWheel = true,
	HudElementSmartTagging = true,
	HudElementDamageIndicator = true,
}

local SCREEN_ELEMENT_NAMES = {
	HudElementCustomizer = true,
	HudElementTacticalOverlay = true,
	HudElementCutsceneOverlay = true,
	HudElementCutsceneFading = true,
}

local HUD_DRAW_TARGET = {
	UNCURVED = "uncurved",
	CURVED = "curved",
	SCREEN = "screen",
}

local CAMERA_FOLLOW_DELAY_SECONDS = 0.01
local WORLD_PIXELS_PER_SCREEN_HEIGHT = 0.16
local CUSTOM_ASSETS_API_VERSION = 1
local HUD_CUSTOM_ASSET_ID = "curve_your_hud:hud_curve_clean"
local HUD_RENDER_TARGET_MATERIAL = "content/mods/curve_your_hud/hud_curve_clean"

local SCREEN_RENDERER_NAME = "curve_your_hud_screen_renderer"
local CURVED_RENDERER_NAME = "curve_your_hud_curved_renderer"
local UNCURVED_RENDER_PASS = "curve_your_hud_screen_uncurved"
local CURVED_RENDER_PASS   = "curve_your_hud_screen_curved"

local BITMAP_CURVED_LAYER = 0
local UNCURVED_SCREEN_PASS_LAYER = 1
local CURVED_SCREEN_PASS_LAYER = 2
local SCREEN_PASS_LAYER = 3

local FULLSCREEN_UVS = { { 0, 0 }, { 1, 1 } }

local DMF_OPTIONS_VIEW_NAME = "dmf_options_view"

---------------
-- VARIABLES --
---------------

mod.effect_enabled = true
mod.want_enabled = true

local known_huds = setmetatable({}, { __mode = "k" })
local hud_compositors = setmetatable({}, { __mode = "k" })
local hud_element_draw_targets = setmetatable({}, { __mode = "k" })
local original_hud_draw_methods = setmetatable({}, { __mode = "k" })
local world_enabled_by_name = {}
local gameplay_state_active
local hud_material_ready = false
local recreate_hud_compositors_requested = false


---@type string?
local previous_viewport_name

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

--------------------------
-- MOD SETTINGS CACHING --
--------------------------

mod.settings = {
	curve_strength     = mod:get("curve_strength"),
	noise_effect       = mod:get("noise_effect"),
	stripe_effect      = mod:get("stripe_effect"),
	camera_sway        = mod:get("camera_sway"),
	opacity_multiplier = mod:get("opacity_multiplier"),
	horizontal_margin  = mod:get("horizontal_margin"),
	vertical_margin    = mod:get("vertical_margin"),
	debug_grid         = mod:get("debug_grid"),
}

mod.on_setting_changed = function(setting_id)
	mod.settings[setting_id] = mod:get(setting_id)
	recreate_hud_compositors_requested = true
end

mod:register_hud_element({
	class_name = "HudElementCurveYourHudDebugGrid",
	filename = "curve_your_hud/scripts/mods/curve_your_hud/hud/curve_your_hud_debug_grid",
	visibility_groups = { "alive" },
	use_hud_scale = false,
})

-----------------
-- CAMERA SWAY --
-----------------

local function shortest_angle_delta(target, current)
	return (target - current + math.pi) % (math.pi * 2) - math.pi
end

local function reset_camera_lag()
	smoothed_camera_yaw = nil
	smoothed_camera_pitch = nil
	smoothed_camera_x = nil
	smoothed_camera_y = nil
	smoothed_camera_z = nil
	previous_viewport_name = nil
	camera_lag_x = 0.0
	camera_lag_y = 0.0
end

local function set_camera_lag_origin(yaw, pitch, position_x, position_y, position_z, viewport_name)
	smoothed_camera_yaw = yaw
	smoothed_camera_pitch = pitch
	smoothed_camera_x = position_x
	smoothed_camera_y = position_y
	smoothed_camera_z = position_z
	previous_viewport_name = viewport_name
	camera_lag_x = 0.0
	camera_lag_y = 0.0
end

local function current_camera_pose()
	local player_manager = Managers.player
	local camera_manager = Managers.state and Managers.state.camera

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

	return rotation, position, viewport_name
end

local function clamp_screen_offset(offset_x, offset_y, limit)
	local distance = math.sqrt(offset_x * offset_x + offset_y * offset_y)

	if distance <= limit then
		return offset_x, offset_y
	end

	local scale = limit / distance

	return offset_x * scale, offset_y * scale
end

local function movement_limit_pixels(width, height)
	local movement_limit_percent = 2.0

	return math.min(width, height) * movement_limit_percent * 0.01
end

local function update_camera_lag(dt)
	if not dt or dt <= 0 then
		reset_camera_lag()
		return
	end

	local rotation, position, viewport_name = current_camera_pose()

	if not rotation then
		reset_camera_lag()
		return
	end

	local yaw, pitch = Quaternion.to_yaw_pitch_roll(rotation)
	local position_x = position[1]
	local position_y = position[2]
	local position_z = position[3]

	if viewport_name ~= previous_viewport_name or smoothed_camera_yaw == nil then
		set_camera_lag_origin(yaw, pitch, position_x, position_y, position_z, viewport_name)
		return
	end

	local follow_fraction = 1 - math.exp(-dt / CAMERA_FOLLOW_DELAY_SECONDS)

	smoothed_camera_yaw = smoothed_camera_yaw + shortest_angle_delta(yaw, smoothed_camera_yaw) * follow_fraction
	smoothed_camera_pitch = smoothed_camera_pitch + shortest_angle_delta(pitch, smoothed_camera_pitch) * follow_fraction
	smoothed_camera_x = smoothed_camera_x + (position_x - smoothed_camera_x) * follow_fraction
	smoothed_camera_y = smoothed_camera_y + (position_y - smoothed_camera_y) * follow_fraction
	smoothed_camera_z = smoothed_camera_z + (position_z - smoothed_camera_z) * follow_fraction

	local lag_yaw = shortest_angle_delta(smoothed_camera_yaw, yaw)
	local lag_pitch = shortest_angle_delta(smoothed_camera_pitch, pitch)
	local world_lag_x = smoothed_camera_x - position_x
	local world_lag_y = smoothed_camera_y - position_y
	local world_lag_z = smoothed_camera_z - position_z
	local camera_right = Quaternion.right(rotation)
	local camera_up = Quaternion.up(rotation)
	local lag_right = world_lag_x * camera_right[1] + world_lag_y * camera_right[2] + world_lag_z * camera_right[3]
	local lag_up = world_lag_x * camera_up[1] + world_lag_y * camera_up[2] + world_lag_z * camera_up[3]
	local width = RESOLUTION_LOOKUP.width
	local height = RESOLUTION_LOOKUP.height
	local movement_limit = movement_limit_pixels(width, height)
	local world_pixels_per_meter = height * WORLD_PIXELS_PER_SCREEN_HEIGHT
	local camera_sway_scale = mod.settings.camera_sway
	local world_sway_scale = camera_sway_scale * 5
	local target_lag_x = -lag_yaw * width * 0.5 * camera_sway_scale + lag_right * world_pixels_per_meter * world_sway_scale
	local target_lag_y = -lag_pitch * height * camera_sway_scale - lag_up * world_pixels_per_meter * world_sway_scale

	local limited_lag_x, limited_lag_y = clamp_screen_offset(target_lag_x, target_lag_y, movement_limit)

	local movement_smoothing_time = math.max(CAMERA_FOLLOW_DELAY_SECONDS * 0.5, 0.05)
	local movement_fraction = 1 - math.exp(-dt / movement_smoothing_time)

	camera_lag_x = camera_lag_x + (limited_lag_x - camera_lag_x) * movement_fraction
	camera_lag_y = camera_lag_y + (limited_lag_y - camera_lag_y) * movement_fraction

	camera_lag_x, camera_lag_y = clamp_screen_offset(camera_lag_x, camera_lag_y, movement_limit)
end

-------------------------
-- HUD ELEMENT ROUTING --
-------------------------


local function is_gameplay_hud_element(element)
	local hud = element._parent
	local visibility_groups = hud and hud._visibility_groups

	if not visibility_groups then
		return false
	end

	for i = 1, #visibility_groups do
		local visibility_group = visibility_groups[i]

		if visibility_group.name == "alive" then
			local visible_elements = visibility_group.visible_elements

			return visible_elements and visible_elements[element.__class_name] == true or false
		end
	end

	return false
end

local function calculate_hud_element_draw_target(element)
	local element_name = element.__class_name

	if SCREEN_ELEMENT_NAMES[element_name] then
		return HUD_DRAW_TARGET.SCREEN
	end

	local scenegraph = element._ui_scenegraph

	if scenegraph
		and is_gameplay_hud_element(element)
		and not UNCURVED_ELEMENT_NAMES[element_name]
	then
		return HUD_DRAW_TARGET.CURVED
	end

	return HUD_DRAW_TARGET.UNCURVED
end

local function hud_element_draw_target(element)
	local draw_target = hud_element_draw_targets[element]

	if not draw_target then
		draw_target = calculate_hud_element_draw_target(element)
		hud_element_draw_targets[element] = draw_target
	end

	return draw_target
end

----------------------------
-- HUD RENDERER MIGRATION --
----------------------------

local function is_live_widget(value)
	local passes = type(value) == "table" and rawget(value, "passes")
	local pass = type(passes) == "table" and passes[1]
	local data = type(pass) == "table" and rawget(pass, "data")
	local parent_name = type(data) == "table" and rawget(data, "_parent_name")

	return parent_name ~= nil and parent_name == rawget(value, "name")
end

local function release_owned_widgets(value, ui_renderer, visited)
	if type(value) ~= "table" or visited[value] then
		return
	end

	visited[value] = true

	if is_live_widget(value) then
		UIWidget.destroy(ui_renderer, value)
		value.dirty = true
		return
	end

	for key, child in pairs(value) do
		if key ~= "_parent" and type(child) == "table" then
			release_owned_widgets(child, ui_renderer, visited)
		end
	end
end

local function migrate_hud_renderer(hud, source_renderer, destination_renderer)
	local elements = hud._elements_array

	if source_renderer and elements then
		local visited = {}

		for i = 1, #elements do
			release_owned_widgets(elements[i], source_renderer, visited)
		end
	end

	hud._ui_renderer = destination_renderer
	hud._refresh_retained = true
end

--------------------
-- HUD COMPOSITOR --
--------------------

local function get_or_create_hud_compositor(hud)
	if hud_compositors[hud] then
		return hud_compositors[hud]
	end
	if not hud_material_ready then
		return nil
	end

	local original_renderer = hud._ui_renderer

	if not original_renderer or original_renderer.render_target then
		return nil
	end

	local world = Managers.world:world(hud._world_name)
	local screen_renderer = Managers.ui:create_renderer(SCREEN_RENDERER_NAME, world)

	screen_renderer.render_pass_flag = "render_pass"
	screen_renderer.base_render_pass = "to_screen"

	local curved_renderer = Managers.ui:create_renderer(
		CURVED_RENDERER_NAME,
		world,
		true,
		screen_renderer.gui,
		screen_renderer.gui_retained,
		HUD_RENDER_TARGET_MATERIAL
	)
	local curved_material = curved_renderer.render_target_material

	Material.set_scalar(curved_material, "material_variable_a0cca63e", mod.settings.noise_effect)
	Material.set_scalar(curved_material, "raster_intensity", mod.settings.stripe_effect)
	Material.set_scalar(curved_material, "strength", mod.settings.curve_strength)
	Material.set_scalar(curved_material, "angular_strength", 2.0)

	Gui.render_pass(
		screen_renderer.gui_retained,
		BITMAP_CURVED_LAYER,
		curved_renderer.base_render_pass,
		true,
		curved_renderer.render_target
	)
	Gui.render_pass(
		screen_renderer.gui_retained,
		UNCURVED_SCREEN_PASS_LAYER,
		UNCURVED_RENDER_PASS,
		false
	)
	Gui.render_pass(
		screen_renderer.gui_retained,
		CURVED_SCREEN_PASS_LAYER,
		CURVED_RENDER_PASS,
		false
	)
	Gui.render_pass(
		screen_renderer.gui_retained,
		SCREEN_PASS_LAYER,
		screen_renderer.base_render_pass,
		false
	)

	local compositor = {
		original_renderer = original_renderer,
		screen_renderer = screen_renderer,
		curved_renderer = curved_renderer,
	}

	hud_compositors[hud] = compositor
	migrate_hud_renderer(hud, original_renderer, curved_renderer)

	return compositor
end

local function destroy_hud_compositor(hud, restore_original_renderer)
	local compositor = hud_compositors[hud]

	if not compositor then
		return
	end

	hud_compositors[hud] = nil

	if restore_original_renderer and hud._ui_renderer == compositor.curved_renderer then
		migrate_hud_renderer(hud, compositor.curved_renderer, compositor.original_renderer)
	end

	Managers.ui:destroy_renderer(CURVED_RENDERER_NAME)
	Managers.ui:destroy_renderer(SCREEN_RENDERER_NAME)
end

local function destroy_all_hud_compositors()
	for hud in pairs(hud_compositors) do
		destroy_hud_compositor(hud, true)
	end
end

-----------------
-- HUD DRAWING --
-----------------

local function composite_hud(compositor)
	local screen_renderer = compositor.screen_renderer
	local curved_renderer = compositor.curved_renderer

	UIRenderer.clear_render_pass_queue(screen_renderer)
	UIRenderer.add_render_pass(
		screen_renderer,
		BITMAP_CURVED_LAYER,
		curved_renderer.base_render_pass,
		false,
		curved_renderer.render_target
	)
	UIRenderer.add_render_pass(
		screen_renderer,
		UNCURVED_SCREEN_PASS_LAYER,
		UNCURVED_RENDER_PASS,
		false
	)
	UIRenderer.add_render_pass(
		screen_renderer,
		CURVED_SCREEN_PASS_LAYER,
		CURVED_RENDER_PASS,
		false
	)
	UIRenderer.add_render_pass(
		screen_renderer,
		SCREEN_PASS_LAYER,
		"to_screen",
		false
	)

	local width = RESOLUTION_LOOKUP.width
	local height = RESOLUTION_LOOKUP.height
	local horizontal_margin = mod.settings.horizontal_margin
	local vertical_margin = mod.settings.vertical_margin
	local content_width = width - horizontal_margin * 2
	local content_height = height - vertical_margin * 2
	local previous_base_render_pass = screen_renderer.base_render_pass
	local color = Color(255, 255, 255, 255)
	local scenegraph = {}
	local render_settings = {
		scale = 1,
	}

	UIRenderer.begin_pass(screen_renderer, scenegraph, nil, 0, render_settings)
	screen_renderer.base_render_pass = CURVED_RENDER_PASS

	local scale = screen_renderer.scale or 1
	local snapped_lag_x = math.floor(camera_lag_x + 0.5)
	local snapped_lag_y = math.floor(camera_lag_y + 0.5)
	local left = math.floor(horizontal_margin + 0.5) + snapped_lag_x
	local right = math.floor(horizontal_margin + content_width + 0.5) + snapped_lag_x
	local top = math.floor(vertical_margin + 0.5) + snapped_lag_y
	local bottom = math.floor(vertical_margin + content_height + 0.5) + snapped_lag_y
	local position = Vector3(left / scale, top / scale, BITMAP_CURVED_LAYER)
	local size = Vector3((right - left) / scale, (bottom - top) / scale, 0)

	UIRenderer.script_draw_bitmap_uv(
		screen_renderer,
		curved_renderer.render_target_material,
		position,
		size,
		FULLSCREEN_UVS,
		color,
		nil
	)

	screen_renderer.base_render_pass = previous_base_render_pass
	UIRenderer.end_pass(screen_renderer)
end

local function draw_hud_elements(hud, dt, t, input_service, ui_renderer, draw_target, base_render_pass)
	local render_settings = hud._render_settings
	local saved_start_layer = render_settings.start_layer
	local saved_base_render_pass = ui_renderer.base_render_pass
	local alpha_multiplier = render_settings.alpha_multiplier or 1
	local opacity_multiplier = mod.settings.opacity_multiplier
	local currently_visible_elements = hud._currently_visible_elements
	local elements_hud_scale_lookup = hud._elements_hud_scale_lookup
	local elements_array = hud._elements_array
	local elements_hud_retained_mode_lookup = hud._elements_hud_retained_mode_lookup

	for i = 1, #elements_array do
		local element = elements_array[i]
		local element_name = element.__class_name

		if hud_element_draw_target(element) == draw_target
			and currently_visible_elements[element_name]
			and element.draw
		then
			local hud_scale_applied = false
			local opacity = not SCREEN_ELEMENT_NAMES[element_name]
				and opacity_multiplier or 1

			if elements_hud_scale_lookup[element_name] then
				hud_scale_applied = true
				hud:_apply_hud_scale()
			end

			render_settings.force_retained_mode = elements_hud_retained_mode_lookup[element_name]
			render_settings.alpha_multiplier = alpha_multiplier * opacity
			ui_renderer.base_render_pass = base_render_pass or saved_base_render_pass

			element:draw(dt, t, ui_renderer, render_settings, input_service)
			render_settings.alpha_multiplier = alpha_multiplier

			if hud_scale_applied then
				hud:_abort_hud_scale()
			end
		end
	end

	ui_renderer.base_render_pass = saved_base_render_pass
	render_settings.start_layer = saved_start_layer
end

local function is_world_enabled(world_name)
	if world_enabled_by_name[world_name] == nil then
		world_enabled_by_name[world_name] = Managers.world:is_world_enabled(world_name) == true
	end

	return world_enabled_by_name[world_name]
end

local function install_hud_draw(hud)
	if original_hud_draw_methods[hud] then
		return
	end

	local original_draw = hud.draw

	original_hud_draw_methods[hud] = original_draw
	hud.draw = function(self, dt, t, input_service)
		local compositor = mod.effect_enabled
			and is_world_enabled(self._world_name)
			and get_or_create_hud_compositor(self)

		if not compositor then
			return original_draw(self, dt, t, input_service)
		end

		composite_hud(compositor)
		draw_hud_elements(self, dt, t, input_service, compositor.screen_renderer, HUD_DRAW_TARGET.UNCURVED, UNCURVED_RENDER_PASS)
		draw_hud_elements(self, dt, t, input_service, compositor.curved_renderer, HUD_DRAW_TARGET.CURVED)
		draw_hud_elements(self, dt, t, input_service, compositor.screen_renderer, HUD_DRAW_TARGET.SCREEN)
	end
end

local function restore_hud_draw(hud)
	local original_draw = original_hud_draw_methods[hud]

	if original_draw then
		hud.draw = original_draw
		original_hud_draw_methods[hud] = nil
	end
end

local function register_hud(hud)
	if not hud then
		return
	end

	known_huds[hud] = true
	world_enabled_by_name[hud._world_name] = Managers.world:is_world_enabled(hud._world_name) == true
	install_hud_draw(hud)
end

------------------
-- UI HUD HOOKS --
------------------

mod:hook(UIHud, "init", function(func, self, ...)
	local result = func(self, ...)

	register_hud(self)

	return result
end)

mod:hook(UIHud, "destroy", function(func, self, ...)
	local result = func(self, ...)

	destroy_hud_compositor(self, false)
	restore_hud_draw(self)
	known_huds[self] = nil

	return result
end)

----------------
-- WORLD HOOK --
----------------

mod:hook(WorldManager, "enable_world", function(func, self, world_name, enabled, ...)
	local result = func(self, world_name, enabled, ...)

	world_enabled_by_name[world_name] = enabled == true

	return result
end)

---------------------------------
-- 3D TEXT RENDER-PASS ROUTING --
---------------------------------

local function draw_text_3d_to_render_pass(ui_renderer, text, font_size, font_type, transform, position, layer, size, color, retained_id)
	local render_settings = ui_renderer.render_settings
	local retained_mode = not not retained_id

	if retained_id == true then
		retained_id = nil
	end

	local alpha_multiplier = render_settings and render_settings.alpha_multiplier or 1
	local intensity_multiplier = render_settings and render_settings.color_intensity_multiplier or 1

	if color then
		color = Color(color[1] * alpha_multiplier, color[2] * intensity_multiplier, color[3] * intensity_multiplier, color[4] * intensity_multiplier)
	end

	if render_settings then
		layer = (render_settings.start_layer or 0) + layer
	end

	local font_data = UIFonts.data_by_type(font_type)
	local flags = (font_data.render_flags or 0) + Gui.RenderPass
	local gui = retained_mode and ui_renderer.gui_retained or ui_renderer.gui
	local gui_position = position or Vector3.zero()
	local render_pass_flag = ui_renderer.render_pass_flag
	local render_pass = ui_renderer.base_render_pass

	if retained_id then
		return Gui_update_slug_text_3d(gui, retained_id, text, font_data.path, font_size, render_pass_flag, render_pass, transform, gui_position, layer, size, color, "flags", flags)
	else
		return Gui_slug_text_3d(gui, text, font_data.path, font_size, render_pass_flag, render_pass, transform, gui_position, layer, size, color, "flags", flags)
	end
end

mod:hook(UIRenderer, "script_draw_text_3d", function(func, ui_renderer, text, font_size, font_type, transform, position, layer, size, color, options, retained_id)
	if ui_renderer.name ~= CURVED_RENDERER_NAME then
		return func(ui_renderer, text, font_size, font_type, transform, position, layer, size, color, options, retained_id)
	end

	return draw_text_3d_to_render_pass(ui_renderer, text, font_size, font_type, transform, position, layer, size, color, retained_id)
end)

-------------------------------------
-- REFRESH HUD ON MOD OPTIONS EXIT --
-------------------------------------

mod:hook(UIViewHandler, "_force_close", function(func, self, view_name, ...)
	local result = func(self, view_name, ...)

	if view_name == DMF_OPTIONS_VIEW_NAME then
		reset_camera_lag()
		if recreate_hud_compositors_requested then
			recreate_hud_compositors_requested = false
			if mod:is_enabled() and mod.effect_enabled then
				destroy_all_hud_compositors()
			end
		end
	end

	return result
end)

------------------------
-- GAMEPLAY LIFECYCLE --
------------------------

local function gameplay_scene_is_active()
	if gameplay_state_active ~= nil then
		return gameplay_state_active
	end

	return not not (Managers.state and Managers.state.game_mode)
end

local function set_effect_enabled(enabled)
	enabled = not not enabled

	if mod.effect_enabled == enabled then
		return
	end

	mod.effect_enabled = enabled

	if not enabled then
		reset_camera_lag()
		destroy_all_hud_compositors()
	else
		world_enabled_by_name = {}
	end
end

local function refresh_effect_state()
	set_effect_enabled(
		mod:is_enabled()
		and mod.want_enabled
		and hud_material_ready
		and gameplay_scene_is_active()
	)
end

--------------------
-- ON EVERY FRAME --
--------------------

mod.update = function(dt)
	if mod.effect_enabled then
		if mod.settings.camera_sway ~= 0 then
			update_camera_lag(dt)
		end
	end
end

---------------------------
-- ON GAME STATE CHANGED --
---------------------------

mod.on_game_state_changed = function(status, state_name)
	if state_name == "StateGameplay" then
		gameplay_state_active = status == "enter"

		if gameplay_state_active then
			refresh_effect_state()
		else
			set_effect_enabled(false)
		end
	end
end

------------------------
-- ON ALL MODS LOADED --
------------------------

mod.on_all_mods_loaded = function()
	set_effect_enabled(false)

	if not custom_assets or not custom_assets.is_api_compatible(CUSTOM_ASSETS_API_VERSION) then
        mod:error("Needs Custom Assets")
        return
    end

	local ticket, acquire_error = custom_assets.acquire(mod, HUD_CUSTOM_ASSET_ID, function(_, asset, load_error)
		if load_error or not asset or not asset.primary then
			mod:error("Could not load %s: %s", HUD_CUSTOM_ASSET_ID, tostring(load_error))
			return
		end

		hud_material_ready = true
		refresh_effect_state()
	end)

	if not ticket then
		mod:error("Could not acquire %s: %s", HUD_CUSTOM_ASSET_ID, tostring(acquire_error))
	end
end

---------------------------
-- ON ENABLED / DISABLED --
---------------------------

mod.on_enabled = function()
	local ui_manager = Managers.ui

	if ui_manager then
		register_hud(ui_manager._hud)
		register_hud(ui_manager._spectator_hud)
	end

	refresh_effect_state()
end

mod.on_disabled = function()
	set_effect_enabled(false)
end

mod.on_unload = function()
	set_effect_enabled(false)

	for hud in pairs(known_huds) do
		restore_hud_draw(hud)
	end

	if custom_assets then
		custom_assets.release_owner(mod)
	end
end

----------------------
-- PUBLIC FUNCTIONS --
----------------------

local function can_press_keybind()
	local ui_manager = Managers.ui
	local chat_is_open = ui_manager and ui_manager.chat_using_input and ui_manager:chat_using_input()
	local view_is_open = ui_manager and ui_manager.has_active_view and ui_manager:has_active_view()

	return gameplay_scene_is_active()
		and not chat_is_open
		and not view_is_open
end

mod.toggle = function()
	mod.want_enabled = not mod.want_enabled
	refresh_effect_state()
end

mod.enable = function()
	mod.want_enabled = true
	refresh_effect_state()
end

mod.disable = function()
	mod.want_enabled = false
	refresh_effect_state()
end

mod.toggle_keybind = function()
	if not can_press_keybind() then return end
	mod.toggle()
end


--------------------
-- INITIALIZATION --
--------------------

set_effect_enabled(false)
