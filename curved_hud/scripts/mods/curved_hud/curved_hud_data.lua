local mod = get_mod("curved_hud")

return {
	name = mod:localize("mod_name"),
	description = mod:localize("mod_description"),
	is_togglable = true,
	options = {
		widgets = {
			{
				setting_id = "curve_buff_hud",
				type = "checkbox",
				default_value = false,
			},
			{
				setting_id = "curve_strength",
				type = "numeric",
				default_value = -10,
				range = { -20, 20 },
			},
			{
				setting_id = "camera_follow_limit",
				type = "numeric",
				default_value = 1.0,
				range = { 0.0, 2.0 },
				decimals_number = 1,
			},
		},
	},
}
