local mod = get_mod("immersive_evasion")

return {
	name = mod:localize("mod_name"),
	description = mod:localize("mod_description"),
	is_togglable = true,
	options = {
		widgets = {
			{
				setting_id      = "invert_dodge_angle",
				type = "checkbox",
				default_value = false,
			},
			{
				setting_id      = "invert_dodging_slide_angle",
				type = "checkbox",
				default_value = false,
			},
			{
				setting_id      = "tilt_factor_dodge",
				type            = "numeric",
				default_value   = 0.050,
				range           = { 0.0, 0.5 },
				decimals_number = 3,
			},
			{
				setting_id      = "tilt_factor_slide",
				type            = "numeric",
				default_value   = 0.150,
				range           = { 0.0, 0.5 },
				decimals_number = 3,
			},
			{
				setting_id  = "debug_group",
				type        = "group",
				sub_widgets = {
					{
						setting_id = "enable_debug_modding_tools",
						type = "checkbox",
						default_value = false,
					},
				}
			},
		},
	}
}
