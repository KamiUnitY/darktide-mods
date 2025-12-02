local mod = get_mod("guarantee_weapon_swap")

return {
	name = mod:localize("mod_name"),
	description = mod:localize("mod_description"),
	is_togglable = true,
	options = {
		widgets = {
			{
				setting_id = "queue_limit",
				type            = "numeric",
				default_value   = 3,
				range           = { 1, 5 }
			},
			{
				setting_id = "enable_quick_grenades",
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
