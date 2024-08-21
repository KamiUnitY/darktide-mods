local mod = get_mod("guarantee_special_action")

return {
	name = mod:localize("mod_name"),
	description = mod:localize("mod_description"),
	is_togglable = true,
	options = {
		widgets = {
			{
				setting_id = "enable_blocking_cancel_special",
				type = "checkbox",
				default_value = true,
			},
			{
				setting_id = "enable_ads_cancel_special",
				type = "checkbox",
				default_value = true,
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
