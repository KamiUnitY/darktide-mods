local mod = get_mod("curve_your_hud")

local Vector3 = Vector3

local UIRenderer = require("scripts/managers/ui/ui_renderer")

local CompatHudStudio = {}

CompatHudStudio.install = function(offscreen_renderer_name)
	local hud_studio = get_mod("hud_studio")
	local gui_direct = hud_studio and hud_studio.hud_studio_gui_direct

	if not gui_direct then return end

	mod:hook(gui_direct, "text", function(func, ui_renderer, text, font_size, font_type, x, y, z, width, height, color, options, retain_key, shadow_color, shadow_text)
		if ui_renderer.name == offscreen_renderer_name then
			retain_key = nil
		end

		return func(ui_renderer, text, font_size, font_type, x, y, z, width, height, color, options, retain_key, shadow_color, shadow_text)
	end)

	mod:hook(gui_direct, "text_3d", function(func, ui_renderer, text, font_size, font_type, transform, layer, size, color)
		if ui_renderer.name == offscreen_renderer_name then
			return UIRenderer.script_draw_text_3d(ui_renderer, text, font_size, font_type, transform, Vector3.zero(), layer, size, color)
		end

		return func(ui_renderer, text, font_size, font_type, transform, layer, size, color)
	end)
end

return CompatHudStudio
