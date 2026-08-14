local mod = get_mod("upside_down_name")
local UIRenderer = require("scripts/managers/ui/ui_renderer")

local function local_player_name()
	local player = Managers.player and Managers.player:local_player_safe(1)
	local profile = player and player:profile()

	return profile and profile.name
end

mod:hook(UIRenderer, "script_draw_text", function(func, self, text, font_size, font_type, position, size, color, options, retained_id)
	local name = local_player_name()

	if type(text) ~= "string" or not name or not string.find(text, name, 1, true) then
		return func(self, text, font_size, font_type, position, size, color, options, retained_id)
	end

	local angle = math.rad(mod:get("angle") or 180)

	if angle == 0 then
		return func(self, text, font_size, font_type, position, size, color, options, retained_id)
	end

	local width, height, minimum = UIRenderer.text_size(self, text, font_type, font_size, size, options, false)
	local pivot_x = minimum[1] + width * 0.5
	local pivot_y = minimum[2] + height * 0.5
	local cosine = math.cos(angle)
	local sine = math.sin(angle)
	local transform = Matrix4x4.from_elements(
		cosine, sine, 0,
		-sine, cosine, 0,
		0, 0, 1,
		position[1] + pivot_x * (1 - cosine) + pivot_y * sine,
		position[2] + pivot_y * (1 - cosine) - pivot_x * sine,
		0
	)

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
		options,
		retained_id
	)
end)
