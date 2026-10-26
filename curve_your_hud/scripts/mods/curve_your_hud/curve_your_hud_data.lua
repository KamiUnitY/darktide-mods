local mod = get_mod("curve_your_hud")

return {
	name = mod:localize("mod_name"),
	description = mod:localize("mod_description"),
	is_togglable = true,
	options = {
		widgets = {
			{
				setting_id = "toggle_keybind",
				type = "keybind",
				default_value = {},
				keybind_trigger = "pressed",
				keybind_type = "function_call",
				function_name = "toggle_keybind",
			},
			{
				setting_id = "curve_strength",
				type = "numeric",
				default_value = 0.08,
				range = { 0, 0.25 },
				decimals_number = 3,
				step_size_value = 0.005,
			},
			{
				setting_id = "noise_effect",
				type = "numeric",
				default_value = 0.2,
				range = { 0.0, 1.0 },
				decimals_number = 2,
				step_size_value = 0.05,
			},
			{
				setting_id = "stripe_effect",
				type = "numeric",
				default_value = 0.8,
				range = { 0.0, 1.0 },
				decimals_number = 2,
				step_size_value = 0.05,
			},
			{
				setting_id = "camera_sway",
				type = "numeric",
				default_value = 0.25,
				range = { -1.0, 1.0 },
				decimals_number = 2,
  				step_size_value = 0.05,
			},
			{
				setting_id = "opacity_multiplier",
				type = "numeric",
				default_value = 0.85,
				range = { 0, 1 },
				decimals_number = 2,
				step_size_value = 0.05,
			},
			{
				setting_id = "horizontal_margin",
				type = "numeric",
				default_value = 0,
				range = { -200, 200 },
				decimals_number = 0,
				step_size_value = 5,
			},
			{
				setting_id = "vertical_margin",
				type = "numeric",
				default_value = -15,
				range = { -200, 200 },
				decimals_number = 0,
				step_size_value = 5,
			},
			{
				setting_id = "debug_group",
				type = "group",
				sub_widgets = {
					{
						setting_id = "debug_grid",
						type = "checkbox",
						default_value = false,
					},
				},
			},
		},
	},
}
