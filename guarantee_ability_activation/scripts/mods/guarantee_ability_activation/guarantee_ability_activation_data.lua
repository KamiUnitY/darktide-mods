local mod = get_mod("guarantee_ability_activation")

return {
	name = mod:localize("mod_name"),
	description = mod:localize("mod_description"),
	is_togglable = true,
	options = {
		widgets = {
			{
				setting_id = "enable_prevent_double_dashing",
				type = "checkbox",
				default_value = true,
			},
			{
				setting_id = "enable_prevent_relic_cancel",
				type = "checkbox",
				default_value = false,
			},
			{
				setting_id = "enable_prevent_ability_aiming",
				type = "checkbox",
				default_value = false,
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
	},
}
