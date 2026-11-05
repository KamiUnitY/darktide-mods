local mod = get_mod("curve_your_hud")
local custom_assets = get_mod("CustomAssets")

local Managers = Managers
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

local CameraSway = mod:io_dofile("curve_your_hud/scripts/mods/curve_your_hud/library/camera_sway")
local CompatHudStudio = mod:io_dofile("curve_your_hud/scripts/mods/curve_your_hud/compatibility/hud_studio")

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

local OVERLAY_ELEMENT_NAMES = {
	HudElementCustomizer = true,
	HudElementTacticalOverlay = true,
	HudElementCutsceneOverlay = true,
	HudElementCutsceneFading = true,
}

local HUD_DRAW_TARGET = {
	UNCURVED = "uncurved",
	CURVED = "curved",
	OVERLAY = "overlay",
}

local CUSTOM_ASSETS_API_VERSION = 1
local HUD_CUSTOM_ASSET_ID = "curve_your_hud:hud_curve_clean"
local HUD_RENDER_TARGET_MATERIAL = "content/mods/curve_your_hud/hud_curve_clean"

local SCREEN_RENDERER_NAME = "curve_your_hud_screen_renderer"
local OFFSCREEN_RENDERER_NAME = "curve_your_hud_offscreen_renderer"
local DEFAULT_SCREEN_RENDER_PASS = "to_screen"

local OFFSCREEN_PASS_LAYER = 0
local SCREEN_PASS_LAYER = 1

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
local widget_renderer_owners = setmetatable({}, { __mode = "k" })
local world_enabled_by_name = {}
local gameplay_state_active
local hud_material_ready = false
local recreate_hud_compositors_requested = false

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

	if OVERLAY_ELEMENT_NAMES[element_name] then
		return HUD_DRAW_TARGET.OVERLAY
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

-------------------------
-- HUD WIDGET OWNERSHIP --
-------------------------

local function is_live_widget(value)
	local passes = type(value) == "table" and rawget(value, "passes")
	local pass = type(passes) == "table" and passes[1]
	local data = type(pass) == "table" and rawget(pass, "data")
	local parent_name = type(data) == "table" and rawget(data, "_parent_name")

	return parent_name ~= nil and parent_name == rawget(value, "name")
end

local function release_owned_widgets(value, ui_renderer, destination_renderer, visited)
	if type(value) ~= "table" or visited[value] then
		return
	end

	visited[value] = true

	if is_live_widget(value) then
		UIWidget.destroy(ui_renderer, value)
		value.dirty = true
		widget_renderer_owners[value] = destination_renderer
		return
	end

	for key, child in pairs(value) do
		if key ~= "_parent" and type(child) == "table" then
			release_owned_widgets(child, ui_renderer, destination_renderer, visited)
		end
	end
end

local function release_hud_element_widgets(hud, ui_renderer, destination_renderer, draw_target)
	local elements = hud._elements_array

	if ui_renderer and elements then
		local visited = {}

		for i = 1, #elements do
			local element = elements[i]

			if not draw_target or hud_element_draw_target(element) == draw_target then
				release_owned_widgets(element, ui_renderer, destination_renderer, visited)
			end
		end
	end

	hud._refresh_retained = true
end

mod:hook(UIWidget, "draw", function(func, widget, ui_renderer, ...)
	if ui_renderer.name == OFFSCREEN_RENDERER_NAME then
		widget_renderer_owners[widget] = ui_renderer
	end

	return func(widget, ui_renderer, ...)
end)

mod:hook(UIWidget, "destroy", function(func, ui_renderer, widget, ...)
	return func(widget_renderer_owners[widget] or ui_renderer, widget, ...)
end)

mod:hook(UIWidget, "set_visible", function(func, widget, ui_renderer, ...)
	return func(widget, widget_renderer_owners[widget] or ui_renderer, ...)
end)

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

	local screen_renderer = Managers.ui:create_renderer(SCREEN_RENDERER_NAME)

	screen_renderer.render_pass_flag = "render_pass"
	screen_renderer.base_render_pass = DEFAULT_SCREEN_RENDER_PASS

	local offscreen_renderer = Managers.ui:create_renderer(
		OFFSCREEN_RENDERER_NAME,
		nil,
		true,
		screen_renderer.gui,
		screen_renderer.gui_retained,
		HUD_RENDER_TARGET_MATERIAL
	)
	local curved_material = offscreen_renderer.render_target_material

	Material.set_scalar(curved_material, "material_variable_a0cca63e", mod.settings.noise_effect)
	Material.set_scalar(curved_material, "raster_intensity", mod.settings.stripe_effect)
	Material.set_scalar(curved_material, "strength", mod.settings.curve_strength)
	Material.set_scalar(curved_material, "angular_strength", 2.0)

	Gui.render_pass(
		screen_renderer.gui_retained,
		OFFSCREEN_PASS_LAYER,
		offscreen_renderer.base_render_pass,
		true,
		offscreen_renderer.render_target
	)
	Gui.render_pass(
		screen_renderer.gui_retained,
		SCREEN_PASS_LAYER,
		DEFAULT_SCREEN_RENDER_PASS,
		false
	)

	local compositor = {
		screen_renderer = screen_renderer,
		offscreen_renderer = offscreen_renderer,
	}

	hud_compositors[hud] = compositor
	release_hud_element_widgets(hud, original_renderer, offscreen_renderer, HUD_DRAW_TARGET.CURVED)

	return compositor
end

local function destroy_hud_compositor(hud)
	local compositor = hud_compositors[hud]

	if not compositor then
		return
	end

	hud_compositors[hud] = nil
	release_hud_element_widgets(hud, compositor.offscreen_renderer, nil, HUD_DRAW_TARGET.CURVED)

	Managers.ui:destroy_renderer(OFFSCREEN_RENDERER_NAME)
	Managers.ui:destroy_renderer(SCREEN_RENDERER_NAME)
end

local function destroy_all_hud_compositors()
	for hud in pairs(hud_compositors) do
		destroy_hud_compositor(hud)
	end
end

-----------------
-- HUD DRAWING --
-----------------

local function prepare_hud_render_passes(compositor)
	local screen_renderer = compositor.screen_renderer
	local offscreen_renderer = compositor.offscreen_renderer

	UIRenderer.clear_render_pass_queue(screen_renderer)
	UIRenderer.add_render_pass(
		screen_renderer,
		OFFSCREEN_PASS_LAYER,
		offscreen_renderer.base_render_pass,
		false,
		offscreen_renderer.render_target
	)
	UIRenderer.add_render_pass(
		screen_renderer,
		SCREEN_PASS_LAYER,
		DEFAULT_SCREEN_RENDER_PASS,
		false
	)
end

local function draw_original_hud_without_curved_elements(hud, original_draw, dt, t, input_service)
	local currently_visible_elements = hud._currently_visible_elements
	local elements_array = hud._elements_array
	local hidden_element_names = {}

	for i = 1, #elements_array do
		local element = elements_array[i]
		local element_name = element.__class_name

		if currently_visible_elements[element_name]
			and hud_element_draw_target(element) == HUD_DRAW_TARGET.CURVED
		then
			currently_visible_elements[element_name] = false
			hidden_element_names[#hidden_element_names + 1] = element_name
		end
	end

	original_draw(hud, dt, t, input_service)

	for i = 1, #hidden_element_names do
		currently_visible_elements[hidden_element_names[i]] = true
	end
end

local function draw_hud_elements(hud, dt, t, input_service, ui_renderer, draw_target)
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

			if elements_hud_scale_lookup[element_name] then
				hud_scale_applied = true
				hud:_apply_hud_scale()
			end

			render_settings.force_retained_mode = elements_hud_retained_mode_lookup[element_name]
			render_settings.alpha_multiplier = alpha_multiplier * opacity_multiplier
			ui_renderer.base_render_pass = saved_base_render_pass

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

local function composite_hud(compositor)
	local screen_renderer = compositor.screen_renderer
	local offscreen_renderer = compositor.offscreen_renderer

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
	screen_renderer.base_render_pass = DEFAULT_SCREEN_RENDER_PASS

	local scale = screen_renderer.scale or 1
	local camera_lag_x, camera_lag_y = CameraSway.offset()
	local snapped_lag_x = math.floor(camera_lag_x + 0.5)
	local snapped_lag_y = math.floor(camera_lag_y + 0.5)
	local left = math.floor(horizontal_margin + 0.5) + snapped_lag_x
	local right = math.floor(horizontal_margin + content_width + 0.5) + snapped_lag_x
	local top = math.floor(vertical_margin + 0.5) + snapped_lag_y
	local bottom = math.floor(vertical_margin + content_height + 0.5) + snapped_lag_y
	local position = Vector3(left / scale, top / scale, 0)
	local size = Vector3((right - left) / scale, (bottom - top) / scale, 0)

	UIRenderer.script_draw_bitmap_uv(
		screen_renderer,
		offscreen_renderer.render_target_material,
		position,
		size,
		FULLSCREEN_UVS,
		color,
		nil
	)

	screen_renderer.base_render_pass = previous_base_render_pass
	UIRenderer.end_pass(screen_renderer)
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

		prepare_hud_render_passes(compositor)
		draw_original_hud_without_curved_elements(self, original_draw, dt, t, input_service)
		draw_hud_elements(self, dt, t, input_service, compositor.offscreen_renderer, HUD_DRAW_TARGET.CURVED)
		composite_hud(compositor)
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
	destroy_hud_compositor(self)
	restore_hud_draw(self)
	known_huds[self] = nil

	return func(self, ...)
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
	if ui_renderer.name == OFFSCREEN_RENDERER_NAME then
		return draw_text_3d_to_render_pass(ui_renderer, text, font_size, font_type, transform, position, layer, size, color, retained_id)
	end

	return func(ui_renderer, text, font_size, font_type, transform, position, layer, size, color, options, retained_id)
end)

-------------------------------------
-- REFRESH HUD ON MOD OPTIONS EXIT --
-------------------------------------

mod:hook(UIViewHandler, "_force_close", function(func, self, view_name, ...)
	local result = func(self, view_name, ...)

	if view_name == DMF_OPTIONS_VIEW_NAME then
		CameraSway.reset()
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
		CameraSway.reset()
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
			CameraSway.update(dt)
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

	CompatHudStudio.install(OFFSCREEN_RENDERER_NAME)

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
